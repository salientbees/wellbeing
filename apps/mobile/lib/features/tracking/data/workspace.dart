import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/storage/account_store.dart';
import '../domain/entry.dart';

/// The only write path used by widgets: commit encrypted projection + outbox first.
class Workspace extends ChangeNotifier {
  Workspace(this.store, this.api, this.account);
  final AccountStore store;
  final ApiClient api;
  Map<String, dynamic> account;
  final Map<String, Entry> _entries = {};
  final List<Map<String, dynamic>> _operations = [];
  String? _cursor;
  bool _closed = false;
  bool syncing = false;
  String? syncError;
  Future<void> _serial = Future.value();
  Future<void>? _syncFuture;
  Timer? _timer;
  int get pendingCount => _operations.length;
  int get pendingDeletionCount =>
      _entries.values.where((e) => e.deleted && e.state != 'synced').length;
  List<Entry> all(EntryKind kind) =>
      _entries.values.where((e) => e.kind == kind && !e.deleted).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  List<Entry> get entries => _entries.values.where((e) => !e.deleted).toList();
  String _entryKey(EntryKind kind, String id) => 'entry:${kind.route}:$id';
  Future<void> initialize() async {
    for (final value in await store.entries()) {
      if (value['kind'] == 'entry') {
        final entry = Entry.fromJson(value);
        _entries[_entryKey(entry.kind, entry.id)] = entry;
      }
      if (value['kind'] == 'operation') {
        _operations.add(Map<String, dynamic>.from(value['operation'] as Map));
      }
      if (value['kind'] == 'sync') _cursor = value['cursor'] as String?;
    }
    _operations.sort(
      (a, b) => (a['operationCreatedAt'] as String).compareTo(
        b['operationCreatedAt'] as String,
      ),
    );
    await store.put('account', {'kind': 'account', 'value': account});
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(synchronize()),
    );
    notifyListeners();
    unawaited(synchronize());
  }

  Future<void> _locked(Future<void> Function() action) {
    final next = _serial.then((_) {
      if (_closed) throw StateError('Account closed');
      return action();
    });
    _serial = next.catchError((Object _) {});
    return next;
  }

  Future<void> save(
    EntryKind kind,
    Map<String, dynamic> payload, {
    String? id,
    bool delete = false,
  }) => _locked(() async {
    final entityId =
        id ??
        (kind == EntryKind.checkIn
            ? payload['localDate'] as String
            : const Uuid().v4());
    final key = _entryKey(kind, entityId);
    final old = _entries[key];
    if (old?.state == 'conflict') {
      throw const ApiFailure('RESOLVE_CONFLICT_FIRST');
    }
    final queued = _operations
        .where(
          (op) => op['entityId'] == entityId && op['entityType'] == kind.route,
        )
        .toList();
    final base = queued.isNotEmpty
        ? (queued.last['baseRevision'] as int) + 1
        : old?.revision ?? 0;
    final op = <String, dynamic>{
      'operationId': const Uuid().v4(),
      'entityType': kind.route,
      'entityId': entityId,
      'action': delete
          ? 'delete'
          : base == 0
          ? 'create'
          : 'update',
      'baseRevision': base,
      'operationCreatedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': delete ? <String, dynamic>{} : payload,
    };
    final entry = Entry(
      id: entityId,
      kind: kind,
      payload: payload,
      revision: old?.revision ?? 0,
      deleted: delete,
      state: 'savedOnDevice',
    );
    await store.transaction(() async {
      await store.put(key, entry.toJson());
      await store.put('op:${op['operationId']}', {
        'kind': 'operation',
        'operation': op,
      });
    });
    _entries[key] = entry;
    _operations.add(op);
    notifyListeners();
    unawaited(synchronize());
  });
  Future<void> synchronize() =>
      _syncFuture ??= _synchronize().whenComplete(() => _syncFuture = null);
  Future<void> _synchronize() async {
    if (_closed) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      // One entity chain at a time; submitted operation bytes never change on retry.
      final blocked = <String>{};
      for (final op in List<Map<String, dynamic>>.from(_operations)) {
        if (_closed) return;
        final kind = EntryKind.fromRoute(op['entityType'] as String);
        final id = op['entityId'] as String;
        final key = _entryKey(kind, id);
        if (blocked.contains(key)) continue;
        final response = await api.request(
          'POST',
          '/me/sync/mutations',
          data: {
            'operations': [op],
          },
        );
        if (_closed) return;
        final result = Map<String, dynamic>.from(
          (response['results'] as List).single as Map,
        );
        if (result['status'] != 'success' &&
            !const {
              'REVISION_CONFLICT',
              'CONFLICT',
              'VALIDATION_FAILED',
              'VALIDATION_ERROR',
              'ENTITY_DELETED',
              'NOT_FOUND',
              'OPERATION_EXPIRED',
              'RECONCILIATION_REQUIRED',
              'INVALID_OCCURRENCE_ID',
              'IDEMPOTENCY_CONFLICT',
            }.contains(result['code'])) {
          throw ApiFailure(result['code'] as String? ?? 'SYNC_UNAVAILABLE');
        }
        await _locked(() async {
          final old = _entries[key]!;
          if (result['status'] != 'success') {
            blocked.add(key);
            syncError = result['code'] as String;
            final entry = Entry(
              id: id,
              kind: kind,
              payload: old.payload,
              revision: old.revision,
              deleted: old.deleted,
              state: 'conflict',
              server: result['current'] == null
                  ? null
                  : Map<String, dynamic>.from(result['current'] as Map),
            );
            await store.put(key, entry.toJson());
            _entries[key] = entry;
            return;
          }
          final remains = _operations.any(
            (other) =>
                other != op &&
                other['entityId'] == id &&
                other['entityType'] == kind.route,
          );
          final entry = Entry(
            id: id,
            kind: kind,
            payload: old.payload,
            revision: result['revision'] as int,
            deleted: old.deleted,
            state: remains ? 'savedOnDevice' : 'synced',
          );
          await store.transaction(() async {
            await store.remove('op:${op['operationId']}');
            await store.put(key, entry.toJson());
          });
          _operations.removeWhere(
            (other) => other['operationId'] == op['operationId'],
          );
          _entries[key] = entry;
        });
      }
      for (var page = 0; page < 100; page++) {
        final result = await api.request(
          'GET',
          '/me/sync/changes${_cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(_cursor!)}'}',
        );
        if (_closed) return;
        await _locked(() async {
          final updates = <String, Entry>{};
          final nextCursor = result['nextCursor'] as String;
          final latestAccount = result['account'] == null
              ? null
              : Map<String, dynamic>.from(result['account'] as Map);
          await store.transaction(() async {
            for (final raw in result['changes'] as List) {
              final change = Map<String, dynamic>.from(raw as Map);
              if (change['entity'] == null) continue;
              final entry = Entry.fromJson(
                Map<String, dynamic>.from(change['entity'] as Map),
              );
              final key = _entryKey(entry.kind, entry.id);
              if (_operations.any(
                (op) =>
                    op['entityId'] == entry.id &&
                    op['entityType'] == entry.kind.route,
              )) {
                continue;
              }
              if ((_entries[key]?.revision ?? -1) <= entry.revision) {
                await store.put(key, entry.toJson());
                updates[key] = entry;
              }
            }
            await store.put('sync', {'kind': 'sync', 'cursor': nextCursor});
            if (latestAccount != null) {
              await store.put('account', {
                'kind': 'account',
                'value': latestAccount,
              });
            }
          });
          if (latestAccount != null) account = latestAccount;
          _entries.addAll(updates);
          _cursor = nextCursor;
        });
        if ((result['changes'] as List).length < 100) break;
      }
    } on ApiFailure catch (error) {
      syncError = error.code;
      if (error.code == 'CURSOR_EXPIRED') {
        try {
          await _rebuild();
          syncError = null;
        } catch (_) {
          syncError = 'SYNC_UNAVAILABLE';
        }
      }
    } catch (_) {
      syncError = 'SYNC_UNAVAILABLE';
    } finally {
      if (!_closed) {
        syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshAccount() async {
    final latest = await api.request('GET', '/me');
    await _locked(() async {
      await store.put('account', {'kind': 'account', 'value': latest});
      account = latest;
      notifyListeners();
    });
  }

  Future<void> updatePreferences(
    String kind,
    Map<String, dynamic> request,
  ) async {
    if (!const {'profile', 'settings', 'consents'}.contains(kind)) {
      throw ArgumentError.value(kind);
    }
    final result = await api.request(
      kind == 'consents' ? 'POST' : 'PATCH',
      '/me/$kind',
      data: request,
    );
    final latest = Map<String, dynamic>.from(result['account'] as Map);
    await _locked(() async {
      await store.put('account', {'kind': 'account', 'value': latest});
      account = latest;
      notifyListeners();
    });
  }

  Future<void> useServer(Entry conflict) => _locked(() async {
    final matching = _operations
        .where(
          (op) =>
              op['entityId'] == conflict.id &&
              op['entityType'] == conflict.kind.route,
        )
        .toList();
    final key = _entryKey(conflict.kind, conflict.id);
    await store.transaction(() async {
      for (final op in matching) {
        await store.remove('op:${op['operationId']}');
      }
      if (conflict.server == null) {
        await store.remove(key);
      } else {
        await store.put(key, Entry.fromJson(conflict.server!).toJson());
      }
    });
    _operations.removeWhere((op) => matching.contains(op));
    if (conflict.server == null) {
      _entries.remove(key);
    } else {
      _entries[key] = Entry.fromJson(conflict.server!);
    }
    notifyListeners();
  });
  Future<void> close({bool erase = false}) async {
    if (_closed) return;
    _timer?.cancel();
    _closed = true;
    api.close();
    await _serial;
    if (erase) {
      await store.destroy();
    } else {
      await store.close();
    }
  }

  Future<void> _rebuild() async {
    final baseline = <String, Entry>{};
    String? cursor;
    String? replay;
    do {
      final page = await api.request(
        'GET',
        '/me/sync/snapshot${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
      );
      for (final raw in page['entities'] as List) {
        final entry = Entry.fromJson(Map<String, dynamic>.from(raw as Map));
        baseline[_entryKey(entry.kind, entry.id)] = entry;
      }
      cursor = page['nextCursor'] as String?;
      replay = page['replayCursor'] as String;
    } while (cursor != null && !_closed);
    if (_closed) return;
    // Apply replay before installing the new baseline; drafts stay separate.
    while (true) {
      final page = await api.request(
        'GET',
        '/me/sync/changes?cursor=${Uri.encodeQueryComponent(replay!)}',
      );
      for (final raw in page['changes'] as List) {
        final item = (raw as Map)['entity'];
        if (item == null) continue;
        final entry = Entry.fromJson(Map<String, dynamic>.from(item as Map));
        baseline[_entryKey(entry.kind, entry.id)] = entry;
      }
      replay = page['nextCursor'] as String;
      if ((page['changes'] as List).length < 100) break;
    }
    await _locked(() async {
      final replacement = Map<String, Entry>.from(_entries);
      await store.transaction(() async {
        final pendingKeys = _operations
            .map((op) => 'entry:${op['entityType']}:${op['entityId']}')
            .toSet();
        for (final key in _entries.keys.toList()) {
          if (!pendingKeys.contains(key)) {
            await store.remove(key);
            replacement.remove(key);
          }
        }
        for (final item in baseline.entries) {
          if (!pendingKeys.contains(item.key)) {
            await store.put(item.key, item.value.toJson());
            replacement[item.key] = item.value;
          }
        }
        await store.put('sync', {'kind': 'sync', 'cursor': replay});
      });
      _entries
        ..clear()
        ..addAll(replacement);
      _cursor = replay;
    });
  }
}

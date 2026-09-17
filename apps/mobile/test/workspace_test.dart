import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellbeing/core/api/api_client.dart';
import 'package:wellbeing/core/storage/account_store.dart';
import 'package:wellbeing/features/tracking/data/workspace.dart';
import 'package:wellbeing/features/tracking/domain/entry.dart';

class TestApi implements ApiClient {
  String? failure = 'OFFLINE';
  String? operationFailure;
  final submitted = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
  }) async {
    if (failure != null) throw ApiFailure(failure!);
    if (method == 'POST') {
      final op = ((data as Map)['operations'] as List).single as Map;
      submitted.add(jsonEncode(op));
      return {
        'results': [
          operationFailure != null
              ? {'status': 'error', 'code': operationFailure}
              : {
                  'status': 'success',
                  'revision': (op['baseRevision'] as int) + 1,
                },
        ],
      };
    }
    return {'changes': <Object>[], 'nextCursor': 'test-cursor'};
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('offline queue survives reopening and temporary per-operation errors retry unchanged', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wellbeing-workspace-',
    );
    final file = File('${directory.path}/account.sqlite');
    final key = await AesGcm.with256bits().newSecretKey();
    final api = TestApi();
    var workspace = Workspace(AccountStore(file, key, 'synthetic'), api, {});
    try {
      await workspace.initialize();
      await workspace.synchronize();
      await workspace.save(EntryKind.weight, {
        'localDate': '2026-09-17',
        'weightKg': 70,
      });
      await workspace.synchronize();
      expect(workspace.pendingCount, 1);
      await workspace.close();
      workspace = Workspace(AccountStore(file, key, 'synthetic'), api, {});
      await workspace.initialize();
      await workspace.synchronize();
      expect(workspace.all(EntryKind.weight).single.payload['weightKg'], 70);
      api.failure = null;
      api.operationFailure = 'RATE_LIMITED';
      await workspace.synchronize();
      expect(workspace.pendingCount, 1);
      expect(workspace.all(EntryKind.weight).single.state, 'savedOnDevice');
      api.operationFailure = null;
      await workspace.synchronize();
      expect(workspace.pendingCount, 0);
      expect(workspace.all(EntryKind.weight).single.state, 'synced');
      expect(api.submitted.length, 2);
      expect(api.submitted.first, api.submitted.last);
    } finally {
      await workspace.close();
      await directory.delete(recursive: true);
    }
  });
  test('revision conflict retains the local draft and operation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wellbeing-conflict-',
    );
    final key = await AesGcm.with256bits().newSecretKey();
    final api = TestApi();
    final workspace = Workspace(
      AccountStore(File('${directory.path}/account.sqlite'), key, 'synthetic'),
      api,
      {},
    );
    try {
      await workspace.initialize();
      await workspace.synchronize();
      await workspace.save(EntryKind.hydration, {
        'localDate': '2026-09-17',
        'volumeMl': 250,
      });
      await workspace.synchronize();
      api.failure = null;
      api.operationFailure = 'REVISION_CONFLICT';
      await workspace.synchronize();
      expect(workspace.pendingCount, 1);
      expect(workspace.all(EntryKind.hydration).single.state, 'conflict');
      expect(
        workspace.all(EntryKind.hydration).single.payload['volumeMl'],
        250,
      );
    } finally {
      await workspace.close();
      await directory.delete(recursive: true);
    }
  });
}

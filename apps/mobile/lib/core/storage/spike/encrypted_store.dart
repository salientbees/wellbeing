import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// P1 feasibility only: authenticated payload encryption over Drift, not SQLCipher.
/// No production repository consumes this store. Query design remains a P3 gate.
class EncryptedStore extends GeneratedDatabase {
  EncryptedStore(File file, {required this.key, required this.accountScope})
    : super(
        NativeDatabase(
          file,
          setup: (db) {
            db.execute('PRAGMA journal_mode=WAL;');
            db.execute('PRAGMA temp_store=MEMORY;');
            db.execute('PRAGMA synchronous=FULL;');
          },
        ),
      );

  final SecretKey key;
  final String accountScope;
  final _cipher = AesGcm.with256bits();
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE records (id TEXT PRIMARY KEY, payload BLOB NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, payload BLOB NOT NULL)',
      );
    },
  );

  List<int> _aad(String kind, String id) =>
      utf8.encode(jsonEncode([1, accountScope, kind, id]));
  Future<Uint8List> _seal(
    String kind,
    String id,
    Map<String, Object?> value,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      aad: _aad(kind, id),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Stable opaque IDs only. Payload and operation are committed together.
  Future<void> save({
    required String recordId,
    required String operationId,
    required Map<String, Object?> record,
    required Map<String, Object?> operation,
  }) async {
    final recordBytes = await _seal('record', recordId, record);
    final operationBytes = await _seal('operation', operationId, operation);
    await transaction(() async {
      await customStatement('INSERT OR REPLACE INTO records VALUES (?, ?)', [
        recordId,
        recordBytes,
      ]);
      // Duplicate immutable operation IDs fail and roll back the projection.
      await customStatement('INSERT INTO outbox VALUES (?, ?)', [
        operationId,
        operationBytes,
      ]);
    });
  }

  Future<Map<String, Object?>?> readRecord(String id) async {
    final row = await customSelect(
      'SELECT payload FROM records WHERE id = ?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final box = SecretBox.fromConcatenation(
      row.read<Uint8List>('payload'),
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: _aad('record', id),
    );
    return (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  Future<int> pendingCount() async => (await customSelect(
    'SELECT COUNT(*) AS count FROM outbox',
  ).getSingle()).read<int>('count');
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Account-isolated authenticated payload storage. Health fields never enter SQL.
class AccountStore extends GeneratedDatabase {
  AccountStore(File file, this.key, this.scope)
    : super(
        NativeDatabase(
          file,
          setup: (db) {
            db.execute(
              'PRAGMA journal_mode=WAL; PRAGMA temp_store=MEMORY; PRAGMA synchronous=FULL;',
            );
          },
        ),
      );
  final SecretKey key;
  final String scope;
  final _cipher = AesGcm.with256bits();
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE vault (id TEXT PRIMARY KEY, payload BLOB NOT NULL)',
      );
    },
  );
  static const _secure = FlutterSecureStorage();
  static Future<AccountStore> open(String uid) async {
    final digest = await Sha256().hash(utf8.encode(uid));
    final scope = base64UrlEncode(digest.bytes).replaceAll('=', '');
    final keyName = 'wellbeing_vault_$scope';
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/vault_$scope.sqlite');
    var encoded = await _secure.read(key: keyName);
    if (encoded == null) {
      if (await file.exists()) throw StateError('LOCAL_KEY_UNAVAILABLE');
      encoded = base64Encode(
        await (await AesGcm.with256bits().newSecretKey()).extractBytes(),
      );
      await _secure.write(key: keyName, value: encoded);
    }
    return AccountStore(file, SecretKey(base64Decode(encoded)), scope);
  }

  Future<Map<String, dynamic>?> get(String id) async {
    final row = await customSelect(
      'SELECT payload FROM vault WHERE id=?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final box = SecretBox.fromConcatenation(
      row.read<Uint8List>('payload'),
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode('$scope:$id:v1'),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
  }

  Future<void> put(String id, Map<String, dynamic> value) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      aad: utf8.encode('$scope:$id:v1'),
    );
    await customStatement('INSERT OR REPLACE INTO vault VALUES (?,?)', [
      id,
      Uint8List.fromList(box.concatenation()),
    ]);
  }

  Future<void> remove(String id) =>
      customStatement('DELETE FROM vault WHERE id=?', [id]);
  Future<List<Map<String, dynamic>>> entries() async {
    final ids = await customSelect('SELECT id FROM vault').get();
    return [for (final row in ids) (await get(row.read<String>('id')))!];
  }

  Future<void> destroy() async {
    await customStatement('DELETE FROM vault');
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await _secure.delete(key: 'wellbeing_vault_$scope');
    await close();
    final directory = await getApplicationSupportDirectory();
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${directory.path}/vault_$scope.sqlite$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}

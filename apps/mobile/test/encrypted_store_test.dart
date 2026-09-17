import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellbeing/core/storage/spike/encrypted_store.dart';

void main() {
  test(
    'durable encrypted projection/outbox, rollback, owner binding and key loss',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wellbeing-storage-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      final key = await AesGcm.with256bits().newSecretKey();
      var store = EncryptedStore(file, key: key, accountScope: 'synthetic-a');
      const record = {
        'note': 'SENSITIVE_SYNTHETIC_SENTINEL_4281',
        'weightKg': 72.34567,
      };
      await store.save(
        recordId: 'opaque-1',
        operationId: 'op-1',
        record: record,
        operation: {'record': record},
      );
      await expectLater(
        store.save(
          recordId: 'opaque-1',
          operationId: 'op-1',
          record: {'note': 'incorrect overwrite'},
          operation: {},
        ),
        throwsA(anything),
      );
      expect(await store.readRecord('opaque-1'), record);
      expect(await store.pendingCount(), 1);
      for (final artifact in dir.listSync().whereType<File>()) {
        final bytes = latin1.decode(await artifact.readAsBytes());
        expect(
          bytes.contains('SENSITIVE_SYNTHETIC_SENTINEL_4281'),
          false,
          reason: artifact.path,
        );
        expect(bytes.contains('72.34567'), false, reason: artifact.path);
      }
      await store.close();
      store = EncryptedStore(file, key: key, accountScope: 'synthetic-a');
      expect(await store.readRecord('opaque-1'), record);
      expect(await store.pendingCount(), 1);
      await store.close();
      store = EncryptedStore(file, key: key, accountScope: 'synthetic-b');
      await expectLater(
        store.readRecord('opaque-1'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await store.close();
      store = EncryptedStore(
        file,
        key: await AesGcm.with256bits().newSecretKey(),
        accountScope: 'synthetic-a',
      );
      await expectLater(
        store.readRecord('opaque-1'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await store.close();
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wellbeing/app/wellbeing_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wellbeing/core/storage/spike/encrypted_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android shell and encrypted storage with platform key protection',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: WellbeingApp()));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Wellbeing'), findsOneWidget);
      await tester.tap(find.text('Track').last);
      await tester.pumpAndSettle();
      expect(find.text('Your daily wellbeing'), findsOneWidget);
      const secure = FlutterSecureStorage();
      const keyId = 'wellbeing_p1_synthetic_key';
      final key = await AesGcm.with256bits().newSecretKey();
      final encoded = base64Encode(await key.extractBytes());
      await secure.write(key: keyId, value: encoded);
      final restoredKey = SecretKey(
        base64Decode((await secure.read(key: keyId))!),
      );
      final support = await getApplicationSupportDirectory();
      final dir = await Directory('${support.path}/p1-synthetic').create();
      final file = File('${dir.path}/cache.sqlite');
      if (await file.exists()) await file.delete();
      var store = EncryptedStore(
        file,
        key: restoredKey,
        accountScope: 'synthetic-a',
      );
      const record = {
        'note': 'DEVICE_SYNTHETIC_SENTINEL_98245',
        'weightKg': 72.34567,
      };
      await store.save(
        recordId: 'opaque-1',
        operationId: 'op-1',
        record: record,
        operation: {'record': record},
      );
      for (final artifact in dir.listSync().whereType<File>()) {
        final contents = latin1.decode(await artifact.readAsBytes());
        expect(contents.contains('DEVICE_SYNTHETIC_SENTINEL_98245'), false);
        expect(contents.contains('72.34567'), false);
        expect(contents.contains(encoded), false);
      }
      await store.close();
      store = EncryptedStore(
        file,
        key: restoredKey,
        accountScope: 'synthetic-a',
      );
      expect(await store.readRecord('opaque-1'), record);
      expect(await store.pendingCount(), 1);
      await store.close();
      await secure.delete(key: keyId);
      expect(await secure.read(key: keyId), isNull);
      // Retain only encrypted synthetic artifacts for external inspection.
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );
}

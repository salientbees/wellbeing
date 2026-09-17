import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellbeing/core/api/api_client.dart';
import 'package:wellbeing/core/storage/account_store.dart';
import 'package:wellbeing/features/tracking/data/workspace.dart';
import 'package:wellbeing/features/settings/presentation/settings_screen.dart';
import 'package:wellbeing/features/progress/presentation/progress_screen.dart';

class OfflinePreferencesApi implements ApiClient {
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
  }) async {
    requests.add(jsonEncode(data));
    throw const ApiFailure('OFFLINE');
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late Workspace workspace;
  late OfflinePreferencesApi api;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wellbeing-settings-');
    api = OfflinePreferencesApi();
    workspace = Workspace(
      AccountStore(
        File('${directory.path}/test.sqlite'),
        await AesGcm.with256bits().newSecretKey(),
        'fixture',
      ),
      api,
      {
        'profile': {
          'revision': 1,
          'preferredName': 'Test',
          'timeZone': 'Etc/UTC',
          'coachingTone': 'gentle',
        },
        'settings': {
          'revision': 1,
          'theme': 'system',
          'reduceMotion': false,
          'hiddenMetrics': ['weight', 'nutrition'],
          'weekStartsOn': 1,
          'notificationPreferences': {
            'enabled': false,
            'quietStart': '22:00',
            'quietEnd': '07:00',
          },
        },
      },
    );
  });
  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });
  testWidgets('uncertain profile save retains identical operation for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PreferenceEditor(workspace: workspace, kind: 'profile'),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Preferred name'),
      'New name',
    );
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save was not confirmed'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Preferred name'))
          .enabled,
      false,
    );
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(api.requests.length, 2);
    expect(api.requests.first, api.requests.last);
    expect(workspace.account['profile']['preferredName'], 'Test');
  });
  testWidgets('settings supports large text without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: PreferenceEditor(workspace: workspace, kind: 'settings'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Save preferences'), 300);
    expect(tester.takeException(), isNull);
  });
  testWidgets('hidden metrics do not appear in progress selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProgressScreen(workspace: workspace)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Weight'), findsNothing);
    expect(find.text('Energy'), findsNothing);
    expect(find.text('Hydration'), findsWidgets);
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wellbeing/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account tracking, profile editing, consent revocation and sign-out',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();
      // The fixture exists exclusively in demo-wellbeing's local Auth emulator.
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'wellbeing-e2e@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'Synthetic-only-password-42',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      for (
        var i = 0;
        i < 40 && find.text('Hello, Emulator Test').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Hello, Emulator Test'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Hydration'));
      await tester.pumpAndSettle();
      final numeric = find.widgetWithText(TextFormField, 'Volume (ml)');
      expect(numeric, findsOneWidget);
      await tester.enterText(numeric, '250');
      await tester.ensureVisible(find.text('Save on this device'));
      await tester.tap(find.text('Save on this device'));
      await tester.pumpAndSettle();
      expect(find.text('250 ml'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Account & preferences'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Preferred name'),
        'Emulator Updated',
      );
      await tester.tap(find.text('Save preferences'));
      for (
        var i = 0;
        i < 40 && find.text('Privacy choices').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(find.text('Privacy choices'), findsOneWidget);
      expect(find.text('Emulator Updated'), findsOneWidget);
      Future<void> toggle(String label, {required bool grant}) async {
        final tile = find.widgetWithText(SwitchListTile, label);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        if (grant) {
          await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
        }
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 500));
          final widget = tester.widget<SwitchListTile>(tile);
          if (widget.value == grant && widget.onChanged != null) break;
        }
        expect(tester.widget<SwitchListTile>(tile).value, grant);
      }

      await toggle('AI coaching', grant: true);
      await toggle('Coach memory', grant: true);
      await toggle('AI coaching', grant: false);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Coach memory'),
            )
            .value,
        false,
      );
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Sign out'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

# Wellbeing mobile foundation

Flutter 3.47.4 / Dart 3.13.3. The authoritative design is in the repository's `docs/` directory. See [local setup and P1 gates](../../docs/LOCAL_DEVELOPMENT.md).

Implemented here: Riverpod-managed five-tab go_router shell, Material 3 themes, generated localization, accessibility checks and an isolated authenticated-encryption/Drift spike. This is an initial foundation, not the complete wellbeing application. No authentication, health tracking, coaching or reminders are connected yet.

Run `flutter analyze` and `flutter test`. Build Android with `flutter build apk --debug`; on this Windows machine use the Java wrapper documented above. Run the synthetic Android test with `flutter test integration_test/foundation_test.dart -d emulator-5554`.

Do not place server API keys, service-account files or signing keys in this application. Android backups and device transfers are excluded. iOS validation requires macOS/Xcode and remains pending.

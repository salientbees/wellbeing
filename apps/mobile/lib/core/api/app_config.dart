import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

abstract final class AppConfig {
  static const emulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  static const emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const apiUrl = String.fromEnvironment('API_BASE_URL');
  static bool get configured => emulators
      ? !kReleaseMode
      : [projectId, apiKey, appId, senderId, apiUrl].every((s) => s.isNotEmpty);
  static String get endpoint =>
      emulators ? 'http://$emulatorHost:8787/v1' : apiUrl;
  static FirebaseOptions get firebaseOptions {
    if (!configured || (!emulators && !Uri.parse(apiUrl).isScheme('https'))) {
      throw StateError('Invalid environment configuration');
    }
    return FirebaseOptions(
      apiKey: emulators ? 'demo-emulator-placeholder' : apiKey,
      appId: emulators ? '1:1234567890:android:localdemo' : appId,
      messagingSenderId: emulators ? '1234567890' : senderId,
      projectId: emulators ? 'demo-wellbeing' : projectId,
    );
  }
}

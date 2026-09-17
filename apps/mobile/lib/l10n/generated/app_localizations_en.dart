// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Wellbeing';

  @override
  String get home => 'Home';

  @override
  String get track => 'Track';

  @override
  String get coach => 'Coach';

  @override
  String get progress => 'Progress';

  @override
  String get plan => 'Plan';

  @override
  String get welcome => 'Welcome to Wellbeing';

  @override
  String get welcomeBody =>
      'A private space to understand your daily wellbeing, one day at a time.';

  @override
  String get foundationNotice =>
      'This early version does not yet save entries or connect to your account.';

  @override
  String get trackTitle => 'Your daily wellbeing';

  @override
  String get trackBody =>
      'Your daily entries will belong here. Tracking is not available in this version yet.';

  @override
  String get coachTitle => 'A little space to reflect';

  @override
  String get coachBody =>
      'Coaching is not connected yet. When available, you can choose whether to share your data with the coach.';

  @override
  String get progressTitle => 'Your story over time';

  @override
  String get progressBody =>
      'There is no history to show yet. Progress will be based on your recorded entries.';

  @override
  String get planTitle => 'Make room for yourself';

  @override
  String get planBody =>
      'Planning and reminders are not available in this version yet.';

  @override
  String get notFound => 'This page is not available.';
}

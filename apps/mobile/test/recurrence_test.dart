import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:wellbeing/features/notifications/domain/recurrence.dart';

void main() {
  setUpAll(data.initializeTimeZones);
  test('spring gap advances to first valid instant, fall fold occurs once', () {
    final zone = tz.getLocation('America/New_York');
    final gap = resolveWallTime(zone, DateTime.utc(2026, 3, 8, 2, 30));
    expect(gap.instant, DateTime.utc(2026, 3, 8, 7));
    expect(gap.resolution, 'gapAdvanced');
    final fold = resolveWallTime(zone, DateTime.utc(2026, 11, 1, 1, 30));
    expect(fold.instant, DateTime.utc(2026, 11, 1, 5, 30));
    expect(fold.resolution, 'firstFold');
  });
  Map<String, dynamic> schedule(String time) => {
    'status': 'active',
    'kind': 'daily',
    'zoneMode': 'fixed',
    'timeZone': 'Etc/UTC',
    'localTime': time,
    'startDate': '2026-09-17',
    'weekdays': <int>[],
    'skipDates': <String>[],
  };
  List<ReminderOccurrence> plan(String time, {bool enabled = true}) =>
      planReminder(
        reminderId: 'one',
        scheduleRevision: 2,
        schedule: schedule(time),
        now: DateTime.utc(2026, 9, 17),
        profileZone: 'Asia/Kolkata',
        channelOwner: 'local:device-a',
        enabled: enabled,
        quietStart: '22:00',
        quietEnd: '07:00',
      );
  test(
    'overnight quiet hours defer useful reminders and skip expired ones',
    () {
      expect(plan('06:00').first.dueAt, DateTime.utc(2026, 9, 17, 7));
      expect(plan('23:00'), isEmpty);
      expect(plan('08:00', enabled: false), isEmpty);
    },
  );
  test('revision-bound keys deduplicate and the device cap is global', () {
    final occurrences = plan('08:00');
    expect(deviceWindow([...occurrences, ...occurrences]).length, 7);
    final many = List.generate(
      40,
      (i) => ReminderOccurrence(
        key: '$i',
        dueAt: DateTime.utc(2026, 9, 17, 8, i),
        expiresAt: DateTime.utc(2026, 9, 17, 10),
        resolution: 'exact',
      ),
    );
    expect(deviceWindow(many).length, 32);
  });
}

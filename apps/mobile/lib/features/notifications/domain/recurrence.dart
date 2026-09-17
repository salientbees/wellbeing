import 'package:timezone/timezone.dart' as tz;

class ResolvedWallTime {
  const ResolvedWallTime(this.instant, this.resolution);
  final DateTime instant;
  final String resolution;
}

/// Finds both sides of an offset transition instead of relying on a timezone
/// constructor's implicit choice for ambiguous or nonexistent local times.
ResolvedWallTime resolveWallTime(tz.Location zone, DateTime wall) {
  final nominal = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  final offsets = <Duration>{};
  for (var hour = -36; hour <= 36; hour++) {
    offsets.add(
      tz.TZDateTime.from(
        nominal.add(Duration(hours: hour)),
        zone,
      ).timeZoneOffset,
    );
  }
  for (var minute = 0; minute <= 1440; minute++) {
    final target = nominal.add(Duration(minutes: minute));
    final candidates = <DateTime>[];
    for (final offset in offsets) {
      final instant = target.subtract(offset);
      final local = tz.TZDateTime.from(instant, zone);
      if (local.year == target.year &&
          local.month == target.month &&
          local.day == target.day &&
          local.hour == target.hour &&
          local.minute == target.minute) {
        candidates.add(instant);
      }
    }
    if (candidates.isNotEmpty) {
      candidates.sort();
      return ResolvedWallTime(
        candidates.first,
        minute > 0
            ? 'gapAdvanced'
            : candidates.length > 1
            ? 'firstFold'
            : 'exact',
      );
    }
  }
  throw StateError('Unable to resolve local date in timezone');
}

String localDateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.key,
    required this.dueAt,
    required this.expiresAt,
    required this.resolution,
  });
  final String key;
  final DateTime dueAt, expiresAt;
  final String resolution;
}

/// Pure seven-day planner. Delivery adapters must additionally recheck current
/// permission, revision and channel ownership before submitting an occurrence.
List<ReminderOccurrence> planReminder({
  required String reminderId,
  required int scheduleRevision,
  required Map<String, dynamic> schedule,
  required DateTime now,
  required String profileZone,
  required String channelOwner,
  required bool enabled,
  required String quietStart,
  required String quietEnd,
}) {
  if (!enabled || schedule['status'] != 'active') return [];
  final zoneName = schedule['zoneMode'] == 'followProfile'
      ? profileZone
      : schedule['timeZone'] as String;
  final zone = tz.getLocation(zoneName);
  final today = tz.TZDateTime.from(now, zone);
  final time = (schedule['localTime'] as String)
      .split(':')
      .map(int.parse)
      .toList();
  int minutes(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return parts[0] * 60 + parts[1];
  }

  final quietFrom = minutes(quietStart), quietUntil = minutes(quietEnd);
  final occurrences = <ReminderOccurrence>[];
  for (var offset = 0; offset < 7; offset++) {
    final date = DateTime.utc(today.year, today.month, today.day + offset);
    final key = localDateKey(date);
    if (key.compareTo(schedule['startDate'] as String) < 0 ||
        (schedule['endDate'] != null &&
            key.compareTo(schedule['endDate'] as String) > 0) ||
        (schedule['skipDates'] as List).contains(key)) {
      continue;
    }
    if (schedule['kind'] == 'oneOff' && key != schedule['startDate']) continue;
    if (schedule['kind'] == 'weekly' &&
        !(schedule['weekdays'] as List).contains(date.weekday)) {
      continue;
    }
    final wall = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time[0],
      time[1],
    );
    final resolved = resolveWallTime(zone, wall);
    // Never replay an occurrence that was already due during offline recovery.
    if (!resolved.instant.isAfter(now)) continue;
    final expires = resolved.instant.add(const Duration(hours: 2));
    var due = resolved.instant;
    final local = tz.TZDateTime.from(due, zone);
    final minute = local.hour * 60 + local.minute;
    final overnight = quietFrom > quietUntil;
    final quiet =
        quietFrom != quietUntil &&
        (overnight
            ? minute >= quietFrom || minute < quietUntil
            : minute >= quietFrom && minute < quietUntil);
    if (quiet) {
      final extraDay = overnight && minute >= quietFrom ? 1 : 0;
      due = resolveWallTime(
        zone,
        DateTime.utc(
          local.year,
          local.month,
          local.day + extraDay,
          quietUntil ~/ 60,
          quietUntil % 60,
        ),
      ).instant;
      if (due.isAfter(expires)) continue;
    }
    occurrences.add(
      ReminderOccurrence(
        key:
            '$reminderId|$scheduleRevision|${key}T${schedule['localTime']}|$zoneName|$channelOwner',
        dueAt: due,
        expiresAt: expires,
        resolution: resolved.resolution,
      ),
    );
  }
  return occurrences;
}

/// The limit applies across all reminders, not separately to each reminder.
List<ReminderOccurrence> deviceWindow(
  Iterable<ReminderOccurrence> occurrences,
) {
  final unique = {
    for (final occurrence in occurrences) occurrence.key: occurrence,
  };
  final result = unique.values.toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return result.take(32).toList();
}

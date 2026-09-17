import 'package:flutter_test/flutter_test.dart';
import 'package:wellbeing/features/progress/domain/metrics.dart';
import 'package:wellbeing/features/tracking/domain/entry.dart';

void main() {
  const day = '2026-09-17';
  Entry record(EntryKind kind, Map<String, dynamic> fields) =>
      Entry(id: 'test', kind: kind, payload: {'localDate': day, ...fields});
  Metric metric(List<Entry> entries, String name) =>
      dailyMetrics(entries, day).firstWhere((m) => m.label == name);

  test(
    'missing records are unknown, while explicitly recorded zero is zero',
    () {
      expect(dailyMetrics([], day).every((m) => m.value == null), isTrue);
      final steps = record(EntryKind.activity, {
        'steps': 0,
        'startAt': '${day}T08:00:00Z',
        'endAt': '${day}T09:00:00Z',
      });
      expect(metric([steps], 'Steps').value, 0);
    },
  );
  test('weight median resists outliers and ignores deleted records', () {
    final values = [
      70,
      71,
      150,
    ].map((v) => record(EntryKind.weight, {'weightKg': v})).toList();
    values.add(
      Entry(
        id: 'deleted',
        kind: EntryKind.weight,
        deleted: true,
        payload: {'localDate': day, 'weightKg': 300},
      ),
    );
    expect(metric(values, 'Weight').value, 71);
  });
  test('overlapping step entries cannot silently double count', () {
    final values = [8, 9]
        .map(
          (hour) => record(EntryKind.activity, {
            'steps': 1000,
            'startAt': '${day}T0$hour:00:00Z',
            'endAt': '${day}T10:00:00Z',
          }),
        )
        .toList();
    expect(metric(values, 'Steps').value, isNull);
    expect(metric(values, 'Steps').note, contains('Overlapping'));
  });
  test(
    'exercise intervals are unioned, including nested and touching intervals',
    () {
      DateTime time(int hour) => DateTime.utc(2026, 9, 17, hour);
      expect(
        unionSeconds([
          (time(8), time(10)),
          (time(9), time(10)),
          (time(10), time(11)),
        ]),
        10800,
      );
    },
  );
  test('food basis conversions preserve unknown nutrients', () {
    final food = record(EntryKind.food, {
      'items': [
        {'quantity': 2, 'basis': 'perPortion', 'energyKcal': 100},
        {'quantity': 1, 'basis': 'per100g', 'grams': 50, 'energyKcal': 300},
        {'quantity': 1, 'basis': 'perPortion'},
      ],
    });
    expect(metric([food], 'Energy').value, 350);
    expect(metric([food], 'Energy').note, contains('1 food items'));
    expect(metric([food], 'Protein').value, isNull);
  });
  test('decreasing goal progress is bounded without inventing missing measurements', () {
    final goal = record(EntryKind.goals, {
      'direction': 'decrease',
      'baseline': 80,
      'target': 70,
    });
    expect(goalProgress(goal, 75), .5);
    expect(goalProgress(goal, 65), 1);
    expect(goalProgress(goal, 85), 0);
    expect(goalProgress(goal, null), isNull);
  });
}

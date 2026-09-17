import '../../tracking/domain/entry.dart';

class Metric {
  const Metric(
    this.label,
    this.value,
    this.unit,
    this.records, {
    this.note = '',
  });
  final String label, unit, note;
  final double? value;
  final int records;
  String get display => value == null
      ? 'Not recorded'
      : '${value!.toStringAsFixed(value == value!.roundToDouble() ? 0 : 1)} $unit';
}

double? median(Iterable<double> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) return null;
  final middle = list.length ~/ 2;
  return list.length.isOdd
      ? list[middle]
      : (list[middle - 1] + list[middle]) / 2;
}

double unionSeconds(List<(DateTime, DateTime)> intervals) {
  if (intervals.isEmpty) return 0;
  final sorted = List.of(intervals)..sort((a, b) => a.$1.compareTo(b.$1));
  var start = sorted.first.$1, end = sorted.first.$2;
  var total = 0;
  for (final interval in sorted.skip(1)) {
    if (!interval.$1.isAfter(end)) {
      if (interval.$2.isAfter(end)) end = interval.$2;
    } else {
      total += end.difference(start).inSeconds;
      start = interval.$1;
      end = interval.$2;
    }
  }
  return (total + end.difference(start).inSeconds).toDouble();
}

List<Metric> dailyMetrics(List<Entry> entries, String date) {
  final day = entries.where((e) => !e.deleted && e.date == date).toList();
  List<Entry> group(EntryKind kind) =>
      day.where((e) => e.kind == kind).toList();
  Metric sum(EntryKind kind, String field, String label, String unit) {
    final rows = group(kind);
    final known = rows.where((e) => e.payload[field] is num).toList();
    return Metric(
      label,
      known.isEmpty
          ? null
          : known.fold<double>(
              0,
              (sum, e) => sum + (e.payload[field] as num).toDouble(),
            ),
      unit,
      known.length,
    );
  }

  final weights = group(EntryKind.weight);
  final mood = group(EntryKind.mood);
  final foods = group(EntryKind.food)
      .expand((e) => (e.payload['items'] as List).cast<Map>())
      .toList();
  Metric nutrient(String field, String label, String unit) {
    var count = 0;
    double total = 0;
    for (final item in foods) {
      if (item[field] is! num) continue;
      final factor = item['basis'] == 'per100g'
          ? (item['grams'] as num).toDouble() / 100
          : (item['quantity'] as num).toDouble();
      total += (item[field] as num).toDouble() * factor;
      count++;
    }
    return Metric(
      label,
      count == 0 ? null : total,
      unit,
      count,
      note: foods.length == count
          ? ''
          : 'Known subtotal; ${foods.length - count} food items have no value',
    );
  }

  final exercise = group(EntryKind.exercise);
  final activity = group(EntryKind.activity);
  final sleep = group(EntryKind.sleep);
  List<(DateTime, DateTime)> intervals(List<Entry> values) => values
      .map(
        (e) => (
          DateTime.parse(e.payload['startAt'] as String),
          DateTime.parse(e.payload['endAt'] as String),
        ),
      )
      .toList();
  bool overlaps(List<Entry> values) {
    final times = intervals(values);
    final sum = times.fold<double>(
      0,
      (sum, p) => sum + p.$2.difference(p.$1).inSeconds,
    );
    return unionSeconds(times) < sum;
  }

  final steps = sum(EntryKind.activity, 'steps', 'Steps', 'steps');
  final sleepKnown = sleep
      .where((e) => e.payload['awakeSeconds'] != null)
      .length;
  final sleepSeconds =
      unionSeconds(intervals(sleep)) -
      sleep.fold<double>(
        0,
        (sum, e) =>
            sum + ((e.payload['awakeSeconds'] as num?)?.toDouble() ?? 0),
      );
  return [
    Metric(
      'Weight',
      median(weights.map((e) => (e.payload['weightKg'] as num).toDouble())),
      'kg',
      weights.length,
      note: weights.length > 1 ? 'Daily median' : '',
    ),
    sum(EntryKind.hydration, 'volumeMl', 'Hydration', 'ml'),
    Metric(
      steps.label,
      overlaps(activity) ? null : steps.value,
      steps.unit,
      steps.records,
      note: overlaps(activity)
          ? 'Overlapping activity: resolve entries before totaling'
          : '',
    ),
    Metric(
      'Exercise',
      exercise.isEmpty ? null : unionSeconds(intervals(exercise)) / 60,
      'min',
      exercise.length,
      note: 'Union of recorded workout intervals',
    ),
    Metric(
      'Sleep',
      sleep.isEmpty || overlaps(sleep) ? null : sleepSeconds / 3600,
      'hours',
      sleep.length,
      note: overlaps(sleep)
          ? 'Overlapping sleep: resolve entries'
          : sleepKnown < sleep.length
          ? 'Awake time is unknown for some entries'
          : '',
    ),
    Metric(
      'Mood',
      median(mood.map((e) => (e.payload['rating'] as num).toDouble())),
      '/ 5',
      mood.length,
      note: 'Personal ordinal scale, not a clinical score',
    ),
    nutrient('energyKcal', 'Energy', 'kcal'),
    nutrient('proteinG', 'Protein', 'g'),
    nutrient('carbohydrateG', 'Carbohydrate', 'g'),
    nutrient('fatG', 'Fat', 'g'),
    nutrient('fiberG', 'Fibre', 'g'),
  ];
}

double? goalProgress(Entry goal, double? current) {
  if (current == null) return null;
  final p = goal.payload;
  if (p['direction'] == 'maintain') return null;
  final baseline = (p['baseline'] as num?)?.toDouble(),
      target = (p['target'] as num?)?.toDouble();
  if (baseline == null || target == null || target == baseline) return null;
  return ((current - baseline) / (target - baseline)).clamp(0, 1);
}

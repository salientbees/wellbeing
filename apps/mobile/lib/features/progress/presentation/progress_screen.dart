import 'package:flutter/material.dart';

import '../../tracking/data/workspace.dart';
import '../../tracking/presentation/entry_form.dart';
import '../domain/metrics.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int days = 7;
  String selected = 'Weight';
  DateTime end = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final hidden =
        (widget.workspace.account['settings'] as Map?)?['hiddenMetrics']
            as List? ??
        [];
    final available = dailyMetrics([], '')
        .where(
          (metric) =>
              !(metric.label == 'Weight' && hidden.contains('weight')) &&
              !([
                    'Energy',
                    'Protein',
                    'Carbohydrate',
                    'Fat',
                    'Fibre',
                  ].contains(metric.label) &&
                  hidden.contains('nutrition')),
        )
        .toList();
    if (!available.any((metric) => metric.label == selected)) {
      selected = available.first.label;
    }
    final dates = List.generate(
      days,
      (i) => dateKey(DateTime(end.year, end.month, end.day - i)),
    );
    final rows = dates
        .map(
          (date) => (
            date,
            dailyMetrics(
              widget.workspace.entries,
              date,
            ).firstWhere((m) => m.label == selected),
          ),
        )
        .toList();
    final values = rows.map((row) => row.$2.value).whereType<double>().toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Progress over time',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
            ButtonSegment(value: 90, label: Text('90 days')),
          ],
          selected: {days},
          onSelectionChanged: (selection) =>
              setState(() => days = selection.single),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey(selected),
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Metric'),
          items: [
            for (final metric in available)
              DropdownMenuItem(value: metric.label, child: Text(metric.label)),
          ],
          onChanged: (value) => setState(() => selected = value!),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Period ending'),
          subtitle: Text(dateKey(end)),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final value = await showDatePicker(
              context: context,
              initialDate: end,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (value != null) setState(() => end = value);
          },
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${values.length} of $days days recorded'),
                if (values.length >= 3)
                  Text(
                    'Recorded-day ${selected == 'Mood' ? 'median' : 'mean'}: ${(selected == 'Mood' ? median(values)! : values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1)} ${rows.first.$2.unit}',
                    style: Theme.of(context).textTheme.titleLarge,
                  )
                else
                  const Text(
                    'At least three recorded days are needed for a trend.',
                  ),
                const Text(
                  'Missing days remain unknown; no values are interpolated. These calculations use your entries, not AI.',
                ),
              ],
            ),
          ),
        ),
        for (final row in rows)
          ListTile(
            title: Text(row.$1),
            subtitle: Text(
              '${row.$2.records} records${row.$2.note.isEmpty ? '' : ' • ${row.$2.note}'}',
            ),
            trailing: Text(row.$2.display),
          ),
      ],
    );
  }
}

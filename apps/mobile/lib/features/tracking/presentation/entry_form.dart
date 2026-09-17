import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:cryptography/cryptography.dart';

import 'dart:convert';

import '../domain/entry.dart';
import '../data/workspace.dart';

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.number = false,
    this.optional = false,
    this.options,
    this.reference,
    this.date = false,
    this.time = false,
  });
  final String key, label;
  final bool number, optional, date, time;
  final List<String>? options;
  final EntryKind? reference;
}

List<FieldSpec> fieldsFor(EntryKind kind) => switch (kind) {
  EntryKind.weight => [
    const FieldSpec('weightKg', 'Weight (kg)', number: true),
  ],
  EntryKind.measurements => [
    const FieldSpec(
      'site',
      'Site',
      options: ['waist', 'hip', 'chest', 'arm', 'thigh', 'other'],
    ),
    const FieldSpec('side', 'Side', options: ['none', 'left', 'right']),
    const FieldSpec('circumferenceCm', 'Circumference (cm)', number: true),
    const FieldSpec('customSite', 'Custom site', optional: true),
  ],
  EntryKind.hydration => [
    const FieldSpec('volumeMl', 'Volume (ml)', number: true),
    const FieldSpec(
      'beverageType',
      'Beverage',
      options: ['water', 'tea', 'coffee', 'milk', 'other'],
    ),
  ],
  EntryKind.food => [
    const FieldSpec(
      'meal',
      'Meal',
      options: ['breakfast', 'lunch', 'dinner', 'snack'],
    ),
  ],
  EntryKind.activity => [
    const FieldSpec('steps', 'Steps', number: true, optional: true),
    const FieldSpec(
      'distanceM',
      'Distance (metres)',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'activeSeconds',
      'Active time (seconds)',
      number: true,
      optional: true,
    ),
  ],
  EntryKind.exercise => [
    const FieldSpec(
      'type',
      'Exercise',
      options: ['walk', 'run', 'cycle', 'swim', 'strength', 'yoga', 'other'],
    ),
    const FieldSpec(
      'durationSeconds',
      'Active duration (seconds)',
      number: true,
    ),
    const FieldSpec(
      'effort',
      'Effort (1–10, optional)',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'energyKcal',
      'Estimated energy (kcal, optional)',
      number: true,
      optional: true,
    ),
  ],
  EntryKind.sleep => [
    const FieldSpec('kind', 'Sleep', options: ['main', 'nap']),
    const FieldSpec(
      'awakeSeconds',
      'Known awake time (seconds)',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'quality',
      'Quality (1–5, optional)',
      number: true,
      optional: true,
    ),
  ],
  EntryKind.mood => [
    const FieldSpec('rating', 'Mood (1–5)', options: ['1', '2', '3', '4', '5']),
    const FieldSpec('tags', 'Tags (comma-separated, optional)', optional: true),
  ],
  EntryKind.goals => [
    const FieldSpec(
      'metric',
      'Metric',
      options: ['weight', 'hydration', 'steps', 'exercise', 'sleep', 'habit'],
    ),
    const FieldSpec(
      'direction',
      'Direction',
      options: ['increase', 'decrease', 'maintain', 'complete'],
    ),
    const FieldSpec('baseline', 'Baseline', number: true, optional: true),
    const FieldSpec('target', 'Target', number: true, optional: true),
    const FieldSpec(
      'lowerBound',
      'Maintenance lower bound',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'upperBound',
      'Maintenance upper bound',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'unit',
      'Canonical unit',
      options: ['kg', 'ml', 'steps', 'seconds', 'count'],
    ),
    const FieldSpec('startDate', 'Start date', date: true),
    const FieldSpec(
      'targetDate',
      'Target date (optional)',
      date: true,
      optional: true,
    ),
    const FieldSpec(
      'status',
      'Status',
      options: ['active', 'paused', 'archived'],
    ),
  ],
  EntryKind.schedules => [
    const FieldSpec('kind', 'Repeat', options: ['daily', 'weekly', 'oneOff']),
    const FieldSpec('localTime', 'Time (HH:mm)', time: true),
    const FieldSpec(
      'weekdays',
      'Weekdays (1=Monday … 7=Sunday)',
      optional: true,
    ),
    const FieldSpec('startDate', 'Start date', date: true),
    const FieldSpec(
      'endDate',
      'End date (optional)',
      date: true,
      optional: true,
    ),
    const FieldSpec(
      'zoneMode',
      'Time zone mode',
      options: ['followProfile', 'fixed'],
    ),
    const FieldSpec(
      'status',
      'Status',
      options: ['active', 'paused', 'archived'],
    ),
    const FieldSpec(
      'skipDates',
      'Skip dates (YYYY-MM-DD, comma separated)',
      optional: true,
    ),
  ],
  EntryKind.habits => [
    const FieldSpec('name', 'Habit name'),
    const FieldSpec('targetQuantity', 'Target quantity', number: true),
    const FieldSpec('unit', 'Unit', options: ['count', 'minutes', 'ml']),
    const FieldSpec('scheduleId', 'Schedule', reference: EntryKind.schedules),
    const FieldSpec(
      'status',
      'Status',
      options: ['active', 'paused', 'archived'],
    ),
    const FieldSpec('effectiveFrom', 'Effective date', date: true),
  ],
  EntryKind.habitLogs => [
    const FieldSpec('habitId', 'Habit', reference: EntryKind.habits),
    const FieldSpec(
      'status',
      'Completion',
      options: ['done', 'partial', 'skipped'],
    ),
    const FieldSpec('quantity', 'Quantity', number: true, optional: true),
  ],
  EntryKind.checkIn => [
    const FieldSpec('reflection', 'How was your day?'),
    const FieldSpec(
      'energy',
      'Energy (1–5, optional)',
      number: true,
      optional: true,
    ),
    const FieldSpec(
      'intention',
      'An intention for tomorrow (optional)',
      optional: true,
    ),
  ],
  EntryKind.reminders => [
    const FieldSpec('scheduleId', 'Schedule', reference: EntryKind.schedules),
    const FieldSpec(
      'subjectType',
      'Reminder for',
      options: ['general', 'habit', 'goal', 'checkIn'],
    ),
    const FieldSpec('deliveryMode', 'Delivery', options: ['local', 'push']),
    const FieldSpec('enabled', 'Enabled', options: ['true', 'false']),
  ],
  EntryKind.savedFoods => foodFields,
};
const foodFields = [
  FieldSpec('name', 'Food name'),
  FieldSpec('quantity', 'Portions consumed', number: true),
  FieldSpec('portionUnit', 'Portion unit', options: ['portion', 'g', 'ml']),
  FieldSpec('basis', 'Nutrient basis', options: ['perPortion', 'per100g']),
  FieldSpec('grams', 'Total consumed mass (g)', number: true, optional: true),
  FieldSpec('energyKcal', 'Energy (kcal)', number: true, optional: true),
  FieldSpec('proteinG', 'Protein (g)', number: true, optional: true),
  FieldSpec('carbohydrateG', 'Carbohydrate (g)', number: true, optional: true),
  FieldSpec('fatG', 'Fat (g)', number: true, optional: true),
  FieldSpec('fiberG', 'Fibre (g)', number: true, optional: true),
  FieldSpec(
    'source',
    'Nutrition source',
    options: ['manual', 'label', 'estimate'],
  ),
];

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.kind,
    required this.workspace,
    this.entry,
  });
  final EntryKind kind;
  final Workspace workspace;
  final Entry? entry;
  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final form = GlobalKey<FormState>();
  final inputs = <String, TextEditingController>{};
  final choices = <String, String>{};
  late DateTime occurred =
      DateTime.tryParse(widget.entry?.payload['occurredAt'] as String? ?? '')
          ?.toLocal() ??
      DateTime.now();
  late DateTime start =
      DateTime.tryParse(widget.entry?.payload['startAt'] as String? ?? '')
          ?.toLocal() ??
      DateTime.now().subtract(const Duration(hours: 1));
  late DateTime end =
      DateTime.tryParse(widget.entry?.payload['endAt'] as String? ?? '')
          ?.toLocal() ??
      DateTime.now();
  final items = <Map<String, dynamic>>[];
  bool busy = false;
  String? error;
  bool get interval => [
    EntryKind.activity,
    EntryKind.exercise,
    EntryKind.sleep,
  ].contains(widget.kind);
  @override
  void initState() {
    super.initState();
    final initial = widget.entry?.payload ?? {};
    final source = widget.kind == EntryKind.checkIn
        ? (initial['answers'] as Map? ?? {})
        : initial;
    for (final field in fieldsFor(widget.kind)) {
      final value = source[field.key];
      inputs[field.key] = TextEditingController(
        text: value is List
            ? value.join(', ')
            : value?.toString() ??
                  (field.date && !field.optional
                      ? dateKey(DateTime.now())
                      : field.time
                      ? '09:00'
                      : ''),
      );
      if (field.options != null) {
        choices[field.key] = value?.toString() ?? field.options!.first;
      }
      if (field.reference != null && value != null) {
        choices[field.key] = value.toString();
      }
    }
    inputs['notes'] = TextEditingController(
      text: initial['notes'] as String? ?? '',
    );
    for (final item in initial['items'] as List? ?? []) {
      items.add(Map<String, dynamic>.from(item as Map));
    }
  }

  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pick(DateTime value) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    return time == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload = <String, dynamic>{};
      for (final field in fieldsFor(widget.kind)) {
        final text = (choices[field.key] ?? inputs[field.key]!.text).trim();
        if (text.isEmpty && field.optional) continue;
        payload[field.key] = field.number
            ? num.parse(text.replaceAll(',', '.'))
            : text;
      }
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (widget.kind.isLog) {
        payload.addAll({
          'occurredAt': occurred.toUtc().toIso8601String(),
          'localDate': dateKey(occurred),
          'timeZone': zone,
          'utcOffsetMinutes': occurred.timeZoneOffset.inMinutes,
          'source': 'manual',
          if (inputs['notes']!.text.trim().isNotEmpty)
            'notes': inputs['notes']!.text.trim(),
        });
      }
      if (interval) {
        if (!end.isAfter(start)) {
          throw const FormatException('End must be after start.');
        }
        payload.addAll({
          'startAt': start.toUtc().toIso8601String(),
          'endAt': end.toUtc().toIso8601String(),
        });
      }
      if (widget.kind == EntryKind.sleep) payload['localDate'] = dateKey(end);
      if (widget.kind == EntryKind.activity) {
        payload['sourceGroup'] = 'manual';
        if (!['steps', 'distanceM', 'activeSeconds'].any(payload.containsKey)) {
          throw const FormatException('Record at least one activity value.');
        }
      }
      if (widget.kind == EntryKind.food) {
        if (items.isEmpty) {
          throw const FormatException('Add at least one food.');
        }
        payload['items'] = items;
        final nutrients = [
          'energyKcal',
          'proteinG',
          'carbohydrateG',
          'fatG',
          'fiberG',
        ];
        payload['nutritionStatus'] =
            items.every((item) => nutrients.every(item.containsKey))
            ? 'complete'
            : items.every((item) => !nutrients.any(item.containsKey))
            ? 'unknown'
            : 'partial';
      }
      if (widget.kind == EntryKind.mood) {
        payload['rating'] = int.parse(payload['rating'] as String);
        payload['scaleVersion'] = 'mood-1-5-v1';
        payload['tags'] = split(payload['tags']?.toString() ?? '');
      }
      if (widget.kind == EntryKind.goals) {
        payload['milestones'] = <num>[];
        if (payload['direction'] == 'maintain') {
          if (payload['lowerBound'] == null ||
              payload['upperBound'] == null ||
              (payload['lowerBound'] as num) > (payload['upperBound'] as num)) {
            throw const FormatException(
              'Provide an ordered maintenance range.',
            );
          }
        } else if (payload['baseline'] == null ||
            payload['target'] == null ||
            payload['baseline'] == payload['target']) {
          throw const FormatException(
            'Provide a baseline and a different target.',
          );
        }
      }
      if (widget.kind == EntryKind.schedules) {
        payload['timeZone'] = zone;
        payload['weekdays'] = split(payload['weekdays']?.toString() ?? '')
            .map(int.parse)
            .toList();
        payload['skipDates'] = split(payload['skipDates']?.toString() ?? '');
      }
      if (widget.kind == EntryKind.reminders) {
        payload['enabled'] = payload['enabled'] == 'true';
      }
      if (widget.kind == EntryKind.checkIn) {
        final answers = Map<String, dynamic>.from(payload);
        payload.clear();
        payload.addAll({
          'localDate': dateKey(occurred),
          'timeZone': zone,
          'answers': answers,
          'linkedLogIds': widget.entry?.payload['linkedLogIds'] ?? [],
        });
      }
      String? id = widget.entry?.id;
      if (widget.kind == EntryKind.habitLogs) {
        payload['occurrenceId'] = dateKey(occurred);
        final hash = await Sha256().hash(
          utf8.encode('${payload['habitId']}:${payload['occurrenceId']}'),
        );
        id = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
      await widget.workspace.save(widget.kind, payload, id: id);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to save. Check the form and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<String> split(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  Widget fieldWidget(FieldSpec field) {
    final refs = field.reference == null
        ? <Entry>[]
        : widget.workspace.all(field.reference!);
    if (field.options != null || field.reference != null) {
      final options = field.options ?? refs.map((e) => e.id).toList();
      final value = choices[field.key];
      return DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(
                field.reference == null
                    ? option
                    : refs
                              .firstWhere((e) => e.id == option)
                              .payload['name']
                              ?.toString() ??
                          '${refs.firstWhere((e) => e.id == option).payload['kind']} • ${refs.firstWhere((e) => e.id == option).payload['localTime']}',
              ),
            ),
        ],
        onChanged: (v) => setState(() => choices[field.key] = v!),
        validator: (v) =>
            v == null ? 'Choose ${field.label.toLowerCase()}' : null,
      );
    }
    return TextFormField(
      controller: inputs[field.key],
      maxLength: field.number
          ? 12
          : field.key == 'reflection'
          ? 2000
          : 500,
      decoration: InputDecoration(labelText: field.label),
      keyboardType: field.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      readOnly: field.date || field.time,
      onTap: field.date
          ? () async {
              final date = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(inputs[field.key]!.text) ??
                    DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (date != null) inputs[field.key]!.text = dateKey(date);
            }
          : field.time
          ? () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null) {
                inputs[field.key]!.text =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
              }
            }
          : null,
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return field.optional ? null : 'Required';
        }
        if (field.number) {
          final number = double.tryParse(value!.replaceAll(',', '.'));
          if (number == null ||
              !number.isFinite ||
              number < 0 ||
              number > 1000000) {
            return 'Enter a finite, non-negative number';
          }
          if ([
                'steps',
                'activeSeconds',
                'durationSeconds',
                'awakeSeconds',
                'effort',
                'quality',
                'energy',
              ].contains(field.key) &&
              number != number.roundToDouble()) {
            return 'Enter a whole number';
          }
          if (['effort', 'quality', 'energy'].contains(field.key) &&
              (number < 1 || number > (field.key == 'effort' ? 10 : 5))) {
            return 'Outside the rating scale';
          }
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.entry == null ? 'Add' : 'Edit'} ${widget.kind.label}',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.kind.isLog || widget.kind == EntryKind.checkIn)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recorded at'),
              subtitle: Text(occurred.toString().substring(0, 16)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final value = await pick(occurred);
                if (value != null) setState(() => occurred = value);
              },
            ),
          if (interval) ...[
            ListTile(
              title: const Text('Start'),
              subtitle: Text(start.toString().substring(0, 16)),
              onTap: () async {
                final value = await pick(start);
                if (value != null) setState(() => start = value);
              },
            ),
            ListTile(
              title: const Text('End'),
              subtitle: Text(end.toString().substring(0, 16)),
              onTap: () async {
                final value = await pick(end);
                if (value != null) setState(() => end = value);
              },
            ),
          ],
          for (final field in fieldsFor(widget.kind))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: fieldWidget(field),
            ),
          if (widget.kind == EntryKind.food) ...[
            for (var i = 0; i < items.length; i++)
              ListTile(
                title: Text(items[i]['name'] as String),
                subtitle: Text(
                  '${items[i]['quantity']} portions • ${items[i]['source']}',
                ),
                trailing: IconButton(
                  tooltip: 'Remove food',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => items.removeAt(i)),
                ),
              ),
            OutlinedButton.icon(
              onPressed: items.length >= 30
                  ? null
                  : () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => const FoodItemDialog(),
                      );
                      if (result != null) setState(() => items.add(result));
                    },
              icon: const Icon(Icons.add),
              label: const Text('Add food'),
            ),
          ],
          if (widget.kind.isLog)
            TextFormField(
              controller: inputs['notes'],
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save on this device'),
          ),
        ],
      ),
    ),
  );
}

class FoodItemDialog extends StatefulWidget {
  const FoodItemDialog({super.key});
  @override
  State<FoodItemDialog> createState() => _FoodItemDialogState();
}

class _FoodItemDialogState extends State<FoodItemDialog> {
  final controllers = {
    for (final field in foodFields)
      field.key: TextEditingController(
        text: field.key == 'quantity' ? '1' : '',
      ),
  };
  final choices = {
    for (final field in foodFields.where((f) => f.options != null))
      field.key: field.options!.first,
  };
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    try {
      final result = <String, dynamic>{};
      for (final field in foodFields) {
        final text = choices[field.key] ?? controllers[field.key]!.text.trim();
        if (text.isEmpty && field.optional) continue;
        if (text.isEmpty) throw const FormatException();
        result[field.key] = field.number ? num.parse(text) : text;
        if (result[field.key] is num &&
            (!(result[field.key] as num).isFinite ||
                (result[field.key] as num) < 0)) {
          throw const FormatException();
        }
      }
      if ((result['quantity'] as num) <= 0 ||
          result['basis'] == 'per100g' && result['grams'] == null) {
        throw const FormatException();
      }
      Navigator.pop(context, result);
    } catch (_) {
      setState(
        () => error = 'Enter a food name, positive quantity and valid nutrient values. Per-100g values also require consumed mass.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Food and nutrients'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Leave unknown nutrients blank. Values use the selected basis; totals are calculated from consumed quantity or mass.',
            ),
            for (final field in foodFields)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: field.options != null
                    ? DropdownButtonFormField<String>(
                        initialValue: choices[field.key],
                        decoration: InputDecoration(labelText: field.label),
                        items: [
                          for (final option in field.options!)
                            DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                        ],
                        onChanged: (v) => choices[field.key] = v!,
                      )
                    : TextField(
                        controller: controllers[field.key],
                        decoration: InputDecoration(labelText: field.label),
                        keyboardType: field.number
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                      ),
              ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Add')),
    ],
  );
}

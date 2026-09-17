import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../data/workspace.dart';
import 'entry_form.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key, required this.workspace, this.kinds});
  final Workspace workspace;
  final List<EntryKind>? kinds;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        kinds == null ? 'What would you like to record?' : 'Your plans',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      for (final kind
          in kinds ??
              EntryKind.values
                  .where(
                    (k) =>
                        k.isLog ||
                        k == EntryKind.checkIn ||
                        k == EntryKind.savedFoods,
                  )
                  .toList())
        Card(
          child: ListTile(
            leading: Icon(
              kind == EntryKind.mood
                  ? Icons.mood
                  : kind == EntryKind.hydration
                  ? Icons.water_drop_outlined
                  : Icons.edit_note,
            ),
            title: Text(kind.label),
            subtitle: Text('${workspace.all(kind).length} records'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    EntryListScreen(kind: kind, workspace: workspace),
              ),
            ),
          ),
        ),
    ],
  );
}

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({
    super.key,
    required this.kind,
    required this.workspace,
  });
  final EntryKind kind;
  final Workspace workspace;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace,
    builder: (context, _) {
      final entries = workspace.all(kind);
      return Scaffold(
        appBar: AppBar(title: Text(kind.label)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => EntryForm(kind: kind, workspace: workspace),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        ),
        body: entries.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No ${kind.label.toLowerCase()} recorded yet. Add your first entry when you are ready.',
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Card(
                    child: ListTile(
                      title: Text(entryTitle(entry)),
                      subtitle: Text(
                        '${entry.date}\n${syncLabel(entry.state)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => EntryDetailScreen(
                            entry: entry,
                            workspace: workspace,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}

String syncLabel(String state) => switch (state) {
  'savedOnDevice' => 'Saved on this device • waiting to sync',
  'synced' => 'Synced',
  'conflict' => 'Needs your attention',
  _ => state,
};
String entryTitle(Entry entry) {
  final p = entry.payload;
  return switch (entry.kind) {
    EntryKind.weight => '${p['weightKg']} kg',
    EntryKind.measurements => '${p['site']} • ${p['circumferenceCm']} cm',
    EntryKind.hydration => '${p['volumeMl']} ml • ${p['beverageType']}',
    EntryKind.food => '${p['meal']} • ${(p['items'] as List).length} foods',
    EntryKind.activity => '${p['steps'] ?? 'Unknown'} steps',
    EntryKind.exercise =>
      '${p['type']} • ${((p['durationSeconds'] as num) / 60).toStringAsFixed(0)} min',
    EntryKind.sleep => '${p['kind']} sleep',
    EntryKind.mood => 'Mood ${p['rating']} / 5',
    EntryKind.goals => '${p['metric']} • ${p['direction']}',
    EntryKind.habits => p['name'] as String,
    EntryKind.schedules => '${p['kind']} • ${p['localTime']}',
    EntryKind.reminders =>
      '${p['subjectType']} • ${p['enabled'] == true ? 'on' : 'off'}',
    EntryKind.savedFoods => p['name'] as String,
    EntryKind.habitLogs => '${p['status']}',
    EntryKind.checkIn => 'Daily reflection',
  };
}

class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({
    super.key,
    required this.entry,
    required this.workspace,
  });
  final Entry entry;
  final Workspace workspace;
  Future<void> remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'The entry will disappear here immediately. Server deletion is pending until synchronization succeeds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await workspace.save(
          entry.kind,
          entry.payload,
          id: entry.id,
          delete: true,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to delete this entry. Resolve any pending conflict first.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(entry.kind.label)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          entryTitle(entry),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(syncLabel(entry.state)),
        const SizedBox(height: 16),
        for (final item in entry.payload.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ValueDetails(
              label: _fieldLabel(item.key),
              value: item.value,
            ),
          ),
        if (entry.state == 'conflict') ...[
          const Text(
            'Your saved version could not be synchronized. Review the server version before deciding. Your draft is retained.',
          ),
          if (entry.server != null)
            _ValueDetails(
              label: 'Server version',
              value: entry.server!['payload'],
            ),
          OutlinedButton(
            onPressed: () async {
              await workspace.useServer(entry);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Discard local draft and use server'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EntryForm(
                  kind: entry.kind,
                  workspace: workspace,
                  entry: entry,
                ),
              ),
            ),
            child: const Text('Edit entry'),
          ),
        TextButton(
          onPressed: () => remove(context),
          child: const Text('Delete entry'),
        ),
      ],
    ),
  );
}

String _fieldLabel(String key) {
  const labels = {
    'localDate': 'Date',
    'occurredAt': 'Recorded at',
    'weightKg': 'Weight (kg)',
    'volumeMl': 'Volume (ml)',
    'circumferenceCm': 'Measurement (cm)',
    'startAt': 'Start',
    'endAt': 'End',
    'energyKcal': 'Energy (kcal)',
    'proteinG': 'Protein (g)',
    'carbohydrateG': 'Carbohydrate (g)',
    'fatG': 'Fat (g)',
    'fiberG': 'Fibre (g)',
  };
  final text =
      labels[key] ??
      key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

class _ValueDetails extends StatelessWidget {
  const _ValueDetails({required this.label, required this.value});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) {
    final data = value;
    if (data is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          for (final item in data.entries)
            _ValueDetails(
              label: _fieldLabel(item.key.toString()),
              value: item.value,
            ),
        ],
      );
    }
    if (data is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          if (data.isEmpty) const Text('None'),
          for (var i = 0; i < data.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: _ValueDetails(label: '${i + 1}', value: data[i]),
            ),
        ],
      );
    }
    return SelectableText(
      '$label: ${data == null
          ? 'Not recorded'
          : data is bool
          ? (data ? 'Yes' : 'No')
          : data}',
    );
  }
}

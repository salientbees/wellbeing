import 'package:flutter/material.dart';

import '../../tracking/data/workspace.dart';
import '../../tracking/domain/entry.dart';
import '../../tracking/presentation/entry_form.dart';
import '../../tracking/presentation/tracking_screen.dart';
import '../../progress/domain/metrics.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.workspace});
  final Workspace workspace;
  @override
  Widget build(BuildContext context) {
    final profile = workspace.account['profile'] as Map;
    final name = profile['preferredName'] as String? ?? '';
    final metrics = dailyMetrics(workspace.entries, dateKey(DateTime.now()));
    final hidden =
        (workspace.account['settings'] as Map?)?['hiddenMetrics'] as List? ??
        [];
    return RefreshIndicator(
      onRefresh: workspace.synchronize,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            name.isEmpty ? 'Your day, at your pace' : 'Hello, $name',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(dateKey(DateTime.now())),
          const SizedBox(height: 16),
          Text(
            workspace.pendingCount > 0
                ? 'Includes ${workspace.pendingCount} changes saved on this device.'
                : 'Your recorded wellbeing, without judgments.',
          ),
          if (workspace.pendingDeletionCount > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${workspace.pendingDeletionCount} deletions are waiting for server confirmation. The records remain in your encrypted queue until erasure is acknowledged.',
                ),
              ),
            ),
          if (workspace.syncError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.syncError == 'ERASURE_PIPELINE_UNAVAILABLE'
                          ? 'Server erasure is not available yet. Your deletion request is saved on this device.'
                          : 'Some changes have not synchronized. Your saved drafts are retained.',
                    ),
                    TextButton(
                      onPressed: workspace.syncing
                          ? null
                          : workspace.synchronize,
                      child: const Text('Retry synchronization'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in [
                EntryKind.hydration,
                EntryKind.mood,
                EntryKind.checkIn,
                if (!hidden.contains('weight')) EntryKind.weight,
              ])
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(kind.label),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          EntryForm(kind: kind, workspace: workspace),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          for (final metric in metrics.where(
            (m) =>
                !(m.label == 'Weight' && hidden.contains('weight')) &&
                !([
                      'Energy',
                      'Protein',
                      'Carbohydrate',
                      'Fat',
                      'Fibre',
                    ].contains(m.label) &&
                    hidden.contains('nutrition')),
          ))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metric.display,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '${metric.records} recorded source${metric.records == 1 ? '' : 's'}',
                    ),
                    if (metric.note.isNotEmpty) Text(metric.note),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Your goals', style: Theme.of(context).textTheme.titleLarge),
          if (workspace.all(EntryKind.goals).isEmpty)
            const Text(
              'Set a goal that matters to you. No targets are assigned automatically.',
            ),
          for (final goal
              in workspace
                  .all(EntryKind.goals)
                  .where(
                    (g) =>
                        g.payload['status'] == 'active' &&
                        !(g.payload['metric'] == 'weight' &&
                            hidden.contains('weight')),
                  ))
            GoalCard(goal: goal, metrics: metrics),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EntryListScreen(
                  kind: EntryKind.goals,
                  workspace: workspace,
                ),
              ),
            ),
            child: const Text('Manage goals'),
          ),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, required this.metrics});
  final Entry goal;
  final List<Metric> metrics;
  @override
  Widget build(BuildContext context) {
    final metric = metrics
        .where((m) => m.label.toLowerCase() == goal.payload['metric'])
        .firstOrNull;
    var current = metric?.value;
    if (goal.payload['metric'] == 'sleep' && current != null) current *= 3600;
    if (goal.payload['metric'] == 'exercise' && current != null) current *= 60;
    final progress = goalProgress(goal, current);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entryTitle(goal)),
            Text(
              goal.payload['direction'] == 'maintain'
                  ? 'Your range: ${goal.payload['lowerBound']}–${goal.payload['upperBound']} ${goal.payload['unit']}'
                  : 'Your target: ${goal.payload['target']} ${goal.payload['unit']}',
            ),
            const SizedBox(height: 8),
            if (progress != null)
              Semantics(
                label: 'Goal progress ${(progress * 100).round()} percent',
                child: LinearProgressIndicator(value: progress),
              ),
            if (current == null) const Text('No current measurement available'),
            if (current != null)
              Text(
                'Current: ${current.toStringAsFixed(1)} ${goal.payload['unit']}',
              ),
          ],
        ),
      ),
    );
  }
}

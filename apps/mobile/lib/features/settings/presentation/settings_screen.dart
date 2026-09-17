import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../tracking/data/workspace.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  String? error;
  Map<String, dynamic>? pendingConsent;
  Future<void> consent(String category, bool granted) async {
    if (granted) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow optional processing?'),
          content: Text(
            category == 'aiProcessing'
                ? 'When coaching is available, selected wellbeing records may be sent to the AI provider. You can turn this off at any time.'
                : category == 'memory'
                ? 'Allow the coach to retain statements you confirm. Turning this off pauses memory use; it does not delete existing records.'
                : 'Allow this optional category of processing. You can turn it off at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    pendingConsent = {
      'operationId': const Uuid().v4(),
      'operationCreatedAt': DateTime.now().toUtc().toIso8601String(),
      'baseRevision': widget.workspace.account['consentVersion'],
      'category': category,
      'granted': granted,
      'policyVersion': 'development-v1',
    };
    await submitConsent();
  }

  Future<void> submitConsent() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.workspace.updatePreferences('consents', pendingConsent!);
      pendingConsent = null;
    } on ApiFailure catch (failure) {
      error = failure.code == 'REVISION_CONFLICT'
          ? 'Preferences changed elsewhere. Refresh and review before trying again.'
          : 'Consent was not confirmed. Retry to check the same request. Your displayed choice has not changed.';
    } catch (_) {
      error = 'Unable to confirm consent. Retry when connected.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      await widget.workspace.refreshAccount();
      pendingConsent = null;
      error = null;
    } catch (_) {
      error = 'Unable to refresh. Check your connection.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> signOut() async {
    final pending = widget.workspace.pendingCount;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          pending > 0
              ? '$pending changes are still stored only on this device. Signing out clears this account’s local data and discards those unsynced changes. Stay signed in to synchronize them.'
              : 'This account’s encrypted local data will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(pending > 0 ? 'Discard and sign out' : 'Sign out'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => busy = true);
    try {
      // The account gate owns disposal and erases the old account on auth change.
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Unable to sign out. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.workspace,
    builder: (context, _) {
      final profile = widget.workspace.account['profile'] as Map;
      final choices = widget.workspace.account['consents'] as Map;
      return Scaffold(
        appBar: AppBar(title: const Text('Account & preferences')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              profile['preferredName'] as String? ?? '',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ListTile(
              title: const Text('Profile'),
              subtitle: Text('${profile['timeZone']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PreferenceEditor(
                          workspace: widget.workspace,
                          kind: 'profile',
                        ),
                      ),
                    ),
            ),
            ListTile(
              title: const Text('Appearance & reminders'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PreferenceEditor(
                          workspace: widget.workspace,
                          kind: 'settings',
                        ),
                      ),
                    ),
            ),
            const Divider(),
            Text(
              'Privacy choices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Changes require a connection and take effect only after the server confirms them. Development policy copy requires review before release.',
            ),
            for (final item in const {
              'aiProcessing': 'AI coaching',
              'memory': 'Coach memory',
              'analytics': 'Usage analytics',
              'crashReports': 'Crash reports',
              'healthImport': 'Health imports',
            }.entries)
              SwitchListTile(
                title: Text(item.value),
                value: choices[item.key] == true,
                onChanged:
                    busy ||
                        pendingConsent != null ||
                        (item.key == 'memory' &&
                            choices['aiProcessing'] != true)
                    ? null
                    : (value) => consent(item.key, value),
              ),
            if (error != null) Text(error!, semanticsLabel: error),
            if (pendingConsent != null)
              TextButton(
                onPressed: busy ? null : submitConsent,
                child: const Text('Retry consent request'),
              ),
            TextButton(
              onPressed: busy ? null : refresh,
              child: const Text('Refresh account'),
            ),
            const Divider(),
            OutlinedButton(
              onPressed: busy ? null : signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    },
  );
}

class PreferenceEditor extends StatefulWidget {
  const PreferenceEditor({
    super.key,
    required this.workspace,
    required this.kind,
  });
  final Workspace workspace;
  final String kind;
  @override
  State<PreferenceEditor> createState() => _PreferenceEditorState();
}

class _PreferenceEditorState extends State<PreferenceEditor> {
  final name = TextEditingController(), zone = TextEditingController();
  late Map<String, dynamic> values;
  late int revision;
  Map<String, dynamic>? pending;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    values = Map<String, dynamic>.from(
      widget.workspace.account[widget.kind] as Map,
    );
    revision = values['revision'] as int;
    name.text = values['preferredName'] as String? ?? '';
    zone.text = values['timeZone'] as String? ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    zone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    pending ??= {
      'operationId': const Uuid().v4(),
      'operationCreatedAt': DateTime.now().toUtc().toIso8601String(),
      'baseRevision': revision,
      'changes': widget.kind == 'profile'
          ? {
              'preferredName': name.text.trim(),
              'timeZone': zone.text.trim(),
              'coachingTone': values['coachingTone'],
            }
          : {
              for (final key in [
                'theme',
                'reduceMotion',
                'hiddenMetrics',
                'weekStartsOn',
                'notificationPreferences',
              ])
                key: values[key],
            },
    };
    try {
      await widget.workspace.updatePreferences(widget.kind, pending!);
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (failure) {
      error = failure.code == 'REVISION_CONFLICT'
          ? 'Changed on another device. Refresh and review before saving.'
          : failure.code == 'VALIDATION_FAILED'
          ? 'Some values are invalid. Refresh, then correct them.'
          : 'Save was not confirmed. Retry sends the same request without duplicating it.';
    } catch (_) {
      error = 'Unable to confirm save. Retry when connected.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> reload() async {
    setState(() => busy = true);
    try {
      await widget.workspace.refreshAccount();
      load();
      pending = null;
      error = null;
    } catch (_) {
      error = 'Unable to refresh. Your draft is retained.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final editable = !busy && pending == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.kind == 'profile' ? 'Edit profile' : 'Appearance & reminders',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.kind == 'profile') ...[
            TextField(
              controller: name,
              enabled: editable,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Preferred name'),
            ),
            TextField(
              controller: zone,
              enabled: editable,
              decoration: const InputDecoration(
                labelText: 'Time zone (IANA)',
                helperText: 'For example: Asia/Kolkata. Historical records retain their original dates.',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: values['coachingTone'] as String,
              decoration: const InputDecoration(labelText: 'Coaching tone'),
              items: [
                for (final tone in ['gentle', 'direct', 'encouraging'])
                  DropdownMenuItem(value: tone, child: Text(tone)),
              ],
              onChanged: editable
                  ? (value) => setState(() => values['coachingTone'] = value)
                  : null,
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: values['theme'] as String,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: [
                for (final theme in ['system', 'light', 'dark'])
                  DropdownMenuItem(value: theme, child: Text(theme)),
              ],
              onChanged: editable
                  ? (value) => setState(() => values['theme'] = value)
                  : null,
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              value: values['reduceMotion'] == true,
              onChanged: editable
                  ? (value) => setState(() => values['reduceMotion'] = value)
                  : null,
            ),
            for (final metric in ['weight', 'nutrition', 'measurements'])
              SwitchListTile(
                title: Text('Hide $metric on summaries'),
                value: (values['hiddenMetrics'] as List).contains(metric),
                onChanged: editable
                    ? (value) => setState(() {
                        final hidden = List<String>.from(
                          values['hiddenMetrics'] as List,
                        );
                        value ? hidden.add(metric) : hidden.remove(metric);
                        values['hiddenMetrics'] = hidden;
                      })
                    : null,
              ),
            const Text(
              'Reminder preferences are stored for notification delivery. OS delivery is not enabled in this build.',
            ),
            SwitchListTile(
              title: const Text('Allow reminders'),
              value:
                  (values['notificationPreferences'] as Map)['enabled'] == true,
              onChanged: editable
                  ? (value) => setState(
                      () => values['notificationPreferences'] = {
                        ...values['notificationPreferences'] as Map,
                        'enabled': value,
                      },
                    )
                  : null,
            ),
            for (final item in {
              'quietStart': 'Quiet hours start',
              'quietEnd': 'Quiet hours end',
            }.entries)
              ListTile(
                title: Text(item.value),
                subtitle: Text(
                  (values['notificationPreferences'] as Map)[item.key]
                      as String,
                ),
                onTap: !editable
                    ? null
                    : () async {
                        final parts =
                            ((values['notificationPreferences']
                                        as Map)[item.key]
                                    as String)
                                .split(':')
                                .map(int.parse)
                                .toList();
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: parts[0],
                            minute: parts[1],
                          ),
                        );
                        if (time != null && mounted) {
                          setState(
                            () => values['notificationPreferences'] = {
                              ...values['notificationPreferences'] as Map,
                              item.key:
                                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            },
                          );
                        }
                      },
              ),
          ],
          const SizedBox(height: 24),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Saving…'
                  : pending != null
                  ? 'Retry save'
                  : 'Save preferences',
            ),
          ),
          TextButton(
            onPressed: busy ? null : reload,
            child: const Text('Discard draft and refresh'),
          ),
        ],
      ),
    );
  }
}

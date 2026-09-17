import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/app_theme.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tracking/data/workspace.dart';
import '../features/tracking/domain/entry.dart';
import '../features/tracking/presentation/tracking_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/progress/presentation/progress_screen.dart';
import '../l10n/generated/app_localizations.dart';

final routerProvider = Provider.family<GoRouter, Workspace?>((ref, workspace) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            _NavigationShell(shell: shell, workspace: workspace),
        branches: [
          for (final section in _Section.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/${section.name}',
                  builder: (context, state) =>
                      _SectionScreen(section: section, workspace: workspace),
                ),
              ],
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.appTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.notFound)),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class WellbeingApp extends ConsumerWidget {
  const WellbeingApp({super.key, this.workspace});
  final Workspace? workspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider(workspace));
    Widget buildApp(BuildContext context, Widget? child) {
      final settings = workspace?.account['settings'] as Map?;
      return MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: switch (settings?['theme']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        themeAnimationDuration: settings?['reduceMotion'] == true
            ? Duration.zero
            : kThemeAnimationDuration,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.of(context).disableAnimations ||
                settings?['reduceMotion'] == true,
          ),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      );
    }

    return workspace == null
        ? buildApp(context, null)
        : ListenableBuilder(listenable: workspace!, builder: buildApp);
  }
}

enum _Section { home, track, coach, progress, plan }

class _NavigationShell extends StatelessWidget {
  const _NavigationShell({required this.shell, this.workspace});
  final Workspace? workspace;
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = [l.home, l.track, l.coach, l.progress, l.plan];
    const icons = [
      Icons.home_outlined,
      Icons.edit_note,
      Icons.chat_bubble_outline,
      Icons.insights,
      Icons.event_outlined,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          if (workspace != null)
            IconButton(
              tooltip: 'Account & preferences',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(workspace: workspace!),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}

class _SectionScreen extends StatelessWidget {
  const _SectionScreen({required this.section, this.workspace});
  final Workspace? workspace;
  final _Section section;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final active = workspace;
    if (active != null && section != _Section.coach) {
      return ListenableBuilder(
        listenable: active,
        builder: (context, _) => switch (section) {
          _Section.home => DashboardScreen(workspace: active),
          _Section.track => TrackingScreen(workspace: active),
          _Section.progress => ProgressScreen(workspace: active),
          _Section.plan => TrackingScreen(
            workspace: active,
            kinds: const [
              EntryKind.goals,
              EntryKind.habits,
              EntryKind.schedules,
              EntryKind.reminders,
            ],
          ),
          _Section.coach => throw StateError('Handled separately'),
        },
      );
    }
    final (title, body) = switch (section) {
      _Section.home => (l.welcome, l.welcomeBody),
      _Section.track => (l.trackTitle, l.trackBody),
      _Section.coach => (l.coachTitle, l.coachBody),
      _Section.progress => (l.progressTitle, l.progressBody),
      _Section.plan => (l.planTitle, l.planBody),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.large),
          children: [
            const SizedBox(height: AppSpacing.section),
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(body, style: Theme.of(context).textTheme.bodyLarge),
            if (section == _Section.home) ...[
              const SizedBox(height: AppSpacing.section),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.medium),
                  child: Text(l.foundationNotice),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/api/app_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/account_store.dart';
import '../../tracking/data/workspace.dart';
import '../../../app/wellbeing_app.dart';

final workspaceProvider = Provider<Workspace>(
  (ref) => throw StateError('Account scope required'),
);
Future<void> initializeServices() async {
  if (!AppConfig.configured) return;
  await Firebase.initializeApp(options: AppConfig.firebaseOptions);
  if (AppConfig.emulators) {
    await FirebaseAuth.instance.useAuthEmulator(AppConfig.emulatorHost, 9099);
  } else {
    await FirebaseAppCheck.instance.activate();
  }
}

class AccountGate extends StatefulWidget {
  const AccountGate({super.key});
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  late final Future<void> ready = initializeServices();
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      if (!AppConfig.configured || snapshot.hasError) {
        return const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Wellbeing is not connected to a service yet. For local development, start the Firebase emulators and API, then run with USE_FIREBASE_EMULATORS=true. No cloud credentials are needed.',
                ),
              ),
            ),
          ),
        );
      }
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) return const MaterialApp(home: SignInScreen());
          if (!user.emailVerified) {
            return MaterialApp(home: VerificationScreen(user: user));
          }
          return SessionGate(key: ValueKey(user.uid), user: user);
        },
      );
    },
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit({bool reset = false}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (reset) {
        await auth.sendPasswordResetEmail(email: email.text.trim());
        message = 'If the account exists, password reset instructions have been sent.';
      } else if (register) {
        final result = await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
        await result.user!.sendEmailVerification();
      } else {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (_) {
      message = 'Unable to complete sign-in. Check your details and connection, then try again.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wellbeing')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                register ? 'Create your account' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              if (AppConfig.emulators)
                const Text('Local development • Firebase emulator'),
              TextField(
                controller: email,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                autofillHints: [
                  register ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => busy ? null : submit(),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(message!, semanticsLabel: message),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Please wait…'
                      : register
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => register = !register),
                child: Text(
                  register
                      ? 'Already have an account? Sign in'
                      : 'Create an account',
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => submit(reset: true),
                child: const Text('Reset password'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key, required this.user});
  final User user;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  String? message;
  Future<void> action(bool resend) async {
    try {
      if (resend) {
        await widget.user.sendEmailVerification();
      } else {
        await widget.user.reload();
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      }
      if (mounted) {
        setState(
          () => message = resend
              ? 'Verification sent.'
              : 'If verification is complete, your account will open.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Unable to refresh verification. Try again shortly.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify your email')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Open the verification link sent to your email before continuing.',
          ),
          if (AppConfig.emulators)
            const Text(
              'For local testing, the link appears in the Firebase Auth emulator output.',
            ),
          FilledButton(
            onPressed: () => action(false),
            child: const Text('I have verified my email'),
          ),
          TextButton(
            onPressed: () => action(true),
            child: const Text('Send another link'),
          ),
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
          if (message != null) Text(message!),
        ],
      ),
    ),
  );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, required this.user});
  final User user;
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  Workspace? workspace;
  late final ApiClient api = ApiClient(FirebaseAuth.instance);
  AccountStore? store;
  bool onboarding = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      store ??= await AccountStore.open(widget.user.uid);
      Map<String, dynamic> account;
      try {
        account = await api.request('GET', '/me');
      } on ApiFailure catch (e) {
        if (e.code == 'ONBOARDING_REQUIRED') {
          if (mounted) setState(() => onboarding = true);
          return;
        }
        final cached = await store!.get('account');
        if (e.code != 'OFFLINE' || cached == null) rethrow;
        account = Map<String, dynamic>.from(cached['value'] as Map);
      }
      final next = Workspace(store!, api, account);
      await next.initialize();
      if (!mounted) {
        await next.close(erase: true);
        return;
      }
      setState(() {
        workspace = next;
        error = null;
        onboarding = false;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to open your account. Your local data has not been reset.',
        );
      }
    }
  }

  @override
  void dispose() {
    if (workspace != null) {
      workspace!.close(
        erase: FirebaseAuth.instance.currentUser?.uid != widget.user.uid,
      );
    } else {
      store?.close();
      api.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (workspace != null) {
      return ProviderScope(
        overrides: [workspaceProvider.overrideWithValue(workspace!)],
        child: WellbeingApp(workspace: workspace!),
      );
    }
    return MaterialApp(
      home: onboarding
          ? OnboardingScreen(api: api, onComplete: load)
          : Scaffold(
              body: Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          FilledButton(
                            onPressed: load,
                            child: const Text('Retry'),
                          ),
                          TextButton(
                            onPressed: () => FirebaseAuth.instance.signOut(),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.api,
    required this.onComplete,
  });
  final ApiClient api;
  final Future<void> Function() onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final name = TextEditingController();
  bool eligible = false, ai = false, memory = false, busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      await widget.api.request(
        'POST',
        '/me/bootstrap',
        data: {
          'profile': {
            'preferredName': name.text.trim(),
            'locale': 'en',
            'timeZone': zone.identifier,
            'unitPreferences': {'weight': 'kg', 'length': 'cm', 'volume': 'ml'},
            'coachingTone': 'gentle',
            'ageEligible': eligible,
          },
          'consents': {
            'aiProcessing': ai,
            'memory': memory,
            'analytics': false,
            'crashReports': false,
            'healthImport': false,
          },
          'policyVersion': 'development-v1',
        },
      );
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to save onboarding. Check your connection and try again.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Make this space yours')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: name,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Preferred name (optional)',
          ),
        ),
        const Text(
          'Wellbeing supports personal reflection and tracking. It does not diagnose conditions or replace medical care.',
        ),
        CheckboxListTile(
          value: eligible,
          onChanged: (v) => setState(() => eligible = v!),
          title: const Text('I meet the adult eligibility requirement'),
        ),
        SwitchListTile(
          value: ai,
          onChanged: (v) => setState(() {
            ai = v;
            if (!v) memory = false;
          }),
          title: const Text('Allow AI processing'),
          subtitle: const Text(
            'Optional. Selected records may be sent to the configured AI provider for coaching.',
          ),
        ),
        SwitchListTile(
          value: memory,
          onChanged: ai ? (v) => setState(() => memory = v) : null,
          title: const Text('Allow structured coach memory'),
          subtitle: const Text(
            'Optional. Review and remove saved memories at any time.',
          ),
        ),
        const Text(
          'Analytics, crash reporting and health imports remain off. Development consent copy must be reviewed before release.',
        ),
        if (error != null) Text(error!),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: eligible && !busy ? submit : null,
          child: Text(busy ? 'Saving…' : 'Continue'),
        ),
      ],
    ),
  );
}

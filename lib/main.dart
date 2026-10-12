import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/app_lock_gate.dart';
import 'screens/compose_screen.dart';
import 'screens/inbox_view.dart';
import 'screens/settings_view.dart';
import 'services/app_settings.dart';
import 'services/background_sync.dart';
import 'services/gmail_auth_service.dart';
import 'services/new_mail_checker.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await const SettingsStore().load();

  try {
    await NotificationService.instance.init();
    await BackgroundSync.initialize();
  } catch (_) {
    // The app works without notifications.
  }

  runApp(
    ProviderScope(
      overrides: [initialSettingsProvider.overrideWithValue(settings)],
      child: const SignMailApp(),
    ),
  );
}

class SignMailApp extends ConsumerWidget {
  const SignMailApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Color(0xFF69E0D0);
    final scalePercent = ref.watch(
      settingsProvider.select((settings) => settings.textScalePercent),
    );

    return MaterialApp(
      title: 'SignMail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF111923),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0F16),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151F2B),
          hintStyle: const TextStyle(color: Color(0xFF7D8B9B)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF263342)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF263342)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: seed, width: 1.4),
          ),
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: scalePercent == 100
              ? media
              : media.copyWith(
                  textScaler: TextScaler.linear(scalePercent / 100),
                ),
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const StartupGate(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  BrandMark(size: 42),
                  SizedBox(width: 12),
                  Text(
                    'SignMail',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Spacer(),
                  StatusPill(
                    label: 'EARLY ACCESS',
                    color: Color(0xFF69E0D0),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 218,
                  height: 218,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF69E0D0).withValues(alpha: 0.19),
                        const Color(0xFF69E0D0).withValues(alpha: 0.02),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 142,
                      height: 142,
                      decoration: BoxDecoration(
                        color: const Color(0xFF121D28),
                        borderRadius: BorderRadius.circular(38),
                        border: Border.all(
                          color: const Color(0xFF69E0D0)
                              .withValues(alpha: 0.38),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF69E0D0)
                                .withValues(alpha: 0.08),
                            blurRadius: 34,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mark_email_read_rounded,
                        size: 76,
                        color: Color(0xFF69E0D0),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Email, with proof.',
                style: TextStyle(
                  fontSize: 36,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your inbox, your certificates, your control. Sign messages '
                'with S/MIME without wrestling through complicated settings.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: Color(0xFF9EACBC),
                ),
              ),
              const SizedBox(height: 24),
              const FeatureLine(
                icon: Icons.verified_user_outlined,
                title: 'Signing made visible',
                subtitle: 'Know when a message is signed.',
              ),
              const SizedBox(height: 14),
              const FeatureLine(
                icon: Icons.key_outlined,
                title: 'Your keys stay yours',
                subtitle: 'Private-key protection is a core design rule.',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountSetupScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text(
                    'Set up my email',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF69E0D0),
                    foregroundColor: const Color(0xFF071311),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'PRIVATE BY DESIGN  •  S/MIME-READY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: Color(0xFF6F8092),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  String _method = 'automatic';
  final _email = TextEditingController();
  final GmailAuthService _gmailAuth = GmailAuthService();

  bool _connecting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _connectAccount() async {
    final email = _email.text.trim();

    final validEmail =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    if (!validEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid email address.'),
        ),
      );
      return;
    }

    if (_method == 'manual') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Manual IMAP/SMTP setup is not implemented yet.',
          ),
        ),
      );
      return;
    }

    setState(() => _connecting = true);

    try {
      final authorization = await _gmailAuth.connectGmail();

      if (!mounted) return;

      if (authorization.email.toLowerCase() != email.toLowerCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You signed in as ${authorization.email}. '
              'Enter that email address to continue.',
            ),
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CertificateIntroScreen(email: email),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $error'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _connecting ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Connect an account',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            const StepProgress(current: 1, total: 3),
            const SizedBox(height: 26),
            const Text(
              'Let’s find your\nmailbox.',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.08,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start with your email address. SignMail will guide you '
              'through the right connection method.',
              style: TextStyle(
                color: Color(0xFF9EACBC),
                height: 1.5,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'EMAIL ADDRESS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                color: Color(0xFF8B9BAC),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            TextField(
              controller: _email,
              enabled: !_connecting,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.alternate_email_rounded),
                hintText: 'you@example.com',
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'SETUP METHOD',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                color: Color(0xFF8B9BAC),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableOption(
              selected: _method == 'automatic',
              icon: Icons.auto_awesome_rounded,
              title: 'Automatic setup',
              description: 'Discover supported provider settings',
              onTap: _connecting
                  ? () {}
                  : () => setState(() => _method = 'automatic'),
            ),
            const SizedBox(height: 10),
            SelectableOption(
              selected: _method == 'manual',
              icon: Icons.tune_rounded,
              title: 'Manual IMAP / SMTP',
              description: 'For custom domains and advanced setups',
              onTap: _connecting
                  ? () {}
                  : () => setState(() => _method = 'manual'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF14231F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2B5C51)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF69E0D0),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your account connects directly to its mail provider. '
                      'SignMail does not need your email password on a '
                      'separate server.',
                      style: TextStyle(
                        color: Color(0xFFB8D9D2),
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _connecting ? null : _connectAccount,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF69E0D0),
                  foregroundColor: const Color(0xFF071311),
                  disabledBackgroundColor:
                      const Color(0xFF365A56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _connecting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF071311),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Connecting to Google...'),
                        ],
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Google authorization · mail sync not yet connected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF75869A),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CertificateIntroScreen extends StatelessWidget {
  const CertificateIntroScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Signing certificate',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StepProgress(current: 2, total: 3),
              const SizedBox(height: 28),
              const Icon(
                Icons.workspace_premium_outlined,
                size: 48,
                color: Color(0xFF69E0D0),
              ),
              const SizedBox(height: 20),
              const Text(
                'Give your emails\na verifiable signature.',
                style: TextStyle(
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Import the S/MIME certificate that matches your email '
                'address. You can also do this later in Settings.',
                style: TextStyle(
                  color: Color(0xFF9EACBC),
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111923),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF263342)),
                ),
                child: const Column(
                  children: [
                    SecurityBullet(
                      title: 'Supported import format',
                      detail: '.p12 / .pfx certificate bundle',
                    ),
                    Divider(color: Color(0xFF263342), height: 26),
                    SecurityBullet(
                      title: 'We will check',
                      detail:
                          'Email identity, expiry and private-key availability',
                    ),
                    Divider(color: Color(0xFF263342), height: 26),
                    SecurityBullet(
                      title: 'Never silently downgrade',
                      detail: 'Signing failures will be clearly reported',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Certificate import will be enabled in a later phase.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import certificate'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const PrototypeHomeScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF69E0D0),
                    foregroundColor: const Color(0xFF071311),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Explore SignMail',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Setting up $email',
                  style: const TextStyle(
                    color: Color(0xFF75869A),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypeHomeScreen extends ConsumerStatefulWidget {
  const PrototypeHomeScreen({super.key});

  @override
  ConsumerState<PrototypeHomeScreen> createState() =>
      _PrototypeHomeScreenState();
}

class _PrototypeHomeScreenState extends ConsumerState<PrototypeHomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleTimer(ref.read(settingsProvider).autoRefreshSeconds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startup() async {
    final settings = ref.read(settingsProvider);

    try {
      if (settings.notificationsEnabled) {
        await NotificationService.instance.requestPermission();
      }
      await BackgroundSync.apply(settings, signedIn: true);
      await NotificationService.instance.clearMailNotification();
    } catch (_) {
      // Notifications are optional.
    }
  }

  void _scheduleTimer(int seconds) {
    _timer?.cancel();
    _timer = null;

    if (seconds <= 0) {
      return;
    }

    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (_inForeground && mounted) {
        ref.read(inboxProvider.notifier).refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;

    if (_inForeground) {
      ref.read(inboxProvider.notifier).refresh();
      NotificationService.instance.clearMailNotification();
    }
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    final settings = ref.read(settingsProvider);

    await ref.read(authServiceProvider).disconnect();
    await BackgroundSync.apply(settings, signedIn: false);
    await const NewMailChecker().reset();
    await NotificationService.instance.clearMailNotification();

    ref
      ..invalidate(inboxProvider)
      ..invalidate(savedEmailProvider);

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _compose() async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const ComposeScreen(),
      ),
    );

    if (sent == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Message sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      settingsProvider.select((settings) => settings.autoRefreshSeconds),
      (previous, next) => _scheduleTimer(next),
    );

    final pages = [
      const InboxView(),
      const CertificateScreen(),
      SettingsView(onSignOut: _signOut),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            BrandMark(size: 30),
            SizedBox(width: 10),
            Text(
              'SignMail',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(inboxProvider.notifier).refresh(),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: pages[_index],
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: _compose,
              backgroundColor: const Color(0xFF69E0D0),
              foregroundColor: const Color(0xFF071311),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Compose'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF101720),
        indicatorColor: const Color(0xFF21423F),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user_rounded),
            label: 'Certificates',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class CertificateScreen extends StatelessWidget {
  const CertificateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Certificate vault',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage signing identities on this device.',
          style: TextStyle(color: Color(0xFF8F9EAE)),
        ),
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: 'No certificate imported',
          description:
              'Your certificates will appear here after we implement secure '
              '.p12 / .pfx import and validation.',
        ),
        const SizedBox(height: 16),
        const SecurityBullet(
          title: 'Local-first design',
          detail: 'Private keys must never be uploaded to a SignMail server.',
        ),
        const SizedBox(height: 14),
        const SecurityBullet(
          title: 'Explicit signing status',
          detail:
              'A message must never be labelled signed unless cryptographic '
              'signing succeeds.',
        ),
      ],
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8AF1E1), Color(0xFF38AFA4)],
        ),
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Icon(
        Icons.mark_email_read_rounded,
        color: const Color(0xFF08201D),
        size: size * 0.59,
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class FeatureLine extends StatelessWidget {
  const FeatureLine({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF14231F),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF69E0D0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8F9EAE),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        total,
        (i) => Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: i == total - 1 ? 0 : 7,
            ),
            height: 4,
            decoration: BoxDecoration(
              color: i < current
                  ? const Color(0xFF69E0D0)
                  : const Color(0xFF263342),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

class SelectableOption extends StatelessWidget {
  const SelectableOption({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF142824)
              : const Color(0xFF111923),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? const Color(0xFF69E0D0)
                : const Color(0xFF263342),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF69E0D0)
                  : const Color(0xFF8F9EAE),
              size: 25,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF8F9EAE),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? const Color(0xFF69E0D0)
                  : const Color(0xFF607184),
            ),
          ],
        ),
      ),
    );
  }
}

class SecurityBullet extends StatelessWidget {
  const SecurityBullet({
    super.key,
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          color: Color(0xFF69E0D0),
          size: 21,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xFF8F9EAE),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 34,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111923),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF263342)),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFF19252F),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 30,
              color: const Color(0xFF69E0D0),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F9EAE),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 5),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF19252F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF69E0D0),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Color(0xFF8F9EAE),
          fontSize: 12,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF718194),
      ),
    );
  }
}

/// Chooses the first screen: the inbox when an account is already connected
/// on this device, otherwise the welcome flow.
class StartupGate extends ConsumerWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedEmailProvider);

    return saved.when(
      data: (email) =>
          email == null ? const WelcomeScreen() : const PrototypeHomeScreen(),
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF69E0D0)),
        ),
      ),
      error: (error, stackTrace) => const WelcomeScreen(),
    );
  }
}
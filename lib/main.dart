import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SignMailApp());
}

class SignMailApp extends StatelessWidget {
  const SignMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF69E0D0);

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
      home: const WelcomeScreen(),
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

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
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
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
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
              onTap: () => setState(() => _method = 'automatic'),
            ),
            const SizedBox(height: 10),
            SelectableOption(
              selected: _method == 'manual',
              icon: Icons.tune_rounded,
              title: 'Manual IMAP / SMTP',
              description: 'For custom domains and advanced setups',
              onTap: () => setState(() => _method = 'manual'),
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
                onPressed: () {
                  final email = _email.text.trim();

                  if (!email.contains('@') || email.endsWith('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a valid email address to continue.',
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
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF69E0D0),
                  foregroundColor: const Color(0xFF071311),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
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
                'Prototype flow · account connection is not active yet',
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

class PrototypeHomeScreen extends StatefulWidget {
  const PrototypeHomeScreen({super.key});

  @override
  State<PrototypeHomeScreen> createState() => _PrototypeHomeScreenState();
}

class _PrototypeHomeScreenState extends State<PrototypeHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const InboxScreen(),
      const CertificateScreen(),
      const SettingsScreen(),
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Live sync is not connected in this prototype.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: pages[_index],
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  backgroundColor: const Color(0xFF111923),
                  builder: (_) => const ComposeSheet(),
                );
              },
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

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        const Text(
          'Your inbox,\nwithout the noise.',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'A preview of the SignMail experience',
          style: TextStyle(color: Color(0xFF8F9EAE)),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF17332F), Color(0xFF14212B)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2C5C52)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: Color(0xFF69E0D0),
                size: 30,
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signature status at a glance',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Signed, verified and unsigned messages will be clearly '
                      'labelled.',
                      style: TextStyle(
                        color: Color(0xFFB5C9C5),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          'RECENT MESSAGES',
          style: TextStyle(
            color: Color(0xFF7E8EA0),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        const EmptyState(
          icon: Icons.mark_email_unread_outlined,
          title: 'Your messages will live here',
          description:
              'Connect an account to start synchronising your inbox. '
              'These preview screens do not access real email.',
        ),
      ],
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 20),
        const SettingsTile(
          icon: Icons.account_circle_outlined,
          title: 'Email accounts',
          subtitle: 'Provider connections and sync',
        ),
        const SettingsTile(
          icon: Icons.verified_user_outlined,
          title: 'Signing defaults',
          subtitle: 'Require S/MIME signing when available',
        ),
        const SettingsTile(
          icon: Icons.fingerprint_rounded,
          title: 'App lock',
          subtitle: 'Biometrics and device security',
        ),
        const SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'About SignMail',
          subtitle: 'Mobile-first S/MIME email',
        ),
        const SizedBox(height: 20),
        const Text(
          'Prototype only: account sync, secure import, signing and sending '
          'are not implemented yet.',
          style: TextStyle(
            color: Color(0xFF8F9EAE),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key});

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  bool _sign = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'New message',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const TextField(
            decoration: InputDecoration(
              labelText: 'To',
              hintText: 'recipient@example.com',
            ),
          ),
          const SizedBox(height: 10),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Subject',
              hintText: 'Subject',
            ),
          ),
          const SizedBox(height: 10),
          const TextField(
            minLines: 5,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Message',
              hintText: 'Write something thoughtful…',
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: _sign,
            onChanged: (value) => setState(() => _sign = value),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF69E0D0),
            title: const Text('Request S/MIME signing'),
            subtitle: const Text(
              'Actual signing is not yet connected',
              style: TextStyle(
                color: Color(0xFF8F9EAE),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Sending is disabled until SMTP and S/MIME signing '
                      'are implemented.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send message'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF69E0D0),
                foregroundColor: const Color(0xFF071311),
              ),
            ),
          ),
        ],
      ),
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

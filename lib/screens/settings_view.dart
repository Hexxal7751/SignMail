import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../providers.dart';
import '../services/app_settings.dart';
import '../services/new_mail_checker.dart';
import '../services/notification_service.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);
const Color _card = Color(0xFF111923);
const Color _border = Color(0xFF263342);
const Color _iconBox = Color(0xFF19252F);
const Color _danger = Color(0xFFFF8A94);

/// The settings tab.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key, required this.onSignOut});

  /// Signs out and returns to the welcome screen.
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Settings',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
        ),
        _AccountSection(onSignOut: onSignOut),
        const _NotificationsSection(),
        const _SyncSection(),
        const _ReadingSection(),
        const _WritingSection(),
        const _SecuritySection(),
        const _AboutSection(),
      ],
    );
  }
}

// ---------------------------------------------------------------- sections

class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.onSignOut});

  final Future<void> Function() onSignOut;

  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authServiceProvider).connectGmail();
      ref.invalidate(savedEmailProvider);
      await ref.read(inboxProvider.notifier).refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Google account reconnected.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Reconnect failed: $error'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Sign out?',
      message: 'This removes the account from this device. Your mail stays '
          'safe in Gmail.',
      action: 'Sign out',
    );
    if (ok) {
      await onSignOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(savedEmailProvider).valueOrNull ?? '';

    return _Section(
      title: 'Account',
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF21423F),
            child: Text(
              email.isEmpty ? '?' : email[0].toUpperCase(),
              style: const TextStyle(
                color: _mint,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: Text(
            email.isEmpty ? 'No account' : email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Gmail, connected with Google',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        _ActionRow(
          icon: Icons.sync_lock_rounded,
          title: 'Reconnect Google',
          subtitle: 'Use this if Google asks for access again',
          onTap: () => _reconnect(context, ref),
        ),
        _ActionRow(
          icon: Icons.logout_rounded,
          title: 'Sign out',
          subtitle: 'Remove this account from the device',
          danger: true,
          onTap: () => _confirmSignOut(context),
        ),
      ],
    );
  }
}

class _NotificationsSection extends ConsumerStatefulWidget {
  const _NotificationsSection();

  @override
  ConsumerState<_NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<_NotificationsSection>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPermission();
    }
  }

  Future<void> _loadPermission() async {
    try {
      final allowed = await NotificationService.instance.areEnabled();
      if (mounted) {
        setState(() => _allowed = allowed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _allowed = null);
      }
    }
  }

  Future<void> _setEnabled(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(notificationsEnabled: value));

    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      await _loadPermission();
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked. Allow them in the system settings.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkNow() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);

    final outcome = await const NewMailChecker().run(manual: true);
    ref.invalidate(syncStatusProvider);

    if (!mounted) {
      return;
    }
    setState(() => _checking = false);
    messenger.showSnackBar(SnackBar(content: Text(outcome.message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final status = ref.watch(syncStatusProvider).valueOrNull;

    final permissionText = _allowed == null
        ? 'Could not check'
        : (_allowed! ? 'Allowed' : 'Blocked in system settings');

    return _Section(
      title: 'Notifications',
      children: [
        _SwitchRow(
          icon: Icons.notifications_active_outlined,
          title: 'New mail notifications',
          subtitle: 'Get an alert when a new message arrives',
          value: s.notificationsEnabled,
          onChanged: _setEnabled,
        ),
        _InfoRow(
          icon: Icons.verified_outlined,
          title: 'System permission',
          value: permissionText,
          trailing: _allowed == true
              ? null
              : TextButton(
                  onPressed: () async {
                    final granted =
                        await NotificationService.instance.requestPermission();
                    if (!granted) {
                      await NotificationService.instance.openSystemSettings();
                    }
                    await _loadPermission();
                  },
                  child: const Text('Allow'),
                ),
        ),
        _SwitchRow(
          icon: Icons.cloud_sync_outlined,
          title: 'Check while the app is closed',
          subtitle: 'Looks for new mail in the background',
          value: s.backgroundCheck,
          enabled: s.notificationsEnabled,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(backgroundCheck: value)),
        ),
        _ChoiceRow<int>(
          icon: Icons.schedule_rounded,
          title: 'Check every',
          current: s.backgroundIntervalMinutes,
          enabled: s.notificationsEnabled && s.backgroundCheck,
          options: const <int, String>{
            15: '15 minutes',
            30: '30 minutes',
            60: '1 hour',
            120: '2 hours',
          },
          onChanged: (value) => ctl.update(
            (current) => current.copyWith(backgroundIntervalMinutes: value),
          ),
        ),
        _SwitchRow(
          icon: Icons.volume_up_outlined,
          title: 'Sound',
          value: s.notifySound,
          enabled: s.notificationsEnabled,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(notifySound: value)),
        ),
        _SwitchRow(
          icon: Icons.vibration_rounded,
          title: 'Vibration',
          value: s.notifyVibrate,
          enabled: s.notificationsEnabled,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(notifyVibrate: value)),
        ),
        _SwitchRow(
          icon: Icons.visibility_outlined,
          title: 'Show sender and subject',
          subtitle: 'Turn off to hide details on the lock screen',
          value: s.notifyPreview,
          enabled: s.notificationsEnabled,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(notifyPreview: value)),
        ),
        _ActionRow(
          icon: Icons.notification_add_outlined,
          title: 'Send a test notification',
          subtitle: 'See how alerts look with these settings',
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await NotificationService.instance.showTest(s);
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(content: Text('Could not show it: $error')),
              );
            }
          },
        ),
        _ActionRow(
          icon: Icons.mark_email_unread_outlined,
          title: 'Check for new mail now',
          subtitle: status == null
              ? 'No background check has run yet'
              : 'Last check ${_clock(status.at)}: ${status.message}',
          busy: _checking,
          onTap: _checking ? null : _checkNow,
        ),
        const _Note(
          'Android decides exactly when background checks run. Battery '
          'saver or "restricted" battery use for SignMail can delay or stop '
          'them. Instant push alerts need a server and are planned for later.',
        ),
      ],
    );
  }
}

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return _Section(
      title: 'Sync and inbox',
      children: [
        _ChoiceRow<int>(
          icon: Icons.format_list_numbered_rounded,
          title: 'Messages to load',
          current: s.inboxPageSize,
          options: const <int, String>{
            20: '20 messages',
            40: '40 messages',
            80: '80 messages',
            150: '150 messages',
          },
          onChanged: (value) async {
            await ctl.update((current) => current.copyWith(inboxPageSize: value));
            await ref.read(inboxProvider.notifier).refresh();
          },
        ),
        _ChoiceRow<int>(
          icon: Icons.autorenew_rounded,
          title: 'Refresh while the app is open',
          current: s.autoRefreshSeconds,
          options: const <int, String>{
            0: 'Off',
            60: 'Every minute',
            120: 'Every 2 minutes',
            300: 'Every 5 minutes',
            900: 'Every 15 minutes',
          },
          onChanged: (value) => ctl.update(
            (current) => current.copyWith(autoRefreshSeconds: value),
          ),
        ),
      ],
    );
  }
}

class _ReadingSection extends ConsumerWidget {
  const _ReadingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return _Section(
      title: 'Reading',
      children: [
        _SwitchRow(
          icon: Icons.drafts_outlined,
          title: 'Mark as read when opened',
          value: s.markReadOnOpen,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(markReadOnOpen: value)),
        ),
        _SwitchRow(
          icon: Icons.density_small_rounded,
          title: 'Compact list',
          subtitle: 'Smaller rows so more messages fit on screen',
          value: s.compactList,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(compactList: value)),
        ),
        _SwitchRow(
          icon: Icons.account_circle_outlined,
          title: 'Show sender avatars',
          value: s.showAvatars,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(showAvatars: value)),
        ),
        _ChoiceRow<int>(
          icon: Icons.text_fields_rounded,
          title: 'Text size',
          current: s.textScalePercent,
          options: const <int, String>{
            90: 'Small',
            100: 'Default',
            115: 'Large',
            130: 'Extra large',
          },
          onChanged: (value) => ctl.update(
            (current) => current.copyWith(textScalePercent: value),
          ),
        ),
      ],
    );
  }
}

class _WritingSection extends ConsumerWidget {
  const _WritingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return _Section(
      title: 'Writing',
      children: [
        _ActionRow(
          icon: Icons.badge_outlined,
          title: 'Your name',
          subtitle: s.displayName.isEmpty
              ? 'Shown to people you write to (not set)'
              : s.displayName,
          onTap: () async {
            final value = await _editText(
              context,
              title: 'Your name',
              initial: s.displayName,
              hint: 'For example: Vedant',
            );
            if (value != null) {
              await ctl.update(
                (current) => current.copyWith(displayName: value.trim()),
              );
            }
          },
        ),
        _SwitchRow(
          icon: Icons.draw_outlined,
          title: 'Add a signature',
          subtitle: 'Text added to the end of new messages',
          value: s.signatureEnabled,
          onChanged: (value) => ctl
              .update((current) => current.copyWith(signatureEnabled: value)),
        ),
        _ActionRow(
          icon: Icons.edit_note_rounded,
          title: 'Signature text',
          subtitle: s.signature.isEmpty ? 'Not set' : s.signature,
          onTap: () async {
            final value = await _editText(
              context,
              title: 'Signature',
              initial: s.signature,
              hint: 'Best regards, ...',
              maxLines: 5,
            );
            if (value != null) {
              await ctl.update(
                (current) => current.copyWith(
                  signature: value.trim(),
                  signatureEnabled:
                      value.trim().isNotEmpty ? true : current.signatureEnabled,
                ),
              );
            }
          },
        ),
        _SwitchRow(
          icon: Icons.copy_all_outlined,
          title: 'Bcc myself',
          subtitle: 'Send yourself a copy of every message',
          value: s.bccSelf,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(bccSelf: value)),
        ),
        _SwitchRow(
          icon: Icons.warning_amber_rounded,
          title: 'Ask before discarding a draft',
          value: s.confirmDiscard,
          onChanged: (value) =>
              ctl.update((current) => current.copyWith(confirmDiscard: value)),
        ),
      ],
    );
  }
}

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctl = ref.read(settingsProvider.notifier);

    if (!value) {
      await ctl.update((s) => s.copyWith(appLockEnabled: false));
      return;
    }

    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Set up a screen lock or fingerprint in your phone settings '
              'first.',
            ),
          ),
        );
        return;
      }

      final ok = await auth.authenticate(
        localizedReason: 'Confirm to turn on app lock',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) {
        await ctl.update((s) => s.copyWith(appLockEnabled: true));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('App lock is not available: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return _Section(
      title: 'Privacy and security',
      children: [
        _SwitchRow(
          icon: Icons.fingerprint_rounded,
          title: 'App lock',
          subtitle: 'Ask for fingerprint, face or screen lock',
          value: s.appLockEnabled,
          onChanged: (value) => _toggleLock(context, ref, value),
        ),
        _ChoiceRow<int>(
          icon: Icons.timer_outlined,
          title: 'Lock after',
          current: s.appLockDelaySeconds,
          enabled: s.appLockEnabled,
          options: const <int, String>{
            0: 'Immediately',
            30: '30 seconds',
            60: '1 minute',
            300: '5 minutes',
            900: '15 minutes',
          },
          onChanged: (value) => ctl.update(
            (current) => current.copyWith(appLockDelaySeconds: value),
          ),
        ),
        const _InfoRow(
          icon: Icons.verified_user_outlined,
          title: 'S/MIME signing and encryption',
          value: 'Coming soon',
        ),
        const _Note(
          'Messages are currently read and sent through Gmail without '
          'S/MIME. HTML mail is always shown as plain text for safety.',
        ),
      ],
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Section(
      title: 'About',
      children: [
        const _InfoRow(
          icon: Icons.info_outline_rounded,
          title: 'SignMail',
          value: 'Version $appVersion',
        ),
        _ActionRow(
          icon: Icons.description_outlined,
          title: 'Open-source licenses',
          subtitle: 'Libraries used by this app',
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'SignMail',
            applicationVersion: appVersion,
          ),
        ),
        _ActionRow(
          icon: Icons.restart_alt_rounded,
          title: 'Reset settings',
          subtitle: 'Put every setting back to its default',
          danger: true,
          onTap: () async {
            final ok = await _confirm(
              context,
              title: 'Reset all settings?',
              message: 'Your account and mail are not affected.',
              action: 'Reset',
            );
            if (ok) {
              await ref.read(settingsProvider.notifier).reset();
            }
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- widgets

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: _muted,
                fontSize: 11.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 66, color: _border),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.danger = false});

  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _iconBox,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: danger ? _danger : _mint),
    );
  }
}

Widget _subtitle(String? text) {
  if (text == null) {
    return const SizedBox.shrink();
  }
  return Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ListTile(
        enabled: enabled,
        leading: _IconBox(icon: icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: subtitle == null ? null : _subtitle(subtitle),
        trailing: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
        onTap: enabled ? () => onChanged(!value) : null,
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.current,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final T current;
  final Map<T, String> options;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ListTile(
        enabled: enabled,
        leading: _IconBox(icon: icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: _subtitle(options[current] ?? '$current'),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF718194),
        ),
        onTap: !enabled
            ? null
            : () async {
                final picked = await showModalBottomSheet<T>(
                  context: context,
                  showDragHandle: true,
                  backgroundColor: _card,
                  builder: (sheet) => SafeArea(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          for (final entry in options.entries)
                            ListTile(
                              title: Text(entry.value),
                              trailing: entry.key == current
                                  ? const Icon(Icons.check_rounded, color: _mint)
                                  : null,
                              onTap: () => Navigator.pop(sheet, entry.key),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
                if (picked != null && picked != current) {
                  onChanged(picked);
                }
              },
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _IconBox(icon: icon, danger: danger),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: danger ? _danger : null,
        ),
      ),
      subtitle: _subtitle(subtitle),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _mint),
            )
          : const Icon(Icons.chevron_right_rounded, color: Color(0xFF718194)),
      onTap: onTap,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _IconBox(icon: icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: _subtitle(value),
      trailing: trailing,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Text(
        text,
        style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.45),
      ),
    );
  }
}

// ----------------------------------------------------------------- helpers

String _clock(DateTime time) {
  final hours = time.hour.toString().padLeft(2, '0');
  final minutes = time.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = time.year == now.year &&
      time.month == now.month &&
      time.day == now.day;
  return today ? 'at $hours:$minutes' : 'on ${time.day}/${time.month} $hours:$minutes';
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: _card,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _editText(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  int maxLines = 1,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialog) => _TextDialog(
      title: title,
      initial: initial,
      hint: hint,
      maxLines: maxLines,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.maxLines,
    this.hint,
  });

  final String title;
  final String initial;
  final String? hint;
  final int maxLines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _card,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: widget.maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../providers.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);

/// Covers the whole app with a lock screen when app lock is on.
///
/// The app locks at start-up and again when it was in the background for
/// longer than the delay chosen in the settings.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _locked = false;
  bool _authenticating = false;
  DateTime? _pausedAt;
  DateTime? _lastAuthAt;
  String? _error;

  /// True when this device cannot authenticate at all (no screen lock set).
  /// Only then is turning the lock off offered, so it cannot be bypassed by
  /// simply cancelling.
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _locked = ref.read(settingsProvider).appLockEnabled;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    if (!settings.appLockEnabled) {
      return;
    }

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;

      final recentlyAuthenticated = _lastAuthAt != null &&
          DateTime.now().difference(_lastAuthAt!).inSeconds < 3;

      if (pausedAt != null &&
          !_authenticating &&
          !recentlyAuthenticated &&
          DateTime.now().difference(pausedAt).inSeconds >=
              settings.appLockDelaySeconds) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) {
      return;
    }

    _authenticating = true;
    if (mounted) {
      setState(() => _error = null);
    }

    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock SignMail',
        options: const AuthenticationOptions(stickyAuth: true),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _locked = !ok;
        _error = ok ? null : 'Authentication was cancelled.';
      });
    } catch (error) {
      if (mounted) {
        final unavailable = error is PlatformException &&
            const <String>{'NotAvailable', 'PasscodeNotSet', 'NotEnrolled'}
                .contains(error.code);
        setState(() {
          _unavailable = unavailable;
          _error = unavailable
              ? 'This device has no screen lock or biometrics set up.'
              : 'Could not verify your identity.';
        });
      }
    } finally {
      _authenticating = false;
      _lastAuthAt = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.appLockEnabled),
    );
    final showLock = enabled && _locked;

    return Stack(
      children: [
        widget.child,
        if (showLock)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF0A0F16),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded, size: 52, color: _mint),
                        const SizedBox(height: 18),
                        const Text(
                          'SignMail is locked',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use your fingerprint, face or screen lock to '
                          'continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, height: 1.4),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFB3BA),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _unlock,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Unlock'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _mint,
                            foregroundColor: const Color(0xFF071311),
                          ),
                        ),
                        if (_unavailable) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .update(
                                    (s) => s.copyWith(appLockEnabled: false),
                                  );
                              if (mounted) {
                                setState(() => _locked = false);
                              }
                            },
                            child: const Text('Turn off app lock'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
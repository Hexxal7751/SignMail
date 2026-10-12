import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_settings.dart';
import 'gmail_auth_service.dart';
import 'mail_service.dart';
import 'notification_service.dart';

/// The result of one "look for new mail" run.
class CheckOutcome {
  const CheckOutcome({
    required this.ok,
    required this.message,
    this.newCount = 0,
  });

  final bool ok;
  final String message;
  final int newCount;
}

/// The last recorded run, shown on the settings page.
class SyncStatus {
  const SyncStatus({
    required this.at,
    required this.ok,
    required this.message,
  });

  final DateTime at;
  final bool ok;
  final String message;
}

/// Finds unread mail that has not been announced yet and notifies about it.
///
/// Used both by the background job and by the "Check now" button.
class NewMailChecker {
  const NewMailChecker();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _lastUidKey = 'signmail.sync.lastUid';
  static const String _statusKey = 'signmail.sync.status';

  /// Records that the user has now seen everything up to the newest message,
  /// so none of it is announced again.
  Future<void> rememberSeen(Iterable<MailSummary> messages) async {
    try {
      if (messages.isEmpty) {
        return;
      }
      final newest = messages.map((m) => m.uid).reduce(math.max);
      final last = await _readLastUid();
      if (last == null || newest > last) {
        await _storage.write(key: _lastUidKey, value: newest.toString());
      }
    } catch (_) {
      // Only affects whether an old message is announced twice.
    }
  }

  Future<int?> _readLastUid() async {
    final raw = await _storage.read(key: _lastUidKey);
    return raw == null ? null : int.tryParse(raw);
  }

  /// Forget everything (used when signing out).
  Future<void> reset() async {
    try {
      await _storage.delete(key: _lastUidKey);
      await _storage.delete(key: _statusKey);
    } catch (_) {
      // Nothing else to do.
    }
  }

  /// The most recent recorded run, if any.
  static Future<SyncStatus?> readStatus() async {
    try {
      final raw = await _storage.read(key: _statusKey);
      if (raw == null) {
        return null;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SyncStatus(
        at: DateTime.parse(json['at'] as String).toLocal(),
        ok: json['ok'] as bool,
        message: json['message'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeStatus(bool ok, String message) async {
    try {
      await _storage.write(
        key: _statusKey,
        value: jsonEncode(<String, Object>{
          'at': DateTime.now().toUtc().toIso8601String(),
          'ok': ok,
          'message': message,
        }),
      );
    } catch (_) {
      // Status is informational only.
    }
  }

  /// Looks for new mail. [manual] runs from the "Check now" button: it also
  /// works while notifications are off and reports what it found.
  Future<CheckOutcome> run({bool manual = false}) async {
    final settings = await const SettingsStore().load();

    if (!manual && !settings.notificationsEnabled) {
      return const CheckOutcome(ok: true, message: 'Notifications are off.');
    }

    final auth = GmailAuthService();
    if (await auth.savedEmail() == null) {
      return const CheckOutcome(ok: false, message: 'No account connected.');
    }

    try {
      // Background runs have no screen, so they use the silent token path.
      final inbox =
          await MailService(auth, background: !manual).fetchInbox(count: 25);

      final last = await _readLastUid();
      final newest =
          inbox.isEmpty ? 0 : inbox.map((m) => m.uid).reduce(math.max);

      // The very first run only sets a starting point.
      final fresh = last == null
          ? <MailSummary>[]
          : inbox.where((m) => !m.isSeen && m.uid > last).toList();

      if (newest > (last ?? 0)) {
        await _storage.write(key: _lastUidKey, value: newest.toString());
      }

      if (fresh.isNotEmpty && settings.notificationsEnabled) {
        await NotificationService.instance.showNewMail(fresh, settings);
      }

      final message = fresh.isEmpty
          ? 'Checked, no new mail.'
          : 'Checked, ${fresh.length} new.';
      await _writeStatus(true, message);
      return CheckOutcome(ok: true, message: message, newCount: fresh.length);
    } on MailServiceException catch (error) {
      await _writeStatus(false, error.message);
      return CheckOutcome(ok: false, message: error.message);
    } catch (error) {
      final message = 'Check failed: $error';
      await _writeStatus(false, message);
      return CheckOutcome(ok: false, message: message);
    }
  }
}
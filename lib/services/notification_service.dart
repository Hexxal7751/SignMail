import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_settings.dart';
import 'mail_service.dart';

/// Shows system notifications for new mail.
///
/// The small status-bar icon is `ic_stat_notification` and the coloured
/// picture is `ic_notification_large`; both are copied into the Android
/// project from the `branding/` folder by `tools/patch_android.py`.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _mailId = 1001;
  static const int _testId = 1002;
  static const String _smallIcon = 'ic_stat_notification';
  static const Color _accent = Color(0xFF8A6BFF);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) {
      return;
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Whether the system currently lets this app show notifications.
  Future<bool> areEnabled() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Asks for the notification permission (Android 13 and newer).
  Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Opens the system notification settings for this app.
  Future<void> openSystemSettings() async {
    await init();
    await _plugin.openAppNotificationSettings();
  }

  // Android fixes sound and vibration when a channel is created, so each
  // combination gets its own channel.
  NotificationDetails _details(AppSettings s, {StyleInformation? style}) {
    final channelId =
        'new_mail_${s.notifySound ? 's' : 'q'}${s.notifyVibrate ? 'v' : 'n'}';

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'New mail',
        channelDescription: 'Alerts for new messages in your inbox',
        icon: _smallIcon,
        largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
        color: _accent,
        importance: Importance.high,
        priority: Priority.high,
        playSound: s.notifySound,
        enableVibration: s.notifyVibrate,
        category: AndroidNotificationCategory.email,
        visibility: s.notifyPreview
            ? NotificationVisibility.public
            : NotificationVisibility.private,
        styleInformation: style,
      ),
    );
  }

  /// Announces freshly arrived messages (newest first).
  Future<void> showNewMail(List<MailSummary> fresh, AppSettings s) async {
    if (fresh.isEmpty) {
      return;
    }
    await init();

    final String title;
    final String body;
    StyleInformation? style;

    if (fresh.length == 1) {
      final mail = fresh.first;
      title = s.notifyPreview ? mail.senderName : 'New message';
      body = s.notifyPreview ? mail.subject : 'You have a new message.';
    } else {
      title = '${fresh.length} new messages';
      if (s.notifyPreview) {
        final senders = fresh.map((m) => m.senderName).toSet().take(3);
        body = senders.join(', ');
        style = InboxStyleInformation(
          fresh
              .take(6)
              .map((m) => '${m.senderName}  ${m.subject}')
              .toList(),
          contentTitle: title,
          summaryText: 'SignMail',
        );
      } else {
        body = 'Open SignMail to read them.';
      }
    }

    await _plugin.show(
      id: _mailId,
      title: title,
      body: body,
      notificationDetails: _details(s, style: style),
      payload: 'inbox',
    );
  }

  /// A sample notification so the user can check sound and appearance.
  Future<void> showTest(AppSettings s) async {
    await init();
    await _plugin.show(
      id: _testId,
      title: 'Notifications are working',
      body: 'This is how new mail will look.',
      notificationDetails: _details(s),
    );
  }

  /// Removes the new-mail notification (for example once the app is open).
  Future<void> clearMailNotification() async {
    await init();
    await _plugin.cancel(id: _mailId);
  }
}
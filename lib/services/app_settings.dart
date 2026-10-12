import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App version shown on the settings page.
const String appVersion = '0.1.0';

/// Every user-changeable preference of the app.
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.backgroundCheck = true,
    this.backgroundIntervalMinutes = 15,
    this.notifySound = true,
    this.notifyVibrate = true,
    this.notifyPreview = true,
    this.inboxPageSize = 40,
    this.autoRefreshSeconds = 120,
    this.markReadOnOpen = true,
    this.compactList = false,
    this.showAvatars = true,
    this.textScalePercent = 100,
    this.displayName = '',
    this.signatureEnabled = false,
    this.signature = '',
    this.bccSelf = false,
    this.confirmDiscard = true,
    this.appLockEnabled = false,
    this.appLockDelaySeconds = 60,
  });

  /// Master switch for new-mail notifications.
  final bool notificationsEnabled;

  /// Also look for new mail while the app is closed.
  final bool backgroundCheck;

  /// How often the background check runs (Android minimum is 15).
  final int backgroundIntervalMinutes;

  final bool notifySound;
  final bool notifyVibrate;

  /// Show sender and subject in notifications.
  final bool notifyPreview;

  /// How many messages the inbox loads.
  final int inboxPageSize;

  /// Inbox refresh interval while the app is open (0 = off).
  final int autoRefreshSeconds;

  final bool markReadOnOpen;
  final bool compactList;
  final bool showAvatars;

  /// 100 = system default size.
  final int textScalePercent;

  /// Name shown to recipients (empty = just the address).
  final String displayName;
  final bool signatureEnabled;
  final String signature;
  final bool bccSelf;
  final bool confirmDiscard;

  final bool appLockEnabled;

  /// How long the app may stay in the background before it locks.
  final int appLockDelaySeconds;

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? backgroundCheck,
    int? backgroundIntervalMinutes,
    bool? notifySound,
    bool? notifyVibrate,
    bool? notifyPreview,
    int? inboxPageSize,
    int? autoRefreshSeconds,
    bool? markReadOnOpen,
    bool? compactList,
    bool? showAvatars,
    int? textScalePercent,
    String? displayName,
    bool? signatureEnabled,
    String? signature,
    bool? bccSelf,
    bool? confirmDiscard,
    bool? appLockEnabled,
    int? appLockDelaySeconds,
  }) {
    return AppSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      backgroundCheck: backgroundCheck ?? this.backgroundCheck,
      backgroundIntervalMinutes:
          backgroundIntervalMinutes ?? this.backgroundIntervalMinutes,
      notifySound: notifySound ?? this.notifySound,
      notifyVibrate: notifyVibrate ?? this.notifyVibrate,
      notifyPreview: notifyPreview ?? this.notifyPreview,
      inboxPageSize: inboxPageSize ?? this.inboxPageSize,
      autoRefreshSeconds: autoRefreshSeconds ?? this.autoRefreshSeconds,
      markReadOnOpen: markReadOnOpen ?? this.markReadOnOpen,
      compactList: compactList ?? this.compactList,
      showAvatars: showAvatars ?? this.showAvatars,
      textScalePercent: textScalePercent ?? this.textScalePercent,
      displayName: displayName ?? this.displayName,
      signatureEnabled: signatureEnabled ?? this.signatureEnabled,
      signature: signature ?? this.signature,
      bccSelf: bccSelf ?? this.bccSelf,
      confirmDiscard: confirmDiscard ?? this.confirmDiscard,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockDelaySeconds: appLockDelaySeconds ?? this.appLockDelaySeconds,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'notificationsEnabled': notificationsEnabled,
        'backgroundCheck': backgroundCheck,
        'backgroundIntervalMinutes': backgroundIntervalMinutes,
        'notifySound': notifySound,
        'notifyVibrate': notifyVibrate,
        'notifyPreview': notifyPreview,
        'inboxPageSize': inboxPageSize,
        'autoRefreshSeconds': autoRefreshSeconds,
        'markReadOnOpen': markReadOnOpen,
        'compactList': compactList,
        'showAvatars': showAvatars,
        'textScalePercent': textScalePercent,
        'displayName': displayName,
        'signatureEnabled': signatureEnabled,
        'signature': signature,
        'bccSelf': bccSelf,
        'confirmDiscard': confirmDiscard,
        'appLockEnabled': appLockEnabled,
        'appLockDelaySeconds': appLockDelaySeconds,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings();

    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    int number(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    String text(String key, String fallback) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    return AppSettings(
      notificationsEnabled:
          flag('notificationsEnabled', d.notificationsEnabled),
      backgroundCheck: flag('backgroundCheck', d.backgroundCheck),
      backgroundIntervalMinutes: number(
        'backgroundIntervalMinutes',
        d.backgroundIntervalMinutes,
      ).clamp(15, 24 * 60),
      notifySound: flag('notifySound', d.notifySound),
      notifyVibrate: flag('notifyVibrate', d.notifyVibrate),
      notifyPreview: flag('notifyPreview', d.notifyPreview),
      inboxPageSize: number('inboxPageSize', d.inboxPageSize).clamp(10, 300),
      autoRefreshSeconds:
          number('autoRefreshSeconds', d.autoRefreshSeconds).clamp(0, 3600),
      markReadOnOpen: flag('markReadOnOpen', d.markReadOnOpen),
      compactList: flag('compactList', d.compactList),
      showAvatars: flag('showAvatars', d.showAvatars),
      textScalePercent:
          number('textScalePercent', d.textScalePercent).clamp(80, 160),
      displayName: text('displayName', d.displayName),
      signatureEnabled: flag('signatureEnabled', d.signatureEnabled),
      signature: text('signature', d.signature),
      bccSelf: flag('bccSelf', d.bccSelf),
      confirmDiscard: flag('confirmDiscard', d.confirmDiscard),
      appLockEnabled: flag('appLockEnabled', d.appLockEnabled),
      appLockDelaySeconds:
          number('appLockDelaySeconds', d.appLockDelaySeconds).clamp(0, 3600),
    );
  }
}

/// Saves and loads [AppSettings]. Safe to use from background isolates.
class SettingsStore {
  const SettingsStore();

  static const String _key = 'signmail.settings.v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<AppSettings> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) {
        return const AppSettings();
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
    } catch (_) {
      // Unreadable settings fall back to the defaults.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
    } catch (_) {
      // The settings still apply for this session.
    }
  }
}
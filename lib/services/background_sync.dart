import 'package:workmanager/workmanager.dart';

import 'app_settings.dart';
import 'new_mail_checker.dart';
import 'notification_service.dart';

const String _periodicTask = 'signmail.checkMail';
const String _uniqueName = 'signmail-check-mail';

/// Entry point Android runs in the background (no UI, no open app).
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await NotificationService.instance.init();
      await const NewMailChecker().run();
    } catch (_) {
      // The next scheduled run simply tries again.
    }
    return true;
  });
}

/// Schedules the periodic "look for new mail" job.
class BackgroundSync {
  const BackgroundSync._();

  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) {
      return;
    }

    try {
      await Workmanager().initialize(backgroundDispatcher);
      _ready = true;
    } catch (_) {
      // Background checks are optional; the app works without them.
    }
  }

  /// Starts, updates or stops the job to match [settings].
  static Future<void> apply(
    AppSettings settings, {
    required bool signedIn,
  }) async {
    await initialize();
    if (!_ready) {
      return;
    }

    try {
      final wanted =
          signedIn && settings.notificationsEnabled && settings.backgroundCheck;

      if (!wanted) {
        await Workmanager().cancelByUniqueName(_uniqueName);
        return;
      }

      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _periodicTask,
        frequency: Duration(minutes: settings.backgroundIntervalMinutes),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // Ignore scheduling problems; they are shown by the status line.
    }
  }
}
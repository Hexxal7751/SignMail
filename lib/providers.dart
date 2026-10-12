import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/app_settings.dart';
import 'services/background_sync.dart';
import 'services/gmail_auth_service.dart';
import 'services/mail_service.dart';
import 'services/new_mail_checker.dart';

/// The shared Google account / Gmail authorization service.
final authServiceProvider = Provider<GmailAuthService>(
  (ref) => GmailAuthService(),
);

/// Reads and sends Gmail.
final mailServiceProvider = Provider<MailService>(
  (ref) => MailService(ref.watch(authServiceProvider)),
);

/// The email address connected on this device, or null when signed out.
final savedEmailProvider = FutureProvider<String?>(
  (ref) => ref.watch(authServiceProvider).savedEmail(),
);

/// Settings loaded at startup (overridden in `main`).
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// The user's preferences, saved whenever they change.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  /// Applies [change] to the current settings and saves the result.
  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final previous = state;
    final next = change(previous);
    state = next;

    await const SettingsStore().save(next);

    final scheduleChanged =
        previous.notificationsEnabled != next.notificationsEnabled ||
            previous.backgroundCheck != next.backgroundCheck ||
            previous.backgroundIntervalMinutes !=
                next.backgroundIntervalMinutes;

    if (scheduleChanged) {
      final signedIn = await ref.read(authServiceProvider).savedEmail() != null;
      await BackgroundSync.apply(next, signedIn: signedIn);
    }
  }

  /// Puts every preference back to its default.
  Future<void> reset() => update((_) => const AppSettings());
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// The outcome of the latest background or manual mail check.
final syncStatusProvider = FutureProvider.autoDispose<SyncStatus?>(
  (ref) => NewMailChecker.readStatus(),
);

/// The inbox list, loaded from Gmail and refreshable on demand.
class InboxController extends AsyncNotifier<List<MailSummary>> {
  @override
  Future<List<MailSummary>> build() {
    final service = ref.watch(mailServiceProvider);
    final size = ref.read(settingsProvider).inboxPageSize;
    return _load(service, size);
  }

  Future<List<MailSummary>> _load(MailService service, int size) async {
    final messages = await service.fetchInbox(count: size);
    // Anything shown here counts as seen, so it is not announced again.
    await const NewMailChecker().rememberSeen(messages);
    return messages;
  }

  /// Reloads the inbox while keeping the current list visible.
  Future<void> refresh() async {
    final service = ref.read(mailServiceProvider);
    final size = ref.read(settingsProvider).inboxPageSize;
    state = const AsyncLoading<List<MailSummary>>().copyWithPrevious(state);
    state = await AsyncValue.guard<List<MailSummary>>(
      () => _load(service, size),
    );
  }

  /// Shows one message as read without another network call.
  void markSeenLocally(int uid) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    state = AsyncData<List<MailSummary>>(<MailSummary>[
      for (final message in current)
        message.uid == uid ? message.asSeen() : message,
    ]);
  }
}

final inboxProvider =
    AsyncNotifierProvider<InboxController, List<MailSummary>>(
  InboxController.new,
);

/// The full text of one message, downloaded when it is opened.
final messageBodyProvider =
    FutureProvider.autoDispose.family<MailBody, int>(
  (ref, uid) => ref.watch(mailServiceProvider).fetchBody(
        uid,
        markSeen: ref.read(settingsProvider).markReadOnOpen,
      ),
);
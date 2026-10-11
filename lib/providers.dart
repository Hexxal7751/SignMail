import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/gmail_auth_service.dart';
import 'services/mail_service.dart';

/// The shared Google account / Gmail authorization service.
final authServiceProvider = Provider<GmailAuthService>(
  (ref) => GmailAuthService(),
);

/// Reads Gmail over IMAP.
final mailServiceProvider = Provider<MailService>(
  (ref) => MailService(ref.watch(authServiceProvider)),
);

/// The email address connected on this device, or null when signed out.
final savedEmailProvider = FutureProvider<String?>(
  (ref) => ref.watch(authServiceProvider).savedEmail(),
);

/// The inbox list, loaded from Gmail and refreshable on demand.
class InboxController extends AsyncNotifier<List<MailSummary>> {
  @override
  Future<List<MailSummary>> build() {
    return ref.watch(mailServiceProvider).fetchInbox();
  }

  /// Reloads the inbox while keeping the current list visible.
  Future<void> refresh() async {
    final service = ref.read(mailServiceProvider);
    state = const AsyncLoading<List<MailSummary>>().copyWithPrevious(state);
    state = await AsyncValue.guard<List<MailSummary>>(
      () => service.fetchInbox(),
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
  (ref, uid) => ref.watch(mailServiceProvider).fetchBody(uid),
);
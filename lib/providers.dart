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

/// Used once at startup: like [savedEmailProvider], but also tries to
/// recover an already authorized Google account without any screen.
final startupEmailProvider = FutureProvider<String?>(
  (ref) => ref.watch(authServiceProvider).restoreSession(),
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

/// The folder shown in the mail list.
final currentFolderProvider = StateProvider<MailFolder>(
  (ref) => MailFolder.inbox,
);

/// The text typed into the search field (empty = no search).
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Show only unread messages.
final unreadOnlyProvider = StateProvider<bool>((ref) => false);

/// All folders of the account (falls back to just the inbox).
final foldersProvider = FutureProvider<List<MailFolder>>((ref) async {
  try {
    return await ref.watch(mailServiceProvider).fetchFolders();
  } catch (_) {
    return const <MailFolder>[MailFolder.inbox];
  }
});

/// The message list of the current folder or search.
class InboxController extends AsyncNotifier<List<MailSummary>> {
  int _limit = 40;
  bool _canLoadMore = false;
  bool _loadingMore = false;

  /// True when older messages can still be loaded.
  bool get canLoadMore => _canLoadMore;

  @override
  Future<List<MailSummary>> build() {
    final folder = ref.watch(currentFolderProvider);
    final query = ref.watch(searchQueryProvider);
    ref.watch(mailServiceProvider);
    _limit = ref.read(settingsProvider).inboxPageSize;
    _canLoadMore = false;
    return _load(folder, query, _limit);
  }

  Future<List<MailSummary>> _fetch(
    MailFolder folder,
    String query,
    int limit,
  ) {
    final service = ref.read(mailServiceProvider);
    return query.trim().isEmpty
        ? service.fetchInbox(count: limit, folder: folder.path)
        : service.searchMessages(query, folder: folder.path);
  }

  Future<List<MailSummary>> _load(
    MailFolder folder,
    String query,
    int limit,
  ) async {
    final messages = await _fetch(folder, query, limit);
    _canLoadMore = query.trim().isEmpty && messages.length >= limit - 1;

    // Anything shown in the inbox counts as seen, so it is not announced again.
    if (folder.kind == FolderKind.inbox && query.trim().isEmpty) {
      await const NewMailChecker().rememberSeen(messages);
    }
    return messages;
  }

  /// Reloads the list while keeping the current messages visible.
  Future<void> refresh() async {
    final folder = ref.read(currentFolderProvider);
    final query = ref.read(searchQueryProvider);
    state = const AsyncLoading<List<MailSummary>>().copyWithPrevious(state);
    state = await AsyncValue.guard<List<MailSummary>>(
      () => _load(folder, query, _limit),
    );
  }

  /// Loads the next page of older messages.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !_canLoadMore || _loadingMore || state.isLoading) {
      return;
    }

    _loadingMore = true;
    final folder = ref.read(currentFolderProvider);
    final query = ref.read(searchQueryProvider);
    final nextLimit = _limit + ref.read(settingsProvider).inboxPageSize;

    try {
      final messages = await _fetch(folder, query, nextLimit);
      _limit = nextLimit;
      _canLoadMore = query.trim().isEmpty && messages.length > current.length;
      state = AsyncData<List<MailSummary>>(messages);
    } catch (_) {
      _canLoadMore = false;
      state = AsyncData<List<MailSummary>>(current);
    } finally {
      _loadingMore = false;
    }
  }

  void _patch(int uid, MailSummary Function(MailSummary message) change) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    state = AsyncData<List<MailSummary>>(<MailSummary>[
      for (final message in current)
        message.uid == uid ? change(message) : message,
    ]);
  }

  void _remove(int uid) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    state = AsyncData<List<MailSummary>>(<MailSummary>[
      for (final message in current)
        if (message.uid != uid) message,
    ]);
  }

  String? _pathOf(FolderKind kind) {
    final folders = ref.read(foldersProvider).valueOrNull;
    if (folders == null) {
      return null;
    }
    for (final folder in folders) {
      if (folder.kind == kind) {
        return folder.path;
      }
    }
    return null;
  }

  /// Shows one message as read without another network call.
  void markSeenLocally(int uid) => _patch(uid, (message) => message.asSeen());

  /// Adds or removes the star.
  Future<void> toggleStar(MailSummary message) async {
    final folder = ref.read(currentFolderProvider).path;
    final next = !message.isFlagged;

    _patch(message.uid, (m) => m.copyWith(isFlagged: next));
    try {
      await ref
          .read(mailServiceProvider)
          .setFlagged(folder, message.uid, next);
    } catch (_) {
      _patch(message.uid, (m) => m.copyWith(isFlagged: !next));
      rethrow;
    }
  }

  /// Marks a message as read or unread.
  Future<void> setRead(int uid, bool read) async {
    final folder = ref.read(currentFolderProvider).path;

    _patch(uid, (m) => m.copyWith(isSeen: read));
    try {
      await ref.read(mailServiceProvider).setSeen(folder, uid, read);
    } catch (_) {
      _patch(uid, (m) => m.copyWith(isSeen: !read));
      rethrow;
    }
  }

  /// Moves a message out of the current folder into "All Mail".
  Future<void> archive(int uid) async {
    final folder = ref.read(currentFolderProvider).path;
    final target = _pathOf(FolderKind.all);

    _remove(uid);
    if (target == null) {
      await refresh();
      throw const MailServiceException(
        'Could not find the archive folder yet. Try again in a moment.',
      );
    }

    try {
      await ref.read(mailServiceProvider).moveMessage(folder, uid, target);
    } catch (_) {
      await refresh();
      rethrow;
    }
  }

  /// Moves a message to Trash (or deletes it for good when in Trash).
  Future<void> delete(int uid) async {
    final folder = ref.read(currentFolderProvider).path;
    final trash = _pathOf(FolderKind.trash);

    _remove(uid);
    try {
      await ref
          .read(mailServiceProvider)
          .deleteMessage(folder, uid, trashPath: trash);
    } catch (_) {
      await refresh();
      rethrow;
    }
  }
}

final inboxProvider =
    AsyncNotifierProvider<InboxController, List<MailSummary>>(
  InboxController.new,
);

/// The full text of one message, downloaded when it is opened.
final messageBodyProvider =
    FutureProvider.autoDispose.family<MailBody, ({String folder, int uid})>(
  (ref, key) => ref.watch(mailServiceProvider).fetchBody(
        key.uid,
        folder: key.folder,
        markSeen: ref.read(settingsProvider).markReadOnOpen,
      ),
);
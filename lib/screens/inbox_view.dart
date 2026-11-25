import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/mail_service.dart';
import 'message_screen.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);
const Color _card = Color(0xFF111923);
const Color _border = Color(0xFF1E2A37);
const Color _readBg = Color(0xFF0A0F16);
const Color _unreadBg = Color(0xFF0F1923);

/// The mail tab: folder messages, search, swipe actions, pull to refresh.
class InboxView extends ConsumerWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final folder = ref.watch(currentFolderProvider);
    final settings = ref.watch(settingsProvider);
    final unreadOnly = ref.watch(unreadOnlyProvider);
    final query = ref.watch(searchQueryProvider);
    final canMove = ref.watch(foldersProvider).valueOrNull != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: RefreshIndicator(
          color: _mint,
          onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
          child: inbox.when(
            data: (messages) => _MessageList(
              messages: messages,
              folder: folder,
              query: query,
              unreadOnly: unreadOnly,
              compact: settings.compactList,
              showAvatars: settings.showAvatars,
              canMove: canMove,
            ),
            loading: () => const _ScrollableCenter(
              child: CircularProgressIndicator(color: _mint),
            ),
            error: (error, stackTrace) => _ScrollableCenter(
              child: _ErrorPanel(error: error, busy: inbox.isLoading),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 100),
      children: [Center(child: child)],
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.folder,
    required this.query,
    required this.unreadOnly,
    required this.compact,
    required this.showAvatars,
    required this.canMove,
  });

  final List<MailSummary> messages;
  final MailFolder folder;
  final String query;
  final bool unreadOnly;
  final bool compact;
  final bool showAvatars;
  final bool canMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = messages.where((message) => !message.isSeen).length;
    final visible = unreadOnly
        ? messages.where((message) => !message.isSeen).toList()
        : messages;
    final canLoadMore = ref.read(inboxProvider.notifier).canLoadMore;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.maxScrollExtent -
                    notification.metrics.pixels <
                360) {
          ref.read(inboxProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: visible.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _Header(folder: folder, query: query, unread: unread);
          }

          if (index == visible.length + 1) {
            if (canLoadMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _mint,
                    ),
                  ),
                ),
              );
            }
            if (visible.isEmpty) {
              return _EmptyList(
                searching: query.isNotEmpty,
                unreadOnly: unreadOnly,
              );
            }
            return const SizedBox(height: 8);
          }

          final message = visible[index - 1];
          return _MailRow(
            key: ValueKey<String>('${folder.path}:${message.uid}'),
            message: message,
            folder: folder,
            compact: compact,
            showAvatars: showAvatars,
            canMove: canMove,
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.folder,
    required this.query,
    required this.unread,
  });

  final MailFolder folder;
  final String query;
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadOnly = ref.watch(unreadOnlyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SearchField(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            query.isEmpty ? folder.name : 'Search results',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(
            query.isNotEmpty
                ? 'Matches for “$query” in ${folder.name}'
                : (unread == 0 ? 'No unread messages' : '$unread unread'),
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !unreadOnly,
                selectedColor: const Color(0xFF21423F),
                onSelected: (_) =>
                    ref.read(unreadOnlyProvider.notifier).state = false,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Unread'),
                selected: unreadOnly,
                selectedColor: const Color(0xFF21423F),
                onSelected: (_) =>
                    ref.read(unreadOnlyProvider.notifier).state = true,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _border),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    ref.read(searchQueryProvider.notifier).state = value.trim();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (_controller.text != next) {
        _controller.text = next;
      }
    });

    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: _border),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: 'Search mail',
          prefixIcon: const Icon(Icons.search_rounded, color: _muted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, color: _muted),
                onPressed: () {
                  _controller.clear();
                  _submit('');
                },
              );
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: pill,
          enabledBorder: pill,
          focusedBorder: pill.copyWith(
            borderSide: const BorderSide(color: _mint, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _MailRow extends ConsumerWidget {
  const _MailRow({
    super.key,
    required this.message,
    required this.folder,
    required this.compact,
    required this.showAvatars,
    required this.canMove,
  });

  final MailSummary message;
  final MailFolder folder;
  final bool compact;
  final bool showAvatars;
  final bool canMove;

  Widget _swipeBackground(
    IconData icon,
    String label,
    Alignment alignment,
    Color color,
  ) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerLeft) ...[
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ] else ...[
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !message.isSeen;
    final inbox = ref.read(inboxProvider.notifier);
    final inTrash = folder.kind == FolderKind.trash;
    final canArchive =
        folder.kind == FolderKind.inbox || folder.kind == FolderKind.other;

    final DismissDirection direction = !canMove
        ? DismissDirection.none
        : (canArchive
            ? DismissDirection.horizontal
            : DismissDirection.endToStart);

    final nameStyle = TextStyle(
      fontSize: 15,
      fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
      color: unread ? const Color(0xFFE6EDF3) : const Color(0xFFB4C0CC),
    );

    final row = Material(
      color: unread ? _unreadBg : _readBg,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MessageScreen(
                summary: message,
                folder: folder.path,
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, compact ? 8 : 12, 6, compact ? 8 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAvatars) ...[
                SenderAvatar(
                  label: message.senderName,
                  size: compact ? 34 : 42,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                        if (message.hasAttachment) ...[
                          const Icon(
                            Icons.attach_file_rounded,
                            size: 15,
                            color: _muted,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          message.dateLabel,
                          style: TextStyle(
                            color: unread ? _mint : _muted,
                            fontSize: 12,
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message.subject,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread
                            ? const Color(0xFFE6EDF3)
                            : _muted,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: message.isFlagged ? 'Remove star' : 'Star',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await inbox.toggleStar(message);
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('$error')),
                    );
                  }
                },
                icon: Icon(
                  message.isFlagged
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: message.isFlagged
                      ? const Color(0xFFF2C14E)
                      : _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      children: [
        Dismissible(
          key: ValueKey<String>('dismiss:${folder.path}:${message.uid}'),
          direction: direction,
          background: _swipeBackground(
            Icons.archive_outlined,
            'Archive',
            Alignment.centerLeft,
            const Color(0xFF1F5A52),
          ),
          secondaryBackground: _swipeBackground(
            inTrash
                ? Icons.delete_forever_outlined
                : Icons.delete_outline_rounded,
            inTrash ? 'Delete forever' : 'Delete',
            Alignment.centerRight,
            const Color(0xFF6A2A2F),
          ),
          onDismissed: (swipe) async {
            final messenger = ScaffoldMessenger.of(context);
            final archiving = swipe == DismissDirection.startToEnd;
            try {
              if (archiving) {
                await inbox.archive(message.uid);
              } else {
                await inbox.delete(message.uid);
              }
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    archiving
                        ? 'Archived'
                        : (inTrash ? 'Deleted forever' : 'Moved to Trash'),
                  ),
                ),
              );
            } catch (error) {
              messenger.showSnackBar(SnackBar(content: Text('$error')));
            }
          },
          child: row,
        ),
        Divider(
          height: 1,
          color: _border,
          indent: showAvatars ? 68 : 14,
        ),
      ],
    );
  }
}

/// Folder list (Inbox, Starred, Sent, ...) shown in the side drawer.
class FolderDrawer extends ConsumerWidget {
  const FolderDrawer({super.key});

  IconData _iconFor(FolderKind kind) {
    switch (kind) {
      case FolderKind.inbox:
        return Icons.inbox_rounded;
      case FolderKind.starred:
        return Icons.star_border_rounded;
      case FolderKind.sent:
        return Icons.send_rounded;
      case FolderKind.drafts:
        return Icons.drafts_outlined;
      case FolderKind.all:
        return Icons.all_inbox_rounded;
      case FolderKind.spam:
        return Icons.report_gmailerrorred_rounded;
      case FolderKind.trash:
        return Icons.delete_outline_rounded;
      case FolderKind.other:
        return Icons.label_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    final current = ref.watch(currentFolderProvider);
    final email = ref.watch(savedEmailProvider).valueOrNull;

    final items = folders.valueOrNull ?? const <MailFolder>[MailFolder.inbox];

    return Drawer(
      backgroundColor: const Color(0xFF0E151D),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SignMail',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 6),
            for (final folder in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  selected: folder == current,
                  selectedColor: _mint,
                  selectedTileColor: const Color(0xFF16302D),
                  leading: Icon(_iconFor(folder.kind)),
                  title: Text(
                    folder.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    ref.read(currentFolderProvider.notifier).state = folder;
                    ref.read(searchQueryProvider.notifier).state = '';
                    ref.read(unreadOnlyProvider.notifier).state = false;
                    Navigator.of(context).pop();
                  },
                ),
              ),
            if (folders.isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(color: _mint),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.searching, required this.unreadOnly});

  final bool searching;
  final bool unreadOnly;

  @override
  Widget build(BuildContext context) {
    final title = searching
        ? 'No matches'
        : (unreadOnly ? 'Nothing unread' : 'Nothing here');
    final subtitle = searching
        ? 'Try different words.'
        : (unreadOnly
            ? 'You are all caught up.'
            : 'Messages in this folder will show up here.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.inbox_outlined,
            size: 36,
            color: _mint,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends ConsumerWidget {
  const _ErrorPanel({required this.error, required this.busy});

  final Object error;
  final bool busy;

  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(authServiceProvider).connectGmail();
      await ref.read(inboxProvider.notifier).refresh();
    } catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Reconnect failed: $failure'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = error;
    final needsReconnect =
        failure is MailServiceException && failure.needsReconnect;
    final message =
        failure is MailServiceException ? failure.message : failure.toString();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF263342)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 34, color: _mint),
          const SizedBox(height: 14),
          const Text(
            'Could not load your mail',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 8),
          SelectableText(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: _mint),
            )
          else ...[
            FilledButton(
              onPressed: () => ref.read(inboxProvider.notifier).refresh(),
              style: FilledButton.styleFrom(
                backgroundColor: _mint,
                foregroundColor: const Color(0xFF071311),
              ),
              child: const Text('Try again'),
            ),
            if (needsReconnect) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _reconnect(context, ref),
                child: const Text('Reconnect Google'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
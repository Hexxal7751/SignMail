import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/mail_service.dart';
import 'message_screen.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);
const Color _card = Color(0xFF111923);
const Color _border = Color(0xFF263342);

/// The inbox tab: the newest Gmail messages, pull down to refresh.
class InboxView extends ConsumerWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final settings = ref.watch(settingsProvider);

    return RefreshIndicator(
      color: _mint,
      onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
      child: inbox.when(
        data: (messages) => _MessageList(
          messages: messages,
          compact: settings.compactList,
          showAvatars: settings.showAvatars,
        ),
        loading: () => const _ScrollableCenter(
          child: CircularProgressIndicator(color: _mint),
        ),
        error: (error, stackTrace) => _ScrollableCenter(
          child: _ErrorPanel(error: error, busy: inbox.isLoading),
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

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.compact,
    required this.showAvatars,
  });

  final List<MailSummary> messages;
  final bool compact;
  final bool showAvatars;

  @override
  Widget build(BuildContext context) {
    final unread = messages.where((message) => !message.isSeen).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(
            'Inbox',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            unread == 0 ? 'You are all caught up' : '$unread unread',
            style: const TextStyle(color: _muted),
          ),
        ),
        if (messages.isEmpty)
          const _EmptyInbox()
        else
          for (final message in messages)
            _MailTile(
              message: message,
              compact: compact,
              showAvatars: showAvatars,
            ),
      ],
    );
  }
}

class _MailTile extends StatelessWidget {
  const _MailTile({
    required this.message,
    required this.compact,
    required this.showAvatars,
  });

  final MailSummary message;
  final bool compact;
  final bool showAvatars;

  @override
  Widget build(BuildContext context) {
    final unread = !message.isSeen;
    final weight = unread ? FontWeight.w800 : FontWeight.w500;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MessageScreen(summary: message),
              ),
            );
          },
          child: Container(
            padding: EdgeInsets.all(compact ? 9 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: unread ? const Color(0xFF2C5C52) : _border,
              ),
            ),
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
                              style: TextStyle(
                                fontWeight: weight,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            message.dateLabel,
                            style: TextStyle(
                              color: unread ? _mint : _muted,
                              fontSize: 12,
                              fontWeight: weight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.subject,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unread
                              ? const Color(0xFFE6EDF3)
                              : _muted,
                          fontWeight: weight,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 34, color: _mint),
          SizedBox(height: 14),
          Text(
            'Your inbox is empty',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          SizedBox(height: 8),
          Text(
            'New messages will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13),
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
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 34, color: _mint),
          const SizedBox(height: 14),
          const Text(
            'Could not load your inbox',
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);

/// Reads one message from the inbox.
class MessageScreen extends ConsumerWidget {
  const MessageScreen({super.key, required this.summary});

  final MailSummary summary;

  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    ComposeSeed Function(String? myEmail) seed,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final me = await ref.read(authServiceProvider).savedEmail();
    if (!context.mounted) {
      return;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => ComposeScreen(seed: seed(me)),
      ),
    );

    if (sent == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Message sent')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = messageBodyProvider(summary.uid);
    final body = ref.watch(provider);

    ref.listen<AsyncValue<MailBody>>(provider, (previous, next) {
      if (next.hasValue && ref.read(settingsProvider).markReadOnOpen) {
        ref.read(inboxProvider.notifier).markSeenLocally(summary.uid);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Message',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: body.valueOrNull == null
          ? null
          : _ActionBar(
              onReply: () => _write(
                context,
                ref,
                (me) => ComposeSeed.reply(
                  summary: summary,
                  body: body.requireValue,
                  myEmail: me,
                ),
              ),
              onReplyAll: () => _write(
                context,
                ref,
                (me) => ComposeSeed.reply(
                  summary: summary,
                  body: body.requireValue,
                  myEmail: me,
                  replyAll: true,
                ),
              ),
              onForward: () => _write(
                context,
                ref,
                (me) => ComposeSeed.forward(
                  summary: summary,
                  body: body.requireValue,
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              summary.subject,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SenderAvatar(label: summary.senderName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        summary.senderEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              summary.fullDateLabel,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            const _SignatureNote(),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFF263342), height: 1),
            const SizedBox(height: 18),
            body.when(
              data: (mail) => _BodyContent(mail: mail),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: _mint),
                ),
              ),
              error: (error, stackTrace) => _BodyError(
                message: error is MailServiceException
                    ? error.message
                    : error.toString(),
                onRetry: () => ref.invalidate(provider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round letter avatar for a sender.
class SenderAvatar extends StatelessWidget {
  const SenderAvatar({super.key, required this.label, this.size = 42});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = label.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    final hue = (trimmed.hashCode.abs() % 360).toDouble();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HSLColor.fromAHSL(1, hue, 0.45, 0.28).toColor(),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SignatureNote extends StatelessWidget {
  const _SignatureNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF19252F),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF263342)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: _muted),
          SizedBox(width: 6),
          Text(
            'S/MIME signature: not checked yet',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BodyContent extends StatelessWidget {
  const _BodyContent({required this.mail});

  final MailBody mail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mail.toLine.isNotEmpty) ...[
          Text(
            'To: ${mail.toLine}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
        ],
        SelectableText(
          mail.text.isEmpty
              ? '(This message has no text content.)'
              : mail.text,
          style: const TextStyle(
            fontSize: 15,
            height: 1.55,
            color: Color(0xFFDCE4EC),
          ),
        ),
        if (mail.wasHtmlOnly) ...[
          const SizedBox(height: 16),
          const Text(
            'Formatted (HTML) message shown as plain text for safety.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
        if (mail.attachmentNames.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'ATTACHMENTS',
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in mail.attachmentNames)
                Chip(
                  avatar: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text(name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Opening attachments is coming soon.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _BodyError extends StatelessWidget {
  const _BodyError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded, color: _mint, size: 36),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onReply,
    required this.onReplyAll,
    required this.onForward,
  });

  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101720),
        border: Border(top: BorderSide(color: Color(0xFF263342))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReply,
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Reply'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _mint,
                    foregroundColor: const Color(0xFF071311),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Reply all',
                onPressed: onReplyAll,
                icon: const Icon(Icons.reply_all_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: 'Forward',
                onPressed: onForward,
                icon: const Icon(Icons.forward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
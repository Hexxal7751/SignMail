import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/attachment_files.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';
import 'dart:typed_data' show Uint8List;

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);

/// Reads one message.
class MessageScreen extends ConsumerWidget {
  const MessageScreen({
    super.key,
    required this.summary,
    this.folder = 'INBOX',
  });

  final MailSummary summary;

  /// The folder (path) the message lives in.
  final String folder;

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

  Future<void> _manage(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(InboxController inbox) action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await action(ref.read(inboxProvider.notifier));
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = messageBodyProvider((folder: folder, uid: summary.uid));
    final body = ref.watch(provider);
    final kind = ref.watch(currentFolderProvider).kind;
    final canArchive = kind == FolderKind.inbox || kind == FolderKind.other;
    final inTrash = kind == FolderKind.trash;

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
        actions: [
          if (canArchive)
            IconButton(
              tooltip: 'Archive',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () => _manage(
                context,
                ref,
                (inbox) => inbox.archive(summary.uid),
                'Archived',
              ),
            ),
          IconButton(
            tooltip: inTrash ? 'Delete forever' : 'Delete',
            icon: Icon(
              inTrash
                  ? Icons.delete_forever_outlined
                  : Icons.delete_outline_rounded,
            ),
            onPressed: () => _manage(
              context,
              ref,
              (inbox) => inbox.delete(summary.uid),
              inTrash ? 'Deleted forever' : 'Moved to Trash',
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'unread') {
                _manage(
                  context,
                  ref,
                  (inbox) => inbox.setRead(summary.uid, false),
                  'Marked as unread',
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'unread',
                child: Text('Mark as unread'),
              ),
            ],
          ),
        ],
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
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
                  data: (mail) => _BodyContent(
                    mail: mail,
                    folder: folder,
                    uid: summary.uid,
                  ),
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

Future<void> _openAttachment(
  BuildContext context,
  WidgetRef ref,
  String folder,
  int uid,
  MailAttachment attachment, {
  bool saveOnly = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Downloading ${attachment.name}…'),
      duration: const Duration(seconds: 30),
    ),
  );

  try {
    final bytes = await ref
        .read(mailServiceProvider)
        .fetchAttachment(folder, uid, attachment.fetchId);
    messenger.hideCurrentSnackBar();

    if (saveOnly) {
      final saved = await AttachmentFiles.save(attachment.name, bytes);
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text('Saved ${attachment.name}')),
        );
      }
      return;
    }

    if (attachment.isImage) {
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => _ImagePreview(
          name: attachment.name,
          bytes: bytes,
        ),
      );
      return;
    }

    final error = await AttachmentFiles.open(attachment.name, bytes);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  } catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open the attachment: $error')),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('This picture cannot be shown.'),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => AttachmentFiles.save(name, bytes),
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: () => AttachmentFiles.open(name, bytes),
                  child: const Text('Open with…'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForAttachment(MailAttachment attachment) {
  final type = (attachment.mimeType ?? '').toLowerCase();
  final name = attachment.name.toLowerCase();

  if (type.startsWith('image/')) return Icons.image_outlined;
  if (type.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (type.startsWith('video/')) return Icons.movie_outlined;
  if (type.contains('pdf') || name.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }
  if (name.endsWith('.zip') || name.endsWith('.rar') || name.endsWith('.7z')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

class _BodyContent extends ConsumerWidget {
  const _BodyContent({
    required this.mail,
    required this.folder,
    required this.uid,
  });

  final MailBody mail;
  final String folder;
  final int uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        if (mail.attachments.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'ATTACHMENTS (${mail.attachments.length})',
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final attachment in mail.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFF111923),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openAttachment(
                    context,
                    ref,
                    folder,
                    uid,
                    attachment,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF263342)),
                    ),
                    child: Row(
                      children: [
                        Icon(_iconForAttachment(attachment), color: _mint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              if (attachment.sizeLabel.isNotEmpty)
                                Text(
                                  attachment.sizeLabel,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Save',
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () => _openAttachment(
                            context,
                            ref,
                            folder,
                            uid,
                            attachment,
                            saveOnly: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
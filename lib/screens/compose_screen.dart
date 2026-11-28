import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/mail_service.dart';
import '../smime/contact_certs.dart';
import '../smime/identity_dialogs.dart';
import '../smime/identity_vault.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);
const Color _card = Color(0xFF111923);

/// Gmail allows 25 MB per message; attachments grow by about a third when
/// encoded, so stay safely below.
const int _maxAttachmentBytes = 18 * 1024 * 1024;

final RegExp _emailPattern = RegExp(
  r"[A-Za-z0-9._%+'\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+",
);

/// What a new message starts with (empty, a reply or a forward).
class ComposeSeed {
  const ComposeSeed({
    this.to = const <String>[],
    this.cc = const <String>[],
    this.subject = '',
    this.quote = '',
    this.inReplyTo,
    this.references,
    this.title = 'New message',
  });

  /// A reply to [summary]; [replyAll] also includes the other recipients.
  factory ComposeSeed.reply({
    required MailSummary summary,
    required MailBody body,
    required String? myEmail,
    bool replyAll = false,
  }) {
    final me = (myEmail ?? '').toLowerCase();
    final sender = (body.replyToEmail ?? summary.senderEmail).trim();

    final to = <String>[if (sender.isNotEmpty) sender];
    final cc = <String>[];

    if (replyAll) {
      final taken = <String>{sender.toLowerCase(), me};
      for (final address in <String>[...body.toEmails, ...body.ccEmails]) {
        if (taken.add(address.toLowerCase())) {
          cc.add(address);
        }
      }
    }

    final quoted = body.text
        .split('\n')
        .map((line) => '> ${line.trimRight()}')
        .join('\n');

    final references = <String>[
      if ((body.references ?? '').isNotEmpty) body.references!,
      if ((body.messageId ?? '').isNotEmpty) body.messageId!,
    ].join(' ');

    return ComposeSeed(
      to: to,
      cc: cc,
      subject: _prefixed('Re:', summary.subject),
      quote: '\n\nOn ${summary.fullDateLabel}, ${summary.senderName} '
          '<${summary.senderEmail}> wrote:\n$quoted',
      inReplyTo: body.messageId,
      references: references.isEmpty ? null : references,
      title: replyAll ? 'Reply all' : 'Reply',
    );
  }

  /// A forward of [summary] (attachments are not carried over yet).
  factory ComposeSeed.forward({
    required MailSummary summary,
    required MailBody body,
  }) {
    return ComposeSeed(
      subject: _prefixed('Fwd:', summary.subject),
      quote: '\n\n---------- Forwarded message ----------\n'
          'From: ${summary.senderName} <${summary.senderEmail}>\n'
          'Date: ${summary.fullDateLabel}\n'
          'Subject: ${summary.subject}\n'
          'To: ${body.toLine}\n\n'
          '${body.text}',
      title: 'Forward',
    );
  }

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String quote;
  final String? inReplyTo;
  final String? references;
  final String title;

  static String _prefixed(String prefix, String subject) {
    final trimmed = subject.trim();
    if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed;
    }
    return '$prefix $trimmed';
  }
}

/// Full-screen editor for writing and sending a message.
///
/// Closes with `true` when the message was sent.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, this.seed = const ComposeSeed()});

  final ComposeSeed seed;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _to;
  late final TextEditingController _cc;
  late final TextEditingController _bcc;
  late final TextEditingController _subject;
  late final TextEditingController _body;

  final List<OutgoingAttachment> _attachments = <OutgoingAttachment>[];

  bool _showCcBcc = false;
  bool _sending = false;
  bool _dirty = false;
  bool _closing = false;
  String? _error;

  IdentityInfo? _identity;
  bool _sign = false;
  bool _encrypt = false;

  @override
  void initState() {
    super.initState();

    final seed = widget.seed;
    final settings = ref.read(settingsProvider);

    final signature = settings.signatureEnabled && settings.signature.isNotEmpty
        ? '\n\n-- \n${settings.signature}'
        : '';

    _to = TextEditingController(text: seed.to.join(', '));
    _cc = TextEditingController(text: seed.cc.join(', '));
    _bcc = TextEditingController();
    _subject = TextEditingController(text: seed.subject);
    _body = TextEditingController(text: '$signature${seed.quote}');
    _body.selection = const TextSelection.collapsed(offset: 0);

    _showCcBcc = seed.cc.isNotEmpty;

    for (final controller in <TextEditingController>[
      _to,
      _cc,
      _bcc,
      _subject,
      _body,
    ]) {
      controller.addListener(_markDirty);
    }

    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final info = await IdentityVault.instance.info();
    if (!mounted) {
      return;
    }
    setState(() {
      _identity = info;
      // Sign by default when a usable certificate exists.
      _sign = info != null && !info.isExpired;
    });
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  /// Splits typed text into valid addresses and unreadable leftovers.
  ({List<String> valid, List<String> invalid}) _parse(String raw) {
    final valid = <String>[];
    final invalid = <String>[];

    for (final part in raw.split(RegExp(r'[,;\n]'))) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final match = _emailPattern.firstMatch(token);
      if (match == null) {
        invalid.add(token);
      } else {
        valid.add(match.group(0)!);
      }
    }

    return (valid: valid, invalid: invalid);
  }

  int get _attachmentBytes =>
      _attachments.fold<int>(0, (sum, file) => sum + file.bytes.length);

  Future<void> _pickFiles() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null) {
        return;
      }

      var skipped = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          skipped++;
          continue;
        }
        if (_attachmentBytes + bytes.length > _maxAttachmentBytes) {
          skipped++;
          continue;
        }
        _attachments.add(OutgoingAttachment(name: file.name, bytes: bytes));
      }

      if (!mounted) {
        return;
      }
      setState(() => _dirty = true);

      if (skipped > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$skipped file(s) were not added (attachments are limited to '
              '${_maxAttachmentBytes ~/ (1024 * 1024)} MB in total).',
            ),
          ),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add the file: $error')),
      );
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();

    final to = _parse(_to.text);
    final cc = _parse(_cc.text);
    final bcc = _parse(_bcc.text);

    final bad = <String>[...to.invalid, ...cc.invalid, ...bcc.invalid];
    if (bad.isNotEmpty) {
      setState(() => _error = 'This is not an email address: ${bad.first}');
      return;
    }
    if (to.valid.isEmpty && cc.valid.isEmpty && bcc.valid.isEmpty) {
      setState(() => _error = 'Add at least one recipient.');
      return;
    }

    if (_subject.text.trim().isEmpty && _body.text.trim().isEmpty) {
      final ok = await _confirm(
        title: 'Send an empty message?',
        message: 'This message has no subject and no text.',
        action: 'Send',
      );
      if (!ok || !mounted) {
        return;
      }
    }

    // Signing and encrypting need the opened certificate.
    if (_sign || _encrypt) {
      final identity = await ensureIdentityUnlocked(context);
      if (!mounted) {
        return;
      }
      if (identity == null) {
        setState(() {
          _error = 'Unlock your certificate to sign or encrypt this message, '
              'or switch Sign and Encrypt off.';
        });
        return;
      }
    }

    if (_encrypt) {
      final myAddress =
          (await ref.read(authServiceProvider).savedEmail() ?? '').toLowerCase();
      final everyone = <String>{
        for (final a in <String>[...to.valid, ...cc.valid, ...bcc.valid])
          a.toLowerCase(),
      }..remove(myAddress);

      final missing = <String>[];
      for (final address in everyone) {
        if (await ContactCerts.instance.forEmail(address) == null) {
          missing.add(address);
        }
      }
      if (!mounted) {
        return;
      }
      if (missing.isNotEmpty) {
        setState(() {
          _error = 'No encryption certificate for: ${missing.join(', ')}. '
              'You can only encrypt to people whose signed message you have '
              'opened, or whose certificate you added on the Certificates '
              'tab.';
        });
        return;
      }
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final settings = ref.read(settingsProvider);
      final myEmail = await ref.read(authServiceProvider).savedEmail();

      final blind = <String>[
        ...bcc.valid,
        if (settings.bccSelf && myEmail != null) myEmail,
      ];

      await ref.read(mailServiceProvider).sendMail(
            OutgoingMail(
              to: to.valid,
              cc: cc.valid,
              bcc: blind,
              subject: _subject.text.trim(),
              body: _body.text,
              attachments: List<OutgoingAttachment>.of(_attachments),
              inReplyTo: widget.seed.inReplyTo,
              references: widget.seed.references,
              fromName: settings.displayName,
              sign: _sign,
              encrypt: _encrypt,
            ),
          );

      if (!mounted) {
        return;
      }
      _close(sent: true);
    } on MailServiceException catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not send the message: $error';
        });
      }
    }
  }

  void _close({required bool sent}) {
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(sent);
      }
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _tryClose() async {
    if (_sending) {
      return;
    }

    final settings = ref.read(settingsProvider);
    if (_dirty && settings.confirmDiscard) {
      final discard = await _confirm(
        title: 'Discard this message?',
        message: 'What you wrote will be lost.',
        action: 'Discard',
      );
      if (!discard || !mounted) {
        return;
      }
    }

    _close(sent: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _tryClose();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            onPressed: _sending ? null : _tryClose,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(
            widget.seed.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Attach files',
              onPressed: _sending ? null : _pickFiles,
              icon: const Icon(Icons.attach_file_rounded),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
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
              )
            else
              IconButton(
                tooltip: 'Send',
                onPressed: _send,
                color: _mint,
                icon: const Icon(Icons.send_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              TextField(
                controller: _to,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'To',
                  hintText: 'name@example.com',
                  suffixIcon: TextButton(
                    onPressed: () =>
                        setState(() => _showCcBcc = !_showCcBcc),
                    child: Text(_showCcBcc ? 'Hide' : 'Cc/Bcc'),
                  ),
                ),
              ),
              if (_showCcBcc) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _cc,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Cc'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bcc,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Bcc'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _subject,
                enabled: !_sending,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                enabled: !_sending,
                minLines: 10,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final file in _attachments)
                      InputChip(
                        avatar: const Icon(Icons.attach_file_rounded, size: 16),
                        label: Text('${file.name} · ${_size(file.bytes.length)}'),
                        onDeleted: _sending
                            ? null
                            : () => setState(() => _attachments.remove(file)),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1A1D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF5A2D33)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Color(0xFFFF8A94),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFFB3BA),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SmimeOptions(
                identity: _identity,
                sign: _sign,
                encrypt: _encrypt,
                enabled: !_sending,
                onSign: (value) => setState(() => _sign = value),
                onEncrypt: (value) => setState(() => _encrypt = value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The Sign / Encrypt switches at the bottom of the editor.
class _SmimeOptions extends StatelessWidget {
  const _SmimeOptions({
    required this.identity,
    required this.sign,
    required this.encrypt,
    required this.enabled,
    required this.onSign,
    required this.onEncrypt,
  });

  final IdentityInfo? identity;
  final bool sign;
  final bool encrypt;
  final bool enabled;
  final ValueChanged<bool> onSign;
  final ValueChanged<bool> onEncrypt;

  @override
  Widget build(BuildContext context) {
    final info = identity;
    final available = enabled && info != null;

    String caption;
    if (info == null) {
      caption = 'Import your certificate on the Certificates tab to sign and '
          'encrypt messages. Until then, messages are sent unsigned.';
    } else if (info.isExpired) {
      caption = 'Your certificate has expired, so messages cannot be signed.';
    } else if (sign && encrypt) {
      caption = 'Signed with your certificate, then encrypted for every '
          'recipient and for you.';
    } else if (sign) {
      caption = 'Signed with your certificate, so recipients can check it '
          'came from you.';
    } else if (encrypt) {
      caption = 'Encrypted for every recipient and for you. Not signed.';
    } else {
      caption = 'Sent as an ordinary message (neither signed nor encrypted).';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF263342)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Sign'),
                selected: sign,
                showCheckmark: false,
                selectedColor: const Color(0xFF21423F),
                onSelected: available && !(info?.isExpired ?? false)
                    ? onSign
                    : null,
              ),
              FilterChip(
                avatar: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Encrypt'),
                selected: encrypt,
                showCheckmark: false,
                selectedColor: const Color(0xFF21423F),
                onSelected: available ? onEncrypt : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
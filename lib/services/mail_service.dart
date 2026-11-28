import 'dart:async' show TimeoutException;
import 'dart:convert' show base64Encode, latin1, utf8;
import 'dart:io' show SocketException, TlsException;
import 'dart:typed_data' show Uint8List;

import 'package:enough_mail/enough_mail.dart';

import '../smime/cms_envelope.dart';
import '../smime/cms_sign.dart';
import '../smime/contact_certs.dart';
import '../smime/crypto_verify.dart' show Oids;
import '../smime/identity_vault.dart';
import '../smime/mime_build.dart';
import '../smime/smime_inspector.dart';
import '../smime/trust_service.dart';
import '../smime/x509.dart';
import 'gmail_auth_service.dart';

/// What can be said about the encryption of a received message.
enum EncryptionState {
  /// The message was not encrypted.
  none,

  /// The message was encrypted and has been opened.
  decrypted,

  /// The message is encrypted; the user's certificate must be unlocked.
  locked,

  /// The message is encrypted but could not be opened.
  failed,
}

/// What a mail folder is for.
enum FolderKind { inbox, starred, sent, drafts, all, spam, trash, other }

/// A Gmail folder (label) that can be opened.
class MailFolder {
  const MailFolder({
    required this.path,
    required this.name,
    required this.kind,
  });

  final String path;
  final String name;
  final FolderKind kind;

  static const MailFolder inbox = MailFolder(
    path: 'INBOX',
    name: 'Inbox',
    kind: FolderKind.inbox,
  );

  @override
  bool operator ==(Object other) => other is MailFolder && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// One row of the inbox list.
class MailSummary {
  const MailSummary({
    required this.uid,
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.date,
    required this.isSeen,
    required this.isFlagged,
    this.hasAttachment = false,
  });

  final int uid;
  final String senderName;
  final String senderEmail;
  final String subject;
  final DateTime? date;
  final bool isSeen;
  final bool isFlagged;
  final bool hasAttachment;

  MailSummary copyWith({bool? isSeen, bool? isFlagged}) {
    return MailSummary(
      uid: uid,
      senderName: senderName,
      senderEmail: senderEmail,
      subject: subject,
      date: date,
      isSeen: isSeen ?? this.isSeen,
      isFlagged: isFlagged ?? this.isFlagged,
      hasAttachment: hasAttachment,
    );
  }

  /// The same message, shown as read.
  MailSummary asSeen() => copyWith(isSeen: true);

  /// Short date for list rows: time today, otherwise day and month.
  String get dateLabel {
    final value = date?.toLocal();
    if (value == null) {
      return '';
    }

    final now = DateTime.now();
    final isToday = value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;

    if (isToday) {
      return _time(value);
    }

    final label = '${value.day} ${_months[value.month - 1]}';
    return value.year == now.year ? label : '$label ${value.year}';
  }

  /// Full date for the message screen.
  String get fullDateLabel {
    final value = date?.toLocal();
    if (value == null) {
      return '';
    }

    return '${value.day} ${_months[value.month - 1]} ${value.year}, '
        '${_time(value)}';
  }

  static String _time(DateTime value) {
    final hours = value.hour.toString().padLeft(2, '0');
    final minutes = value.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// A file attached to a received message.
class MailAttachment {
  const MailAttachment({
    required this.fetchId,
    required this.name,
    this.size,
    this.mimeType,
    this.data,
  });

  final String fetchId;
  final String name;
  final int? size;
  final String? mimeType;

  /// The file content, already downloaded with the message.
  final Uint8List? data;

  /// True for pictures the app can show itself.
  bool get isImage {
    final type = (mimeType ?? '').toLowerCase();
    return type.startsWith('image/') && type != 'image/svg+xml';
  }

  String get sizeLabel {
    final bytes = size;
    if (bytes == null) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// A picture that is part of an HTML mail (referenced as `cid:`).
class InlineImage {
  const InlineImage({required this.mimeType, required this.bytes});

  final String mimeType;
  final Uint8List bytes;

  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// The downloaded content of one message.
class MailBody {
  const MailBody({
    required this.text,
    required this.toLine,
    required this.wasHtmlOnly,
    this.html,
    this.inlineImages = const <String, InlineImage>{},
    this.smime,
    this.encryption = EncryptionState.none,
    this.encryptionNote,
    this.attachments = const <MailAttachment>[],
    this.messageId,
    this.references,
    this.replyToEmail,
    this.toEmails = const <String>[],
    this.ccEmails = const <String>[],
  });

  final String text;
  final String toLine;
  final List<MailAttachment> attachments;

  /// True when the message had no plain-text version and was converted.
  final bool wasHtmlOnly;

  /// The HTML version of the message, if there is one (not yet cleaned).
  final String? html;

  /// Pictures inside the HTML, by lower-case content id.
  final Map<String, InlineImage> inlineImages;

  /// What was found out about the signature (null: not signed).
  final SmimeResult? smime;

  /// Whether the message was encrypted, and how opening it went.
  final EncryptionState encryption;
  final String? encryptionNote;

  /// Header values needed to reply in the same conversation.
  final String? messageId;
  final String? references;
  final String? replyToEmail;
  final List<String> toEmails;
  final List<String> ccEmails;

  List<String> get attachmentNames =>
      attachments.map((attachment) => attachment.name).toList();
}

/// A file attached to an outgoing message.
class OutgoingAttachment {
  const OutgoingAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// A message to be sent.
class OutgoingMail {
  const OutgoingMail({
    required this.to,
    required this.subject,
    required this.body,
    this.cc = const <String>[],
    this.bcc = const <String>[],
    this.attachments = const <OutgoingAttachment>[],
    this.inReplyTo,
    this.references,
    this.fromName,
    this.sign = false,
    this.encrypt = false,
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;
  final List<OutgoingAttachment> attachments;
  final String? inReplyTo;
  final String? references;
  final String? fromName;

  /// Sign the message with the user's S/MIME certificate.
  final bool sign;

  /// Encrypt the message for every recipient.
  final bool encrypt;
}

/// A mail problem that can be shown to the user as is.
class MailServiceException implements Exception {
  const MailServiceException(this.message, {this.needsReconnect = false});

  final String message;

  /// True when signing in to Google again is the likely fix.
  final bool needsReconnect;

  @override
  String toString() => message;
}

/// Reads and manages Gmail over IMAP using the signed-in Google account
/// (XOAUTH2), and sends over SMTP.
///
/// Each call opens a short-lived secure connection.
class MailService {
  MailService(this._auth, {this.background = false});

  final GmailAuthService _auth;

  /// True when running without a screen (background mail check).
  final bool background;

  static const String _host = 'imap.gmail.com';
  static const int _port = 993;
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 465;

  static const String _listCriteria = '(UID FLAGS ENVELOPE BODYSTRUCTURE)';

  /// All folders and labels of the account.
  Future<List<MailFolder>> fetchFolders() {
    return _session<List<MailFolder>>((client) async {
      final boxes = await client.listMailboxes(recursive: true);

      final folders = <MailFolder>[];
      for (final box in boxes) {
        if (box.isNotSelectable) {
          continue;
        }
        final kind = _kindOf(box);
        folders.add(
          MailFolder(path: box.path, name: _folderName(box, kind), kind: kind),
        );
      }

      folders.sort((a, b) {
        final byKind = _order(a.kind).compareTo(_order(b.kind));
        return byKind != 0
            ? byKind
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!folders.any((folder) => folder.kind == FolderKind.inbox)) {
        folders.insert(0, MailFolder.inbox);
      }
      return folders;
    });
  }

  /// The newest [count] messages of [folder], newest first.
  Future<List<MailSummary>> fetchInbox({
    int count = 40,
    String folder = 'INBOX',
  }) {
    return _withFolder<List<MailSummary>>(folder, (client, box) async {
      if (box.messagesExists == 0) {
        return const <MailSummary>[];
      }

      final result = await client.fetchRecentMessages(
        messageCount: count - 1,
        criteria: _listCriteria,
      );

      final summaries = <MailSummary>[];
      for (final message in result.messages.reversed) {
        final summary = _summaryOf(message);
        if (summary != null) {
          summaries.add(summary);
        }
      }

      return summaries;
    });
  }

  /// Messages of [folder] that contain [query], newest first.
  Future<List<MailSummary>> searchMessages(
    String query, {
    String folder = 'INBOX',
    int limit = 60,
  }) {
    final safe = query.replaceAll(RegExp(r'["\\\r\n]'), ' ').trim();

    return _withFolder<List<MailSummary>>(folder, (client, box) async {
      if (safe.isEmpty || box.messagesExists == 0) {
        return const <MailSummary>[];
      }

      final found = await client.uidSearchMessages(
        searchCriteria: 'TEXT "$safe"',
      );

      final ids = List<int>.of(found.matchingSequence?.toList() ?? <int>[]);
      if (ids.isEmpty) {
        return const <MailSummary>[];
      }

      ids.sort();
      final latest =
          ids.length > limit ? ids.sublist(ids.length - limit) : ids;

      final result = await client.uidFetchMessages(
        MessageSequence.fromIds(latest, isUid: true),
        _listCriteria,
      );

      final summaries = <MailSummary>[];
      for (final message in result.messages) {
        final summary = _summaryOf(message);
        if (summary != null) {
          summaries.add(summary);
        }
      }
      summaries.sort((a, b) => b.uid.compareTo(a.uid));
      return summaries;
    });
  }

  /// Downloads one message, and marks it as read when [markSeen] is set.
  Future<MailBody> fetchBody(
    int uid, {
    String folder = 'INBOX',
    bool markSeen = true,
  }) {
    return _withFolder<MailBody>(folder, (client, box) async {
      final result = await client.uidFetchMessage(
        uid,
        '(FLAGS BODY.PEEK[])',
      );

      if (result.messages.isEmpty) {
        throw const MailServiceException(
          'This message is no longer in this folder.',
        );
      }

      final message = result.messages.first;
      final senders = message.from;
      final fromEmail =
          (senders != null && senders.isNotEmpty) ? senders.first.email : '';

      // S/MIME: open encryption layers and check signatures on the raw
      // message exactly as it arrived.
      SmimeResult? smime;
      var encryption = EncryptionState.none;
      String? encryptionNote;
      String? viewEntity;

      final raw = _rawBytes(message);
      if (raw != null) {
        try {
          await IdentityVault.instance.tryAutoUnlock();
          final trust = await TrustService.instance.load();
          var current = raw;

          for (var depth = 0; depth < 4; depth++) {
            final found = inspectSmime(
              current,
              fromEmail: fromEmail,
              trust: trust,
              messageDate: message.decodeDate(),
            );
            if (found == null) {
              break;
            }

            if (found.status == SmimeStatus.encrypted) {
              final identity = IdentityVault.instance.unlocked;
              final cms = extractPkcs7Content(current);

              if (cms == null) {
                encryption = EncryptionState.failed;
                encryptionNote = 'The encrypted data could not be read.';
                break;
              }
              if (identity == null) {
                encryption = EncryptionState.locked;
                break;
              }

              try {
                final plain = decryptEnvelopedData(
                  cms,
                  certificate: identity.certificate,
                  privateKey: identity.privateKey,
                );
                encryption = EncryptionState.decrypted;
                current = plain;
                viewEntity = utf8.decode(plain, allowMalformed: true);
                continue;
              } on CmsException catch (error) {
                encryption = EncryptionState.failed;
                encryptionNote = error.message;
                break;
              }
            }

            smime = found;
            final inner = found.innerEntity;
            if (inner != null) {
              viewEntity = inner;
              current = Uint8List.fromList(latin1.encode(inner));
              continue;
            }
            break;
          }
        } catch (_) {
          // The message is still shown; only the S/MIME banner is missing.
        }
      }

      // Remember the certificate of a correctly signing sender, so messages
      // to that person can be encrypted later.
      final signerCert = smime?.certificate;
      if (smime != null &&
          signerCert != null &&
          smime.isSigned &&
          smime.status != SmimeStatus.signedInvalid &&
          fromEmail.isNotEmpty &&
          signerCert.emails.contains(fromEmail.toLowerCase()) &&
          signerCert.isValidAt(DateTime.now())) {
        try {
          await ContactCerts.instance.save(signerCert, onlyFor: fromEmail);
        } catch (_) {
          // Not critical.
        }
      }

      MimePart view = message;
      if (viewEntity != null) {
        final inner = MimeMessage.parseFromText(viewEntity)..parse();
        view = inner;
      }

      final plain = (view.decodeTextPlainPart() ?? '').trim();
      final html = (view.decodeTextHtmlPart() ?? '').trim();

      final inlineImages = <String, InlineImage>{};
      final attachments = <MailAttachment>[];
      try {
        _collectParts(view, inlineImages, attachments);
      } catch (_) {
        // Attachments are optional; the message can still be read.
      }

      if (markSeen) {
        try {
          // Opening a message marks it as read, like other mail apps.
          await client.uidMarkSeen(MessageSequence.fromId(uid, isUid: true));
        } catch (_) {
          // Not critical; the message simply stays unread on the server.
        }
      }

      final recipients = message.to ?? const <MailAddress>[];
      final copies = message.cc ?? const <MailAddress>[];

      String? replyTo;
      try {
        final addresses = message.decodeHeaderMailAddressValue('reply-to');
        if (addresses != null && addresses.isNotEmpty) {
          replyTo = addresses.first.email;
        }
      } catch (_) {
        // Fall back to the sender when replying.
      }

      return MailBody(
        text: plain.isNotEmpty
            ? plain
            : (html.isNotEmpty ? htmlToPlainText(html) : ''),
        html: html.isEmpty ? null : html,
        inlineImages: inlineImages,
        smime: smime,
        encryption: encryption,
        encryptionNote: encryptionNote,
        toLine: recipients.map(_labelOf).join(', '),
        attachments: attachments,
        wasHtmlOnly: plain.isEmpty && html.isNotEmpty,
        messageId: message.getHeaderValue('message-id')?.trim(),
        references: message.getHeaderValue('references')?.trim(),
        replyToEmail: replyTo,
        toEmails: recipients.map((a) => a.email).toList(),
        ccEmails: copies.map((a) => a.email).toList(),
      );
    });
  }

  /// The message exactly as the server sent it, or null if unavailable.
  Uint8List? _rawBytes(MimeMessage message) {
    final data = message.mimeData;
    if (data is BinaryMimeData) {
      return data.data;
    }
    if (data is TextMimeData) {
      return Uint8List.fromList(utf8.encode(data.text));
    }
    return null;
  }

  /// Sorts the leaf parts of a message into pictures used by the HTML
  /// ([inline]) and downloadable files ([attachments]).
  void _collectParts(
    MimePart part,
    Map<String, InlineImage> inline,
    List<MailAttachment> attachments,
  ) {
    final children = part.parts;
    if (children != null && children.isNotEmpty) {
      for (final child in children) {
        _collectParts(child, inline, attachments);
      }
      return;
    }

    final type = part.mediaType.text.toLowerCase();
    if (type.startsWith('multipart/') ||
        type == 'application/pkcs7-signature' ||
        type == 'application/x-pkcs7-signature') {
      return;
    }

    final disposition = part.getHeaderContentDisposition();
    final isAttachment = disposition?.disposition == ContentDisposition.attachment;
    final fileName = part.decodeFileName();

    final isBodyText =
        (type == 'text/plain' || type == 'text/html') &&
            !isAttachment &&
            fileName == null;
    if (isBodyText) {
      return;
    }

    Uint8List? bytes;
    try {
      bytes = part.decodeContentBinary();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) {
      return;
    }

    final contentId = part
        .getHeaderValue('content-id')
        ?.trim()
        .replaceAll(RegExp(r'^<|>$'), '');

    if (contentId != null &&
        contentId.isNotEmpty &&
        type.startsWith('image/') &&
        !isAttachment) {
      if (bytes.length <= 6 * 1024 * 1024) {
        inline[contentId.toLowerCase()] =
            InlineImage(mimeType: type, bytes: bytes);
      }
      return;
    }

    attachments.add(
      MailAttachment(
        fetchId: '${attachments.length}',
        name: fileName ?? 'attachment',
        size: bytes.length,
        mimeType: type,
        data: bytes,
      ),
    );
  }

  /// Downloads the content of one attachment (fallback when it was not
  /// already loaded with the message).
  Future<Uint8List> fetchAttachment(String folder, int uid, String fetchId) {
    return _withFolder<Uint8List>(folder, (client, box) async {
      final result = await client.uidFetchMessage(uid, '(BODY.PEEK[])');

      if (result.messages.isEmpty) {
        throw const MailServiceException(
          'This message is no longer in this folder.',
        );
      }

      final bytes = result.messages.first.getPart(fetchId)?.decodeContentBinary();
      if (bytes == null) {
        throw const MailServiceException('Could not read this attachment.');
      }
      return bytes;
    });
  }

  /// Marks a message as read or unread.
  Future<void> setSeen(String folder, int uid, bool seen) {
    return _withFolder<void>(folder, (client, box) async {
      final sequence = MessageSequence.fromId(uid, isUid: true);
      if (seen) {
        await client.uidMarkSeen(sequence);
      } else {
        await client.uidMarkUnseen(sequence);
      }
    });
  }

  /// Adds or removes the star.
  Future<void> setFlagged(String folder, int uid, bool flagged) {
    return _withFolder<void>(folder, (client, box) async {
      final sequence = MessageSequence.fromId(uid, isUid: true);
      if (flagged) {
        await client.uidMarkFlagged(sequence);
      } else {
        await client.uidMarkUnflagged(sequence);
      }
    });
  }

  /// Moves a message to another folder.
  Future<void> moveMessage(String folder, int uid, String targetPath) {
    return _withFolder<void>(folder, (client, box) async {
      await client.uidMove(
        MessageSequence.fromId(uid, isUid: true),
        targetMailboxPath: targetPath,
      );
    });
  }

  /// Moves a message to Trash, or deletes it for good when it is already
  /// in Trash.
  Future<void> deleteMessage(String folder, int uid, {String? trashPath}) {
    return _withFolder<void>(folder, (client, box) async {
      final sequence = MessageSequence.fromId(uid, isUid: true);

      if (trashPath != null && folder == trashPath) {
        await client.uidMarkDeleted(sequence);
        await client.uidExpunge(sequence);
      } else if (trashPath != null) {
        await client.uidMove(sequence, targetMailboxPath: trashPath);
      } else {
        throw const MailServiceException(
          'Could not find the Trash folder yet. Try again in a moment.',
        );
      }
    });
  }

  /// Sends a message through Gmail (SMTP). Gmail files the copy in
  /// "Sent" by itself.
  Future<void> sendMail(OutgoingMail mail) async {
    final email = await _auth.savedEmail();
    if (email == null) {
      throw const MailServiceException(
        'No account is connected yet.',
        needsReconnect: true,
      );
    }

    final token = await _token();

    if (mail.sign || mail.encrypt) {
      await _sendSecure(mail, email, token);
      return;
    }

    final name = mail.fromName?.trim();

    final builder = MessageBuilder(
      text: mail.body,
      characterSet: CharacterSet.utf8,
    )
      ..from = <MailAddress>[
        MailAddress(name == null || name.isEmpty ? null : name, email),
      ]
      ..to = <MailAddress>[for (final a in mail.to) MailAddress(null, a)]
      ..subject = mail.subject;

    if (mail.cc.isNotEmpty) {
      builder.cc = <MailAddress>[for (final a in mail.cc) MailAddress(null, a)];
    }
    if (mail.bcc.isNotEmpty) {
      builder.bcc = <MailAddress>[
        for (final a in mail.bcc) MailAddress(null, a),
      ];
    }
    if (mail.inReplyTo != null && mail.inReplyTo!.isNotEmpty) {
      builder.setHeader('In-Reply-To', mail.inReplyTo);
    }
    if (mail.references != null && mail.references!.isNotEmpty) {
      builder.setHeader('References', mail.references);
    }
    for (final file in mail.attachments) {
      builder.addBinary(
        file.bytes,
        MediaType.guessFromFileName(file.name),
        filename: file.name,
      );
    }

    final message = builder.buildMimeMessage();

    await _withSmtp(email, token, (client) async {
      await client.sendMessage(message);
    });
  }

  /// Sends a signed and/or encrypted (S/MIME) message.
  Future<void> _sendSecure(OutgoingMail mail, String email, String token) async {
    final identity = IdentityVault.instance.unlocked;
    if (identity == null) {
      throw const MailServiceException(
        'Unlock your certificate to sign or encrypt this message.',
      );
    }

    final attachments = <MimeAttachmentData>[
      for (final file in mail.attachments)
        MimeAttachmentData(
          name: file.name,
          mimeType: MediaType.guessFromFileName(file.name).text,
          bytes: file.bytes,
        ),
    ];

    var entity = buildContentEntity(mail.body, attachments);

    try {
      if (mail.sign) {
        if (!identity.certificate.isValidAt(DateTime.now())) {
          throw const MailServiceException(
            'Your certificate has expired, so it cannot be used to sign.',
          );
        }
        final cms = createSignedData(
          content: Uint8List.fromList(latin1.encode(entity)),
          signer: identity.certificate,
          privateKey: identity.privateKey,
          chain: identity.chain,
        );
        entity = buildSignedEntity(entity, cms, micalgFor(Oids.sha256));
      }

      if (mail.encrypt) {
        final everyone = <String>{
          for (final a in <String>[...mail.to, ...mail.cc, ...mail.bcc])
            a.trim().toLowerCase(),
        }..remove(email.toLowerCase());

        final certificates = <X509Certificate>[];
        final missing = <String>[];
        final expired = <String>[];

        for (final address in everyone) {
          final cert = await ContactCerts.instance.forEmail(address);
          if (cert == null) {
            missing.add(address);
          } else if (!cert.isValidAt(DateTime.now())) {
            expired.add(address);
          } else {
            certificates.add(cert);
          }
        }

        if (missing.isNotEmpty) {
          throw MailServiceException(
            'No encryption certificate for: ${missing.join(', ')}. You can '
            'only encrypt to people whose signed message you have opened, or '
            'whose certificate you added on the Certificates tab.',
          );
        }
        if (expired.isNotEmpty) {
          throw MailServiceException(
            'The certificate of ${expired.join(', ')} has expired.',
          );
        }

        // Also encrypt for yourself, so you can read your own copy.
        certificates.add(identity.certificate);

        final cms = encryptEnvelopedData(
          Uint8List.fromList(latin1.encode(entity)),
          certificates,
        );
        entity = buildEnvelopedEntity(cms);
      }
    } on CmsException catch (error) {
      throw MailServiceException(error.message);
    }

    final headers = buildMessageHeaders(
      fromName: mail.fromName?.trim(),
      fromEmail: email,
      to: mail.to,
      cc: mail.cc,
      subject: mail.subject,
      inReplyTo: mail.inReplyTo,
      references: mail.references,
    );
    final raw = assembleMessage(headers, entity);

    final name = mail.fromName?.trim();
    final from = MailAddress(name == null || name.isEmpty ? null : name, email);
    final recipients = <MailAddress>[
      for (final a in <String>{...mail.to, ...mail.cc, ...mail.bcc})
        MailAddress(null, a),
    ];

    await _withSmtp(email, token, (client) async {
      await client.sendMessageText(raw, from, recipients);
    });
  }

  /// Connects to Gmail's SMTP server, signs in, runs [action], disconnects.
  Future<void> _withSmtp(
    String email,
    String token,
    Future<void> Function(SmtpClient client) action,
  ) async {
    final client = SmtpClient('signmail.app');

    try {
      await client.connectToServer(_smtpHost, _smtpPort, isSecure: true);
      await client.ehlo();
      await client.authenticate(email, token, AuthMechanism.xoauth2);
      await action(client);
    } on MailServiceException {
      rethrow;
    } on SmtpException catch (error) {
      final details = '${error.message}'.toLowerCase();
      final looksLikeLogin = details.contains('authenticat') ||
          details.contains('credentials') ||
          details.contains('xoauth');
      throw MailServiceException(
        'Gmail did not accept the message: '
        '${error.message ?? 'unknown error'}',
        needsReconnect: looksLikeLogin,
      );
    } on SocketException {
      throw const MailServiceException(
        'No connection to Gmail. Check your internet and try again.',
      );
    } on TimeoutException {
      throw const MailServiceException('Gmail took too long to respond.');
    } on TlsException {
      throw const MailServiceException(
        'The secure connection to Gmail failed.',
      );
    } catch (error) {
      throw MailServiceException('Could not send the message: $error');
    } finally {
      try {
        await client.quit();
      } catch (_) {
        // The connection is being discarded anyway.
      }
      try {
        await client.disconnect();
      } catch (_) {
        // Already closed.
      }
    }
  }

  Future<String> _token() async {
    try {
      return await _auth.accessToken(background: background);
    } on GmailAuthException catch (error) {
      throw MailServiceException(error.message, needsReconnect: true);
    }
  }

  /// Connects, signs in, runs [action], then disconnects.
  Future<T> _session<T>(Future<T> Function(ImapClient client) action) async {
    final email = await _auth.savedEmail();
    if (email == null) {
      throw const MailServiceException(
        'No account is connected yet.',
        needsReconnect: true,
      );
    }

    final token = await _token();
    final client = ImapClient();

    try {
      await client.connectToServer(_host, _port);
      await client.authenticateWithOAuth2(email, token);
      return await action(client);
    } on MailServiceException {
      rethrow;
    } on ImapException catch (error) {
      final details = '${error.message} ${error.details}'.toLowerCase();
      final looksLikeLogin = details.contains('authenticat') ||
          details.contains('credentials') ||
          details.contains('xoauth');
      throw MailServiceException(
        'Gmail refused the connection: ${error.message ?? 'unknown error'}',
        needsReconnect: looksLikeLogin,
      );
    } on SocketException {
      throw const MailServiceException(
        'No connection to Gmail. Check your internet and try again.',
      );
    } on TimeoutException {
      throw const MailServiceException('Gmail took too long to respond.');
    } on TlsException {
      throw const MailServiceException(
        'The secure connection to Gmail failed.',
      );
    } catch (error) {
      throw MailServiceException('Unexpected mail error: $error');
    } finally {
      await _close(client);
    }
  }

  /// Like [_session], and opens the folder at [path] first.
  Future<T> _withFolder<T>(
    String path,
    Future<T> Function(ImapClient client, Mailbox box) action,
  ) {
    return _session<T>((client) async {
      final box = path.toUpperCase() == 'INBOX'
          ? await client.selectInbox()
          : await client.selectMailboxByPath(path);
      return action(client, box);
    });
  }

  Future<void> _close(ImapClient client) async {
    try {
      if (client.isLoggedIn) {
        await client.logout();
      }
    } catch (_) {
      // The connection is being discarded anyway.
    }

    try {
      await client.disconnect();
    } catch (_) {
      // Already closed.
    }
  }

  FolderKind _kindOf(Mailbox box) {
    if (box.isInbox || box.path.toUpperCase() == 'INBOX') {
      return FolderKind.inbox;
    }
    if (box.isSent) return FolderKind.sent;
    if (box.isDrafts) return FolderKind.drafts;
    if (box.isJunk) return FolderKind.spam;
    if (box.isTrash) return FolderKind.trash;
    if (box.hasFlag(MailboxFlag.flagged)) return FolderKind.starred;
    if (box.hasFlag(MailboxFlag.all) || box.isArchive) return FolderKind.all;
    return FolderKind.other;
  }

  String _folderName(Mailbox box, FolderKind kind) {
    switch (kind) {
      case FolderKind.inbox:
        return 'Inbox';
      case FolderKind.starred:
        return 'Starred';
      case FolderKind.sent:
        return 'Sent';
      case FolderKind.drafts:
        return 'Drafts';
      case FolderKind.all:
        return 'All Mail';
      case FolderKind.spam:
        return 'Spam';
      case FolderKind.trash:
        return 'Trash';
      case FolderKind.other:
        return box.name;
    }
  }

  int _order(FolderKind kind) {
    switch (kind) {
      case FolderKind.inbox:
        return 0;
      case FolderKind.starred:
        return 1;
      case FolderKind.sent:
        return 2;
      case FolderKind.drafts:
        return 3;
      case FolderKind.all:
        return 4;
      case FolderKind.spam:
        return 5;
      case FolderKind.trash:
        return 6;
      case FolderKind.other:
        return 7;
    }
  }

  MailSummary? _summaryOf(MimeMessage message) {
    final uid = message.uid;
    if (uid == null) {
      return null;
    }

    final envelope = message.envelope;
    final senders = envelope?.from;
    final MailAddress? sender =
        (senders != null && senders.isNotEmpty) ? senders.first : null;

    final rawSubject =
        (envelope?.subject ?? message.decodeSubject() ?? '').trim();

    var hasAttachment = false;
    try {
      hasAttachment = message.hasAttachments();
    } catch (_) {
      // The paperclip is optional.
    }

    return MailSummary(
      uid: uid,
      senderName: sender == null ? 'Unknown sender' : _nameOf(sender),
      senderEmail: sender?.email ?? '',
      subject: rawSubject.isEmpty ? '(no subject)' : rawSubject,
      date: envelope?.date ?? message.decodeDate(),
      isSeen: message.isSeen,
      isFlagged: message.isFlagged,
      hasAttachment: hasAttachment,
    );
  }

  String _nameOf(MailAddress address) {
    final name = address.personalName?.trim() ?? '';
    return name.isEmpty ? address.email : name;
  }

  String _labelOf(MailAddress address) {
    final name = address.personalName?.trim() ?? '';
    return name.isEmpty ? address.email : '$name <${address.email}>';
  }
}

/// Turns an HTML mail into readable plain text (no HTML is ever rendered).
String htmlToPlainText(String html) {
  var text = html
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>.*?</\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|tr|li|h[1-6])>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '');

  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
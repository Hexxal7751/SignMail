import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException, TlsException;
import 'dart:typed_data' show Uint8List;

import 'package:enough_mail/enough_mail.dart';

import 'gmail_auth_service.dart';

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
  });

  final int uid;
  final String senderName;
  final String senderEmail;
  final String subject;
  final DateTime? date;
  final bool isSeen;
  final bool isFlagged;

  /// The same message, shown as read.
  MailSummary asSeen() {
    return MailSummary(
      uid: uid,
      senderName: senderName,
      senderEmail: senderEmail,
      subject: subject,
      date: date,
      isSeen: true,
      isFlagged: isFlagged,
    );
  }

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

/// The downloaded content of one message.
class MailBody {
  const MailBody({
    required this.text,
    required this.toLine,
    required this.attachmentNames,
    required this.wasHtmlOnly,
    this.messageId,
    this.references,
    this.replyToEmail,
    this.toEmails = const <String>[],
    this.ccEmails = const <String>[],
  });

  final String text;
  final String toLine;
  final List<String> attachmentNames;

  /// True when the message had no plain-text version and was converted.
  final bool wasHtmlOnly;

  /// Header values needed to reply in the same conversation.
  final String? messageId;
  final String? references;
  final String? replyToEmail;
  final List<String> toEmails;
  final List<String> ccEmails;
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

/// Reads Gmail over IMAP using the signed-in Google account (XOAUTH2).
///
/// Each call opens a short-lived secure connection. A long-lived connection
/// for live updates comes with the sync work.
class MailService {
  MailService(this._auth, {this.background = false});

  final GmailAuthService _auth;

  /// True when running without a screen (background mail check).
  final bool background;

  static const String _host = 'imap.gmail.com';
  static const int _port = 993;
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 465;

  /// The newest [count] messages of the inbox, newest first.
  Future<List<MailSummary>> fetchInbox({int count = 40}) {
    return _withInbox<List<MailSummary>>((client, inbox) async {
      if (inbox.messagesExists == 0) {
        return const <MailSummary>[];
      }

      final result = await client.fetchRecentMessages(
        messageCount: count - 1,
        criteria: '(UID FLAGS ENVELOPE)',
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

  /// Downloads one message, and marks it as read when [markSeen] is set.
  Future<MailBody> fetchBody(int uid, {bool markSeen = true}) {
    return _withInbox<MailBody>((client, inbox) async {
      final result = await client.uidFetchMessage(
        uid,
        '(FLAGS BODY.PEEK[])',
      );

      if (result.messages.isEmpty) {
        throw const MailServiceException(
          'This message is no longer in your inbox.',
        );
      }

      final message = result.messages.first;
      final plain = (message.decodeTextPlainPart() ?? '').trim();
      final html = (message.decodeTextHtmlPart() ?? '').trim();

      var attachments = <String>[];
      try {
        attachments = message
            .findContentInfo()
            .map((info) => info.fileName ?? 'attachment')
            .toList();
      } catch (_) {
        // Attachment names are optional; the message can still be read.
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
        toLine: recipients.map(_labelOf).join(', '),
        attachmentNames: attachments,
        wasHtmlOnly: plain.isEmpty && html.isNotEmpty,
        messageId: message.getHeaderValue('message-id')?.trim(),
        references: message.getHeaderValue('references')?.trim(),
        replyToEmail: replyTo,
        toEmails: recipients.map((a) => a.email).toList(),
        ccEmails: copies.map((a) => a.email).toList(),
      );
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
    final client = SmtpClient('signmail.app');

    try {
      await client.connectToServer(_smtpHost, _smtpPort, isSecure: true);
      await client.ehlo();
      await client.authenticate(email, token, AuthMechanism.xoauth2);
      await client.sendMessage(message);
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

  /// Connects, signs in, opens the inbox, runs [action], then disconnects.
  Future<T> _withInbox<T>(
    Future<T> Function(ImapClient client, Mailbox inbox) action,
  ) async {
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
      final inbox = await client.selectInbox();
      return await action(client, inbox);
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

    return MailSummary(
      uid: uid,
      senderName: sender == null ? 'Unknown sender' : _nameOf(sender),
      senderEmail: sender?.email ?? '',
      subject: rawSubject.isEmpty ? '(no subject)' : rawSubject,
      date: envelope?.date ?? message.decodeDate(),
      isSeen: message.isSeen,
      isFlagged: message.isFlagged,
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
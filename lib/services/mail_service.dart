import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException, TlsException;

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
  });

  final String text;
  final String toLine;
  final List<String> attachmentNames;

  /// True when the message had no plain-text version and was converted.
  final bool wasHtmlOnly;
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
  MailService(this._auth);

  final GmailAuthService _auth;

  static const String _host = 'imap.gmail.com';
  static const int _port = 993;

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

  /// Downloads one message and marks it as read.
  Future<MailBody> fetchBody(int uid) {
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

      try {
        // Opening a message marks it as read, like other mail apps.
        await client.uidMarkSeen(MessageSequence.fromId(uid, isUid: true));
      } catch (_) {
        // Not critical; the message simply stays unread on the server.
      }

      final recipients = message.to ?? const <MailAddress>[];

      return MailBody(
        text: plain.isNotEmpty
            ? plain
            : (html.isNotEmpty ? htmlToPlainText(html) : ''),
        toLine: recipients.map(_labelOf).join(', '),
        attachmentNames: attachments,
        wasHtmlOnly: plain.isEmpty && html.isNotEmpty,
      );
    });
  }

  Future<String> _token() async {
    try {
      return await _auth.accessToken();
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
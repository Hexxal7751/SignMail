import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A file to attach to an outgoing message.
class MimeAttachmentData {
  const MimeAttachmentData({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

const List<String> _days = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = <String>[
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

String _randomToken(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ),
  );
}

/// Base64 text wrapped at 76 characters per line (CRLF).
String wrapBase64(List<int> bytes) {
  final text = base64.encode(bytes);
  final lines = <String>[
    for (var i = 0; i < text.length; i += 76)
      text.substring(i, i + 76 > text.length ? text.length : i + 76),
  ];
  return lines.join('\r\n');
}

bool _isPlainAscii(String text) {
  for (final unit in text.codeUnits) {
    if (unit < 32 || unit > 126) {
      return false;
    }
  }
  return true;
}

/// Encodes header text that has non-ASCII characters (RFC 2047).
String encodeHeaderText(String text) {
  if (_isPlainAscii(text)) {
    return text;
  }
  final words = <String>[];
  var chunk = <int>[];
  for (final rune in text.runes) {
    final bytes = utf8.encode(String.fromCharCode(rune));
    if (chunk.length + bytes.length > 42) {
      words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
      chunk = <int>[];
    }
    chunk.addAll(bytes);
  }
  if (chunk.isNotEmpty) {
    words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
  }
  return words.join('\r\n ');
}

String _addressHeader(String? name, String email) {
  final cleanName = (name ?? '').trim();
  if (cleanName.isEmpty) {
    return email;
  }
  if (_isPlainAscii(cleanName) && !RegExp(r'[()<>@,;:\\".\[\]]').hasMatch(cleanName)) {
    return '$cleanName <$email>';
  }
  if (_isPlainAscii(cleanName)) {
    final quoted = cleanName.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$quoted" <$email>';
  }
  return '${encodeHeaderText(cleanName)} <$email>';
}

String _httpDate(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_days[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} ${t.year} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)} +0000';
}

/// The headers of an outgoing message (without Bcc, which is never written).
String buildMessageHeaders({
  String? fromName,
  required String fromEmail,
  required List<String> to,
  List<String> cc = const <String>[],
  required String subject,
  String? inReplyTo,
  String? references,
  DateTime? date,
}) {
  final domain = fromEmail.contains('@') ? fromEmail.split('@').last : 'signmail';
  final lines = <String>[
    'From: ${_addressHeader(fromName, fromEmail)}',
    if (to.isNotEmpty) 'To: ${to.join(', ')}',
    if (cc.isNotEmpty) 'Cc: ${cc.join(', ')}',
    'Subject: ${encodeHeaderText(subject.replaceAll(RegExp(r'[\r\n]+'), ' '))}',
    'Date: ${_httpDate(date ?? DateTime.now())}',
    'Message-ID: <${_randomToken(24)}@$domain>',
    if (inReplyTo != null && inReplyTo.trim().isNotEmpty)
      'In-Reply-To: ${inReplyTo.trim()}',
    if (references != null && references.trim().isNotEmpty)
      'References: ${references.trim()}',
  ];
  return '${lines.join('\r\n')}\r\n';
}

String _asciiFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '_');
  return cleaned.isEmpty ? 'attachment' : cleaned;
}

String _fileNameParams(String name) {
  final ascii = _asciiFileName(name);
  if (ascii == name) {
    return 'filename="$ascii"';
  }
  final encoded = Uri.encodeComponent(name);
  return 'filename="$ascii"; filename*=UTF-8\'\'$encoded';
}

/// The body of a message as a MIME entity (headers + content), using CRLF.
///
/// Used both as the signed content and as the plain content of a message.
String buildContentEntity(String body, List<MimeAttachmentData> attachments) {
  final text = body
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .join('\r\n');

  // Plain 7-bit text is only used when it is safe for SMTP: no odd
  // characters, no very long lines and no line starting with a dot.
  final simple = !text.codeUnits.any((u) => u == 0 || u > 126) &&
      text
          .split('\r\n')
          .every((line) => line.length <= 900 && !line.startsWith('.'));

  final textPart = StringBuffer()
    ..write('Content-Type: text/plain; charset=utf-8\r\n')
    ..write('Content-Transfer-Encoding: ${simple ? '7bit' : 'base64'}\r\n')
    ..write('\r\n')
    ..write(simple ? text : wrapBase64(utf8.encode(text)));

  if (attachments.isEmpty) {
    return textPart.toString();
  }

  final boundary = '----=_SignMail_${_randomToken(20)}';
  final out = StringBuffer()
    ..write('Content-Type: multipart/mixed; boundary="$boundary"\r\n')
    ..write('\r\n')
    ..write('--$boundary\r\n')
    ..write(textPart)
    ..write('\r\n');

  for (final file in attachments) {
    out
      ..write('--$boundary\r\n')
      ..write('Content-Type: ${file.mimeType}; name="${_asciiFileName(file.name)}"\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n')
      ..write('Content-Disposition: attachment; ${_fileNameParams(file.name)}\r\n')
      ..write('\r\n')
      ..write(wrapBase64(file.bytes))
      ..write('\r\n');
  }
  out.write('--$boundary--');
  return out.toString();
}

/// A multipart/signed entity: [entity] plus its detached [cms] signature.
String buildSignedEntity(String entity, Uint8List cms, String micalg) {
  final boundary = '----=_SignMailSig_${_randomToken(20)}';
  return 'Content-Type: multipart/signed; protocol="application/pkcs7-signature"; '
      'micalg=$micalg; boundary="$boundary"\r\n'
      '\r\n'
      'This is an S/MIME signed message\r\n'
      '\r\n'
      '--$boundary\r\n'
      '$entity\r\n'
      '--$boundary\r\n'
      'Content-Type: application/pkcs7-signature; name="smime.p7s"\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      'Content-Disposition: attachment; filename="smime.p7s"\r\n'
      '\r\n'
      '${wrapBase64(cms)}\r\n'
      '--$boundary--';
}

/// An encrypted entity (application/pkcs7-mime) around [cms].
String buildEnvelopedEntity(Uint8List cms) {
  return 'Content-Type: application/pkcs7-mime; smime-type=enveloped-data; '
      'name="smime.p7m"\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      'Content-Disposition: attachment; filename="smime.p7m"\r\n'
      '\r\n'
      '${wrapBase64(cms)}';
}

/// Joins [headers] and a top-level [entity] into a full message.
String assembleMessage(String headers, String entity) {
  return '${headers}MIME-Version: 1.0\r\n$entity\r\n';
}
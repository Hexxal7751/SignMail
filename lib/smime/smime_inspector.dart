import 'dart:convert';
import 'dart:typed_data';

import 'asn1.dart';
import 'chain.dart';
import 'cms.dart';
import 'crypto_verify.dart';
import 'x509.dart';

/// How far a message's S/MIME signature can be trusted.
enum SmimeStatus {
  /// Signature is valid and the signer's identity is established.
  signedTrusted,

  /// Signature is valid, but the signer is not (yet) trusted.
  signedUnverified,

  /// The signature does not match: do not trust the message.
  signedInvalid,

  /// The message is encrypted for the recipient.
  encrypted,

  /// An S/MIME message SignMail cannot check.
  unsupported,
}

/// What SignMail found out about the S/MIME protection of one message.
class SmimeResult {
  SmimeResult({
    required this.status,
    required this.headline,
    this.details = const <String>[],
    this.signerName,
    this.signerEmail,
    this.certificate,
    this.chainNames = const <String>[],
    this.innerEntity,
    this.signingTime,
    this.hashName,
  });

  final SmimeStatus status;
  final String headline;

  /// Extra lines explaining the result.
  final List<String> details;

  final String? signerName;
  final String? signerEmail;
  final X509Certificate? certificate;
  final List<String> chainNames;

  /// For an opaque signature: the signed message (headers and body).
  final String? innerEntity;

  final DateTime? signingTime;
  final String? hashName;

  bool get isSigned =>
      status == SmimeStatus.signedTrusted ||
      status == SmimeStatus.signedUnverified ||
      status == SmimeStatus.signedInvalid;
}

class _Entity {
  _Entity(this.headers, this.body);

  final Map<String, String> headers;
  final String body;

  String? get contentType => headers['content-type'];

  String get mediaType =>
      (contentType ?? '').split(';').first.trim().toLowerCase();

  String? param(String name) => _params(contentType ?? '')[name.toLowerCase()];

  String get transferEncoding =>
      (headers['content-transfer-encoding'] ?? '').trim().toLowerCase();
}

Map<String, String> _params(String value) {
  final result = <String, String>{};
  final pieces = <String>[];
  var buffer = StringBuffer();
  var quoted = false;
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '"') {
      quoted = !quoted;
      buffer.write(ch);
    } else if (ch == ';' && !quoted) {
      pieces.add(buffer.toString());
      buffer = StringBuffer();
    } else {
      buffer.write(ch);
    }
  }
  pieces.add(buffer.toString());

  for (final piece in pieces.skip(1)) {
    final eq = piece.indexOf('=');
    if (eq < 0) {
      continue;
    }
    final key = piece.substring(0, eq).trim().toLowerCase();
    var val = piece.substring(eq + 1).trim();
    if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
      val = val.substring(1, val.length - 1);
    }
    result[key] = val;
  }
  return result;
}

_Entity _parseEntity(String text) {
  var split = text.indexOf('\r\n\r\n');
  var gap = 4;
  if (split < 0) {
    split = text.indexOf('\n\n');
    gap = 2;
  }
  final headerText = split < 0 ? text : text.substring(0, split);
  final body = split < 0 ? '' : text.substring(split + gap);

  final headers = <String, String>{};
  String? currentKey;
  for (final line in headerText.split(RegExp(r'\r?\n'))) {
    if (line.isEmpty) {
      continue;
    }
    if ((line.startsWith(' ') || line.startsWith('\t')) && currentKey != null) {
      headers[currentKey] = '${headers[currentKey]} ${line.trim()}';
      continue;
    }
    final colon = line.indexOf(':');
    if (colon > 0) {
      currentKey = line.substring(0, colon).trim().toLowerCase();
      headers.putIfAbsent(currentKey, () => line.substring(colon + 1).trim());
    }
  }
  return _Entity(headers, body);
}

List<String>? _splitParts(String body, String boundary) {
  final delim = '--$boundary';
  var pos = body.startsWith(delim) ? 0 : body.indexOf('\r\n$delim');
  if (pos < 0) {
    return null;
  }
  if (pos != 0) {
    pos += 2;
  }

  final parts = <String>[];
  while (true) {
    if (body.startsWith('$delim--', pos)) {
      break;
    }
    final lineEnd = body.indexOf('\r\n', pos);
    if (lineEnd < 0) {
      break;
    }
    final start = lineEnd + 2;
    final next = body.indexOf('\r\n$delim', start);
    if (next < 0) {
      break;
    }
    parts.add(body.substring(start, next));
    pos = next + 2;
  }
  return parts;
}

Uint8List _decodeTransfer(String body, String encoding) {
  if (encoding == 'base64') {
    return base64.decode(body.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), ''));
  }
  return Uint8List.fromList(latin1.encode(body));
}

/// Checks the S/MIME protection of a complete RFC 822 message.
///
/// Returns null when the message is not S/MIME. [fromEmail] is the sender
/// address the mail program shows, [trust] the accepted authorities.
SmimeResult? inspectSmime(
  Uint8List rawMessage, {
  required String fromEmail,
  required TrustStore trust,
  DateTime? messageDate,
  DateTime? now,
}) {
  final text = latin1.decode(rawMessage);
  final top = _parseEntity(text);
  final type = top.mediaType;

  final isSignedMultipart = type == 'multipart/signed';
  final isP7m = type == 'application/pkcs7-mime' ||
      type == 'application/x-pkcs7-mime';
  if (!isSignedMultipart && !isP7m) {
    return null;
  }

  try {
    if (isSignedMultipart) {
      final boundary = top.param('boundary');
      final parts = boundary == null ? null : _splitParts(top.body, boundary);
      if (parts == null || parts.length < 2) {
        return SmimeResult(
          status: SmimeStatus.unsupported,
          headline: 'Signed message could not be read',
          details: const ['The message structure is not valid.'],
        );
      }
      final signature = _parseEntity(parts[1]);
      final signatureType = signature.mediaType;
      if (signatureType != 'application/pkcs7-signature' &&
          signatureType != 'application/x-pkcs7-signature') {
        return SmimeResult(
          status: SmimeStatus.unsupported,
          headline: 'Unsupported signature format',
          details: [signatureType],
        );
      }
      final cms = _decodeTransfer(signature.body, signature.transferEncoding);
      final signedBytes = Uint8List.fromList(latin1.encode(parts[0]));
      final data = verifyCmsSignedData(cms, detachedContent: signedBytes);
      return _assess(
        data,
        fromEmail: fromEmail,
        trust: trust,
        messageDate: messageDate,
        now: now,
        innerEntity: null,
      );
    }

    // application/pkcs7-mime
    final cms = _decodeTransfer(top.body, top.transferEncoding);
    final info = Tlv.parse(cms).children;
    final contentOid = info.isEmpty ? '' : info[0].oid;

    if (contentOid == Oids.envelopedData) {
      return SmimeResult(
        status: SmimeStatus.encrypted,
        headline: 'Encrypted message',
        details: const [
          'This message is encrypted with S/MIME. Reading encrypted messages '
              'will be added in a later update.',
        ],
      );
    }

    if (contentOid != Oids.signedData) {
      return SmimeResult(
        status: SmimeStatus.unsupported,
        headline: 'Unsupported S/MIME message',
        details: [contentOid],
      );
    }

    final data = verifyCmsSignedData(cms);
    final inner = data.content == null ? null : latin1.decode(data.content!);
    return _assess(
      data,
      fromEmail: fromEmail,
      trust: trust,
      messageDate: messageDate,
      now: now,
      innerEntity: inner,
    );
  } on Asn1Exception catch (error) {
    return SmimeResult(
      status: SmimeStatus.unsupported,
      headline: 'Signature could not be read',
      details: [error.message],
    );
  } catch (error) {
    return SmimeResult(
      status: SmimeStatus.unsupported,
      headline: 'Signature could not be read',
      details: ['$error'],
    );
  }
}

SmimeResult _assess(
  CmsSignedData data, {
  required String fromEmail,
  required TrustStore trust,
  required DateTime? messageDate,
  required DateTime? now,
  required String? innerEntity,
}) {
  if (data.signers.isEmpty) {
    return SmimeResult(
      status: SmimeStatus.unsupported,
      headline: 'No signer found',
      innerEntity: innerEntity,
    );
  }

  final signer = data.signers.first;
  final cert = signer.certificate;
  final name = cert?.commonName;
  final email = cert != null && cert.emails.isNotEmpty ? cert.emails.first : null;

  if (!signer.signatureValid) {
    return SmimeResult(
      status: SmimeStatus.signedInvalid,
      headline: 'Signature is NOT valid',
      details: [
        signer.problem ?? 'The signature could not be verified.',
        'Do not trust this message.',
      ],
      signerName: name,
      signerEmail: email,
      certificate: cert,
      innerEntity: innerEntity,
      signingTime: signer.signingTime,
    );
  }

  if (cert == null) {
    return SmimeResult(
      status: SmimeStatus.unsupported,
      headline: 'Signer certificate missing',
      innerEntity: innerEntity,
    );
  }

  // The signature is mathematically correct; now decide how far to trust it.
  final problems = <String>[];
  final notes = <String>[];
  final moment = signer.signingTime ?? messageDate ?? now ?? DateTime.now();

  final wanted = fromEmail.trim().toLowerCase();
  final addressMatches = wanted.isNotEmpty && cert.emails.contains(wanted);
  if (!addressMatches) {
    problems.add(
      wanted.isEmpty
          ? 'The sender address is unknown.'
          : 'The certificate is not issued for the sender address ($wanted).',
    );
  }

  if (!cert.isValidAt(moment)) {
    problems.add(
      'The certificate was not valid when the message was signed '
      '(${_date(cert.notBefore)} to ${_date(cert.notAfter)}).',
    );
  }
  if (!cert.canSignMessages) {
    problems.add('The certificate is not meant for signing messages.');
  }
  if (!cert.allowsEmailProtection) {
    problems.add('The certificate is not meant for e-mail.');
  }

  final chain = buildChain(cert, data.certificates, trust, moment);
  if (!chain.trusted) {
    problems.add(
      chain.problem ?? 'The certificate does not lead to a trusted authority.',
    );
  } else if (chain.pinned) {
    notes.add('You chose to trust this certificate.');
  }

  final hash = signer.hashOid == null ? null : hashName(signer.hashOid!);
  if (hash == 'SHA-1' || hash == 'MD5') {
    problems.add('The signature uses the weak $hash algorithm.');
  }
  notes.add('Revocation status is not checked.');

  final good = problems.isEmpty;
  return SmimeResult(
    status: good ? SmimeStatus.signedTrusted : SmimeStatus.signedUnverified,
    headline: good
        ? 'Signed by ${name ?? email ?? 'the sender'}'
        : 'Signed, but not verified',
    details: <String>[...problems, ...notes],
    signerName: name,
    signerEmail: email,
    certificate: cert,
    chainNames: chain.path.map((c) => c.commonName).toList(),
    innerEntity: innerEntity,
    signingTime: signer.signingTime,
    hashName: hash,
  );
}

String _date(DateTime value) {
  final v = value.toLocal();
  return '${v.year}-${v.month.toString().padLeft(2, '0')}-'
      '${v.day.toString().padLeft(2, '0')}';
}
import 'dart:typed_data';

import 'asn1.dart';
import 'crypto_verify.dart';
import 'x509.dart';

/// The outcome of checking one signer of a CMS (S/MIME) signature.
class CmsSignerResult {
  CmsSignerResult({
    required this.certificate,
    required this.signatureValid,
    required this.hashOid,
    this.signingTime,
    this.problem,
  });

  /// The signer's certificate, or null if it was not included.
  final X509Certificate? certificate;

  /// True only when the signature really matches the content.
  final bool signatureValid;

  final String? hashOid;
  final DateTime? signingTime;

  /// Why the check failed (for display), or null.
  final String? problem;
}

/// A parsed and checked CMS SignedData structure.
class CmsSignedData {
  CmsSignedData({
    required this.signers,
    required this.certificates,
    required this.content,
  });

  final List<CmsSignerResult> signers;

  /// Every certificate carried in the signature.
  final List<X509Certificate> certificates;

  /// The signed content for an opaque signature, otherwise null.
  final Uint8List? content;
}

/// Reads a CMS SignedData and checks every signature.
///
/// For a detached signature pass the signed bytes as [detachedContent]; for
/// an opaque signature leave it null and the embedded content is used.
CmsSignedData verifyCmsSignedData(
  Uint8List cms, {
  Uint8List? detachedContent,
}) {
  final contentInfo = Tlv.parse(cms);
  final ciParts = contentInfo.children;
  if (ciParts.length < 2 || ciParts[0].oid != Oids.signedData) {
    throw const Asn1Exception('not a SignedData structure');
  }

  final signedData = ciParts[1].child(0);
  final fields = signedData.children;
  // version, digestAlgorithms, encapContentInfo, [certs], [crls], signerInfos
  if (fields.length < 4) {
    throw const Asn1Exception('SignedData is incomplete');
  }

  final encap = fields[2].children;
  final contentType = encap[0].oid;
  Uint8List? embedded;
  if (encap.length > 1 && encap[1].tag == 0xA0) {
    embedded = encap[1].child(0).octets;
  }

  final certs = <X509Certificate>[];
  Tlv? signerInfosNode;
  for (final field in fields.skip(3)) {
    if (field.tag == 0xA0) {
      for (final item in field.children) {
        if (item.tag == Tlv.tagSequence) {
          try {
            certs.add(X509Certificate.fromDer(Uint8List.fromList(item.encoded)));
          } catch (_) {
            // A certificate we cannot read is simply not used.
          }
        }
      }
    } else if (field.tag == Tlv.tagSet) {
      signerInfosNode = field;
    }
  }

  if (signerInfosNode == null) {
    throw const Asn1Exception('no signer information');
  }

  final content = detachedContent ?? embedded;
  if (content == null) {
    throw const Asn1Exception('the signed content is missing');
  }

  final results = <CmsSignerResult>[];
  for (final info in signerInfosNode.children) {
    results.add(_checkSigner(info, certs, content, contentType));
  }

  return CmsSignedData(
    signers: results,
    certificates: certs,
    content: detachedContent == null ? embedded : null,
  );
}

CmsSignerResult _checkSigner(
  Tlv info,
  List<X509Certificate> certs,
  Uint8List content,
  String contentType,
) {
  final parts = info.children;
  if (parts.length < 5) {
    return CmsSignerResult(
      certificate: null,
      signatureValid: false,
      hashOid: null,
      problem: 'The signer information is incomplete.',
    );
  }

  final sid = parts[1];
  final digestAlgorithmOid = parts[2].child(0).oid;

  Tlv? signedAttrs;
  var next = 3;
  if (parts[next].tag == 0xA0) {
    signedAttrs = parts[next];
    next++;
  }
  final signatureAlgorithmOid = parts[next].child(0).oid;
  final signature = Uint8List.fromList(parts[next + 1].octets);

  // Find the signer's certificate.
  X509Certificate? signer;
  if (sid.tag == Tlv.tagSequence) {
    final issuer = sid.child(0).encoded;
    final serial = sid.child(1).integer;
    for (final cert in certs) {
      if (cert.serial == serial && sameBytes(cert.issuerDer, issuer)) {
        signer = cert;
        break;
      }
    }
  } else if (sid.tag == 0x80) {
    final keyId = sid.value;
    for (final cert in certs) {
      final id = cert.subjectKeyId;
      if (id != null && sameBytes(id, keyId)) {
        signer = cert;
        break;
      }
    }
  }

  if (signer == null) {
    return CmsSignerResult(
      certificate: null,
      signatureValid: false,
      hashOid: digestAlgorithmOid,
      problem: 'The signer\'s certificate is not included in the message.',
    );
  }

  final scheme = signatureSchemeFor(signatureAlgorithmOid);
  if (scheme == null || scheme.pss) {
    return CmsSignerResult(
      certificate: signer,
      signatureValid: false,
      hashOid: digestAlgorithmOid,
      problem: 'This signature type is not supported yet.',
    );
  }

  final hashOid = scheme.hashOid ?? digestAlgorithmOid;
  final contentHash = hashBytes(digestAlgorithmOid, content);
  if (contentHash == null) {
    return CmsSignerResult(
      certificate: signer,
      signatureValid: false,
      hashOid: digestAlgorithmOid,
      problem: 'The hash algorithm is not supported.',
    );
  }

  DateTime? signingTime;
  Uint8List toBeVerified;

  if (signedAttrs != null) {
    Uint8List? messageDigest;
    String? attrContentType;
    for (final attr in signedAttrs.children) {
      final attrParts = attr.children;
      final oid = attrParts[0].oid;
      final values = attrParts[1].children;
      if (values.isEmpty) {
        continue;
      }
      if (oid == Oids.attrMessageDigest) {
        messageDigest = Uint8List.fromList(values[0].octets);
      } else if (oid == Oids.attrContentType) {
        attrContentType = values[0].oid;
      } else if (oid == Oids.attrSigningTime) {
        try {
          signingTime = values[0].time;
        } catch (_) {
          signingTime = null;
        }
      }
    }

    if (messageDigest == null || !sameBytes(messageDigest, contentHash)) {
      return CmsSignerResult(
        certificate: signer,
        signatureValid: false,
        hashOid: digestAlgorithmOid,
        signingTime: signingTime,
        problem: 'The message content does not match its signature. It may '
            'have been changed after signing.',
      );
    }
    if (attrContentType != null && attrContentType != contentType) {
      return CmsSignerResult(
        certificate: signer,
        signatureValid: false,
        hashOid: digestAlgorithmOid,
        signingTime: signingTime,
        problem: 'The signed content type is inconsistent.',
      );
    }

    // The signature covers the attributes re-tagged as a SET.
    toBeVerified = Uint8List.fromList(signedAttrs.encoded);
    toBeVerified[0] = Tlv.tagSet;
  } else {
    toBeVerified = content;
  }

  final key = signer.publicKey;
  if (key == null) {
    return CmsSignerResult(
      certificate: signer,
      signatureValid: false,
      hashOid: digestAlgorithmOid,
      signingTime: signingTime,
      problem: 'The signer\'s key type is not supported yet.',
    );
  }

  final ok = verifySignatureBytes(
    publicKey: key,
    hashOid: hashOid,
    message: toBeVerified,
    signature: signature,
  );

  return CmsSignerResult(
    certificate: signer,
    signatureValid: ok,
    hashOid: hashOid,
    signingTime: signingTime,
    problem: ok
        ? null
        : 'The signature does not match. The message may have been changed.',
  );
}
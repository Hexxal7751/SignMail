import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'asn1.dart';

/// Object identifiers used for hashes and signatures.
class Oids {
  const Oids._();

  static const String md5 = '1.2.840.113549.2.5';
  static const String sha1 = '1.3.14.3.2.26';
  static const String sha224 = '2.16.840.1.101.3.4.2.4';
  static const String sha256 = '2.16.840.1.101.3.4.2.1';
  static const String sha384 = '2.16.840.1.101.3.4.2.2';
  static const String sha512 = '2.16.840.1.101.3.4.2.3';

  static const String rsaEncryption = '1.2.840.113549.1.1.1';
  static const String rsaPss = '1.2.840.113549.1.1.10';
  static const String ecPublicKey = '1.2.840.10045.2.1';

  static const String signedData = '1.2.840.113549.1.7.2';
  static const String envelopedData = '1.2.840.113549.1.7.3';
  static const String data = '1.2.840.113549.1.7.1';

  static const String attrContentType = '1.2.840.113549.1.9.3';
  static const String attrMessageDigest = '1.2.840.113549.1.9.4';
  static const String attrSigningTime = '1.2.840.113549.1.9.5';
}

/// How a signature algorithm identifier maps to a hash and key type.
class SignatureScheme {
  const SignatureScheme(this.hashOid, {required this.ec, this.pss = false});

  /// Hash algorithm, or null when the signature algorithm does not say.
  final String? hashOid;
  final bool ec;
  final bool pss;
}

const Map<String, SignatureScheme> _schemes = <String, SignatureScheme>{
  '1.2.840.113549.1.1.1': SignatureScheme(null, ec: false),
  '1.2.840.113549.1.1.4': SignatureScheme(Oids.md5, ec: false),
  '1.2.840.113549.1.1.5': SignatureScheme(Oids.sha1, ec: false),
  '1.2.840.113549.1.1.14': SignatureScheme(Oids.sha224, ec: false),
  '1.2.840.113549.1.1.11': SignatureScheme(Oids.sha256, ec: false),
  '1.2.840.113549.1.1.12': SignatureScheme(Oids.sha384, ec: false),
  '1.2.840.113549.1.1.13': SignatureScheme(Oids.sha512, ec: false),
  '1.2.840.113549.1.1.10': SignatureScheme(null, ec: false, pss: true),
  '1.2.840.10045.4.1': SignatureScheme(Oids.sha1, ec: true),
  '1.2.840.10045.4.3.1': SignatureScheme(Oids.sha224, ec: true),
  '1.2.840.10045.4.3.2': SignatureScheme(Oids.sha256, ec: true),
  '1.2.840.10045.4.3.3': SignatureScheme(Oids.sha384, ec: true),
  '1.2.840.10045.4.3.4': SignatureScheme(Oids.sha512, ec: true),
};

SignatureScheme? signatureSchemeFor(String oid) => _schemes[oid];

/// A readable name for a hash OID.
String hashName(String oid) {
  switch (oid) {
    case Oids.md5:
      return 'MD5';
    case Oids.sha1:
      return 'SHA-1';
    case Oids.sha224:
      return 'SHA-224';
    case Oids.sha256:
      return 'SHA-256';
    case Oids.sha384:
      return 'SHA-384';
    case Oids.sha512:
      return 'SHA-512';
  }
  return oid;
}

Digest? digestFor(String hashOid) {
  switch (hashOid) {
    case Oids.md5:
      return MD5Digest();
    case Oids.sha1:
      return SHA1Digest();
    case Oids.sha224:
      return SHA224Digest();
    case Oids.sha256:
      return SHA256Digest();
    case Oids.sha384:
      return SHA384Digest();
    case Oids.sha512:
      return SHA512Digest();
  }
  return null;
}

/// The hash of [data], or null for an unsupported algorithm.
Uint8List? hashBytes(String hashOid, Uint8List data) {
  final digest = digestFor(hashOid);
  return digest?.process(data);
}

const Map<String, String> _rsaDigestIds = <String, String>{
  Oids.md5: '06082a864886f70d0205',
  Oids.sha1: '06052b0e03021a',
  Oids.sha224: '0609608648016503040204',
  Oids.sha256: '0609608648016503040201',
  Oids.sha384: '0609608648016503040202',
  Oids.sha512: '0609608648016503040203',
};

/// Checks [signature] over [message] with [publicKey].
///
/// [publicKey] is an [RSAPublicKey] or an [ECPublicKey]. Any malformed input
/// simply counts as "does not verify".
bool verifySignatureBytes({
  required Object publicKey,
  required String hashOid,
  required Uint8List message,
  required Uint8List signature,
}) {
  try {
    final digest = digestFor(hashOid);
    if (digest == null) {
      return false;
    }

    if (publicKey is RSAPublicKey) {
      final id = _rsaDigestIds[hashOid];
      if (id == null) {
        return false;
      }
      final signer = RSASigner(digest, id)
        ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      return signer.verifySignature(message, RSASignature(signature));
    }

    if (publicKey is ECPublicKey) {
      final seq = Tlv.parse(signature);
      final parts = seq.children;
      if (parts.length != 2) {
        return false;
      }
      final signer = ECDSASigner(digest)
        ..init(false, PublicKeyParameter<ECPublicKey>(publicKey));
      return signer.verifySignature(
        message,
        ECSignature(parts[0].integer, parts[1].integer),
      );
    }
  } catch (_) {
    return false;
  }
  return false;
}
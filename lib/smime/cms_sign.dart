import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'crypto_verify.dart';
import 'der_writer.dart';
import 'x509.dart';

/// A problem while creating S/MIME data.
class CmsException implements Exception {
  const CmsException(this.message);

  final String message;

  @override
  String toString() => message;
}

SecureRandom secureRandom() {
  final random = Random.secure();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => random.nextInt(256)),
  );
  return FortunaRandom()..seed(KeyParameter(seed));
}

const Map<String, String> _ecdsaOidByHash = <String, String>{
  Oids.sha1: '1.2.840.10045.4.1',
  Oids.sha224: '1.2.840.10045.4.3.1',
  Oids.sha256: '1.2.840.10045.4.3.2',
  Oids.sha384: '1.2.840.10045.4.3.3',
  Oids.sha512: '1.2.840.10045.4.3.4',
};

const String _aes256Cbc = '2.16.840.1.101.3.4.1.42';
const String _aes128Cbc = '2.16.840.1.101.3.4.1.2';
const String _des3Cbc = '1.2.840.113549.3.7';
const String _oidSmimeCapabilities = '1.2.840.113549.1.9.15';

Uint8List _sign(Object privateKey, String hashOid, Uint8List message) {
  final digest = digestFor(hashOid)!;

  if (privateKey is RSAPrivateKey) {
    final id = <String, String>{
      Oids.sha1: '06052b0e03021a',
      Oids.sha256: '0609608648016503040201',
      Oids.sha384: '0609608648016503040202',
      Oids.sha512: '0609608648016503040203',
    }[hashOid];
    if (id == null) {
      throw const CmsException('This hash algorithm cannot be used to sign.');
    }
    final signer = RSASigner(digest, id)
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return signer.generateSignature(message).bytes;
  }

  if (privateKey is ECPrivateKey) {
    final signer = ECDSASigner(digest)
      ..init(
        true,
        ParametersWithRandom<PrivateKeyParameter<ECPrivateKey>>(
          PrivateKeyParameter<ECPrivateKey>(privateKey),
          secureRandom(),
        ),
      );
    final sig = signer.generateSignature(message) as ECSignature;
    return derSequence([derInteger(sig.r), derInteger(sig.s)]);
  }

  throw const CmsException('This private key type cannot be used to sign.');
}

/// Creates a CMS SignedData (S/MIME signature) over [content].
///
/// With [detached] the content is not embedded (used for multipart/signed).
Uint8List createSignedData({
  required Uint8List content,
  required X509Certificate signer,
  required Object privateKey,
  List<X509Certificate> chain = const <X509Certificate>[],
  String hashOid = Oids.sha256,
  bool detached = true,
  DateTime? signingTime,
}) {
  final contentHash = hashBytes(hashOid, content);
  if (contentHash == null) {
    throw const CmsException('This hash algorithm is not supported.');
  }

  final attributes = <Uint8List>[
    derSequence([
      derOid(Oids.attrContentType),
      derSetOf([derOid(Oids.data)]),
    ]),
    derSequence([
      derOid(Oids.attrSigningTime),
      derSetOf([derUtcTime(signingTime ?? DateTime.now())]),
    ]),
    derSequence([
      derOid(Oids.attrMessageDigest),
      derSetOf([derOctetString(contentHash)]),
    ]),
    derSequence([
      derOid(_oidSmimeCapabilities),
      derSetOf([
        derSequence([
          derAlgorithm(_aes256Cbc, withNull: false),
          derAlgorithm(_aes128Cbc, withNull: false),
          derAlgorithm(_des3Cbc, withNull: false),
        ]),
      ]),
    ]),
  ];

  // The signature covers the attributes as a SET; they are stored as [0].
  final attributeSet = derSetOf(attributes);
  final signature = _sign(privateKey, hashOid, attributeSet);

  // Re-use the sorted encoding with the context tag for the SignerInfo.
  final attributesImplicit = Uint8List.fromList(attributeSet)..[0] = 0xA0;

  final String signatureAlgorithm;
  if (privateKey is ECPrivateKey) {
    signatureAlgorithm = _ecdsaOidByHash[hashOid]!;
  } else {
    signatureAlgorithm = Oids.rsaEncryption;
  }

  final signerInfo = derSequence([
    derInt(1),
    derSequence([signer.issuerDer, derInteger(signer.serial)]),
    derAlgorithm(hashOid),
    attributesImplicit,
    derAlgorithm(signatureAlgorithm, withNull: privateKey is! ECPrivateKey),
    derOctetString(signature),
  ]);

  final certificates = <X509Certificate>[signer, ...chain];
  final seen = <String>{};
  final certDers = <Uint8List>[
    for (final cert in certificates)
      if (seen.add(cert.fingerprint)) cert.der,
  ];

  final encapsulated = derSequence([
    derOid(Oids.data),
    if (!detached) derContext(0, derOctetString(content)),
  ]);

  final signedData = derSequence([
    derInt(1),
    derSetOf([derAlgorithm(hashOid)]),
    encapsulated,
    derContext(0, certDers.expand((d) => d).toList()),
    derSetOf([signerInfo]),
  ]);

  return derSequence([
    derOid(Oids.signedData),
    derContext(0, signedData),
  ]);
}

/// The micalg value for the Content-Type of a multipart/signed message.
String micalgFor(String hashOid) {
  switch (hashOid) {
    case Oids.sha1:
      return 'sha-1';
    case Oids.sha384:
      return 'sha-384';
    case Oids.sha512:
      return 'sha-512';
    default:
      return 'sha-256';
  }
}
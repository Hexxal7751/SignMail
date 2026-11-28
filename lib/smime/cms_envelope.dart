import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'asn1.dart';
import 'cms_sign.dart';
import 'crypto_verify.dart';
import 'der_writer.dart';
import 'x509.dart';

const String _aes128Cbc = '2.16.840.1.101.3.4.1.2';
const String _aes192Cbc = '2.16.840.1.101.3.4.1.22';
const String _aes256Cbc = '2.16.840.1.101.3.4.1.42';
const String _des3Cbc = '1.2.840.113549.3.7';
const String _rsaesOaep = '1.2.840.113549.1.1.7';

PaddedBlockCipherImpl _cbcCipher(
  BlockCipher engine,
  Uint8List key,
  Uint8List iv,
  bool encrypt,
) {
  return PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(engine))
    ..init(
      encrypt,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
}

/// Encrypts [content] for every certificate in [recipients] (RSA keys).
///
/// The result is a CMS EnvelopedData (AES-256-CBC, RSA key transport).
Uint8List encryptEnvelopedData(
  Uint8List content,
  List<X509Certificate> recipients,
) {
  if (recipients.isEmpty) {
    throw const CmsException('There is no recipient to encrypt for.');
  }

  final random = secureRandom();
  final cek = random.nextBytes(32);
  final iv = random.nextBytes(16);

  final encrypted = _cbcCipher(AESEngine(), cek, iv, true).process(content);

  final infos = <Uint8List>[];
  final seen = <String>{};
  for (final cert in recipients) {
    if (!seen.add(cert.fingerprint)) {
      continue;
    }
    final key = cert.publicKey;
    if (key is! RSAPublicKey) {
      throw CmsException(
        '${cert.commonName} uses a key type that cannot be used for '
        'encryption yet.',
      );
    }
    if (!cert.allowsEmailProtection) {
      throw CmsException('${cert.commonName}\'s certificate is not meant '
          'for e-mail.');
    }

    final rsa = PKCS1Encoding(RSAEngine())
      ..init(
        true,
        ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
          PublicKeyParameter<RSAPublicKey>(key),
          random,
        ),
      );
    final wrapped = rsa.process(cek);

    infos.add(
      derSequence([
        derInt(0),
        derSequence([cert.issuerDer, derInteger(cert.serial)]),
        derAlgorithm(Oids.rsaEncryption),
        derOctetString(wrapped),
      ]),
    );
  }

  final encryptedContentInfo = derSequence([
    derOid(Oids.data),
    derSequence([derOid(_aes256Cbc), derOctetString(iv)]),
    derTlv(0x80, encrypted),
  ]);

  final envelopedData = derSequence([
    derInt(0),
    derSetOf(infos),
    encryptedContentInfo,
  ]);

  return derSequence([
    derOid(Oids.envelopedData),
    derContext(0, envelopedData),
  ]);
}

/// Opens a CMS EnvelopedData with our [privateKey] and returns the content.
Uint8List decryptEnvelopedData(
  Uint8List cms, {
  required X509Certificate certificate,
  required Object privateKey,
}) {
  if (privateKey is! RSAPrivateKey) {
    throw const CmsException(
      'Decrypting with this key type is not supported yet.',
    );
  }

  final contentInfo = Tlv.parse(cms).children;
  if (contentInfo.length < 2 || contentInfo[0].oid != Oids.envelopedData) {
    throw const CmsException('This is not an encrypted message.');
  }

  final fields = contentInfo[1].child(0).children;
  // version, [originatorInfo], recipientInfos, encryptedContentInfo, ...
  var index = 1;
  if (fields[index].tag == 0xA0) {
    index++;
  }
  final recipientInfos = fields[index].children;
  final eci = fields[index + 1].children;

  final algorithm = eci[1].children;
  final algorithmOid = algorithm[0].oid;
  final iv = Uint8List.fromList(algorithm[1].octets);
  final encryptedContent = Uint8List.fromList(eci[2].octets);

  // Collect the recipient entries that use RSA key transport.
  final mine = <Tlv>[];
  final others = <Tlv>[];
  for (final info in recipientInfos) {
    if (info.tag != Tlv.tagSequence) {
      continue; // key agreement and other types are not supported
    }
    final parts = info.children;
    final rid = parts[1];
    var matches = false;
    if (rid.tag == Tlv.tagSequence) {
      matches = sameBytes(rid.child(0).encoded, certificate.issuerDer) &&
          rid.child(1).integer == certificate.serial;
    } else if (rid.tag == 0x80) {
      final ski = certificate.subjectKeyId;
      matches = ski != null && sameBytes(ski, rid.value);
    }
    (matches ? mine : others).add(info);
  }

  Uint8List? cek;
  for (final info in <Tlv>[...mine, ...others]) {
    cek = _unwrapKey(info, privateKey);
    if (cek != null) {
      break;
    }
  }
  if (cek == null) {
    throw const CmsException(
      'This message was not encrypted for your certificate.',
    );
  }

  final BlockCipher engine;
  final int keyLength;
  switch (algorithmOid) {
    case _aes128Cbc:
      engine = AESEngine();
      keyLength = 16;
    case _aes192Cbc:
      engine = AESEngine();
      keyLength = 24;
    case _aes256Cbc:
      engine = AESEngine();
      keyLength = 32;
    case _des3Cbc:
      engine = DESedeEngine();
      keyLength = 24;
    default:
      throw const CmsException('This encryption method is not supported yet.');
  }
  if (cek.length != keyLength) {
    throw const CmsException('The message key has an unexpected size.');
  }

  try {
    return _cbcCipher(engine, cek, iv, false).process(encryptedContent);
  } catch (_) {
    throw const CmsException('The encrypted message is damaged.');
  }
}

Uint8List? _unwrapKey(Tlv info, RSAPrivateKey privateKey) {
  try {
    final parts = info.children;
    final keyAlgorithm = parts[2].children;
    final oid = keyAlgorithm[0].oid;
    final wrapped = Uint8List.fromList(parts[3].octets);

    AsymmetricBlockCipher cipher;
    if (oid == _rsaesOaep) {
      var hashOid = Oids.sha1;
      if (keyAlgorithm.length > 1) {
        for (final field in keyAlgorithm[1].children) {
          if (field.tag == 0xA0) {
            hashOid = field.child(0).child(0).oid;
          }
        }
      }
      switch (hashOid) {
        case Oids.sha1:
          cipher = OAEPEncoding(RSAEngine());
        case Oids.sha256:
          cipher = OAEPEncoding.withSHA256(RSAEngine());
        case Oids.sha512:
          cipher = OAEPEncoding.withSHA512(RSAEngine());
        default:
          return null;
      }
    } else if (oid == Oids.rsaEncryption) {
      cipher = PKCS1Encoding(RSAEngine());
    } else {
      return null;
    }

    cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return cipher.process(wrapped);
  } catch (_) {
    return null;
  }
}
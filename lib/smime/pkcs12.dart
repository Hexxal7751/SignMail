import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'asn1.dart';
import 'crypto_verify.dart';
import 'x509.dart';

/// A problem while opening a PKCS#12 (.p12 / .pfx) file.
class Pkcs12Exception implements Exception {
  const Pkcs12Exception(this.message, {this.wrongPassword = false});

  final String message;

  /// True when the most likely cause is a wrong password.
  final bool wrongPassword;

  @override
  String toString() => message;
}

/// The content of a PKCS#12 file: the person's certificate, the private key
/// and any other certificates (issuers) that were included.
class Pkcs12Result {
  Pkcs12Result({
    required this.certificate,
    required this.chain,
    required this.privateKey,
  });

  final X509Certificate certificate;
  final List<X509Certificate> chain;

  /// An [RSAPrivateKey] or an [ECPrivateKey].
  final Object privateKey;
}

const String _oidData = '1.2.840.113549.1.7.1';
const String _oidEncryptedData = '1.2.840.113549.1.7.6';
const String _oidKeyBag = '1.2.840.113549.1.12.10.1.1';
const String _oidShroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
const String _oidCertBag = '1.2.840.113549.1.12.10.1.3';
const String _oidLocalKeyId = '1.2.840.113549.1.9.21';
const String _oidPbes2 = '1.2.840.113549.1.5.13';
const String _oidPbkdf2 = '1.2.840.113549.1.5.12';

class _Bag {
  _Bag(this.data, this.localKeyId);

  final Uint8List data;
  final Uint8List? localKeyId;
}

/// Opens [bytes] with [password].
Pkcs12Result parsePkcs12(Uint8List bytes, String password) {
  try {
    return _parse(bytes, password);
  } on Pkcs12Exception {
    rethrow;
  } on Asn1Exception catch (error) {
    throw Pkcs12Exception('This does not look like a valid .p12 file '
        '(${error.message}).');
  } catch (error) {
    throw Pkcs12Exception('The certificate file could not be read: $error');
  }
}

Pkcs12Result _parse(Uint8List bytes, String password) {
  final pfx = Tlv.parse(bytes).children;
  if (pfx.length < 2) {
    throw const Pkcs12Exception('The file is not a PKCS#12 certificate file.');
  }

  final authSafe = pfx[1].children;
  if (authSafe[0].oid != _oidData) {
    throw const Pkcs12Exception('Password-protected containers of this type '
        'are not supported.');
  }
  final authSafeBytes = Uint8List.fromList(authSafe[1].child(0).octets);

  if (pfx.length > 2) {
    _checkMac(pfx[2], authSafeBytes, password);
  }

  final keys = <_Bag>[];
  final certs = <_Bag>[];

  for (final info in Tlv.parse(authSafeBytes).children) {
    final parts = info.children;
    final type = parts[0].oid;
    Uint8List safeContents;

    if (type == _oidData) {
      safeContents = Uint8List.fromList(parts[1].child(0).octets);
    } else if (type == _oidEncryptedData) {
      final eci = parts[1].child(0).child(1).children;
      final encrypted = Uint8List.fromList(eci[2].octets);
      safeContents = _decryptPbe(eci[1], encrypted, password);
    } else {
      continue;
    }

    for (final bag in Tlv.parse(safeContents).children) {
      final bagParts = bag.children;
      final bagId = bagParts[0].oid;
      final value = bagParts[1].child(0);

      Uint8List? localKeyId;
      if (bagParts.length > 2) {
        for (final attr in bagParts[2].children) {
          final attrParts = attr.children;
          if (attrParts[0].oid == _oidLocalKeyId) {
            localKeyId =
                Uint8List.fromList(attrParts[1].child(0).octets);
          }
        }
      }

      if (bagId == _oidKeyBag) {
        keys.add(_Bag(Uint8List.fromList(value.encoded), localKeyId));
      } else if (bagId == _oidShroudedKeyBag) {
        final valueParts = value.children;
        final plain = _decryptPbe(
          valueParts[0],
          Uint8List.fromList(valueParts[1].octets),
          password,
        );
        keys.add(_Bag(plain, localKeyId));
      } else if (bagId == _oidCertBag) {
        final der = Uint8List.fromList(value.child(1).child(0).octets);
        certs.add(_Bag(der, localKeyId));
      }
    }
  }

  if (keys.isEmpty) {
    throw const Pkcs12Exception('The file contains no private key.');
  }
  if (certs.isEmpty) {
    throw const Pkcs12Exception('The file contains no certificate.');
  }

  final key = keys.first;
  final privateKey = _readPrivateKey(key.data);

  final parsed = <X509Certificate>[];
  final ids = <Uint8List?>[];
  for (final bag in certs) {
    try {
      parsed.add(X509Certificate.fromDer(bag.data));
      ids.add(bag.localKeyId);
    } catch (_) {
      // Skip certificates that cannot be read.
    }
  }
  if (parsed.isEmpty) {
    throw const Pkcs12Exception('The certificates in the file are not readable.');
  }

  var ownIndex = -1;
  final keyId = key.localKeyId;
  if (keyId != null) {
    for (var i = 0; i < parsed.length; i++) {
      final id = ids[i];
      if (id != null && sameBytes(id, keyId)) {
        ownIndex = i;
        break;
      }
    }
  }
  if (ownIndex < 0) {
    for (var i = 0; i < parsed.length; i++) {
      if (_keyMatches(privateKey, parsed[i])) {
        ownIndex = i;
        break;
      }
    }
  }
  if (ownIndex < 0) {
    throw const Pkcs12Exception(
      'No certificate in the file matches the private key.',
    );
  }

  final own = parsed[ownIndex];
  final others = <X509Certificate>[
    for (var i = 0; i < parsed.length; i++)
      if (i != ownIndex) parsed[i],
  ];

  return Pkcs12Result(certificate: own, chain: others, privateKey: privateKey);
}

bool _keyMatches(Object privateKey, X509Certificate cert) {
  final pub = cert.publicKey;
  if (privateKey is RSAPrivateKey && pub is RSAPublicKey) {
    return privateKey.modulus == pub.modulus;
  }
  if (privateKey is ECPrivateKey && pub is ECPublicKey) {
    final d = privateKey.d;
    final domain = privateKey.parameters;
    if (d == null || domain == null || pub.Q == null) {
      return false;
    }
    final q = domain.G * d;
    return q != null && q == pub.Q;
  }
  return false;
}

// --- private key -----------------------------------------------------------

Object _readPrivateKey(Uint8List pkcs8) {
  final info = Tlv.parse(pkcs8).children;
  final algorithm = info[1].children;
  final oid = algorithm[0].oid;
  final inner = Tlv.parse(Uint8List.fromList(info[2].octets));

  if (oid == Oids.rsaEncryption) {
    final f = inner.children;
    // version, n, e, d, p, q, ...
    return RSAPrivateKey(f[1].integer, f[3].integer, f[4].integer, f[5].integer);
  }

  if (oid == Oids.ecPublicKey) {
    final curveOid = algorithm.length > 1 && algorithm[1].tag == Tlv.tagOid
        ? algorithm[1].oid
        : null;
    final ECDomainParameters domain;
    switch (curveOid) {
      case '1.2.840.10045.3.1.7':
        domain = ECCurve_secp256r1();
      case '1.3.132.0.34':
        domain = ECCurve_secp384r1();
      case '1.3.132.0.35':
        domain = ECCurve_secp521r1();
      default:
        throw const Pkcs12Exception('This elliptic curve is not supported.');
    }
    final d = bytesToBigInt(inner.child(1).octets);
    return ECPrivateKey(d, domain);
  }

  throw const Pkcs12Exception('This private key type is not supported.');
}

// --- password based encryption --------------------------------------------

Uint8List _bmpPassword(String password) {
  final units = password.codeUnits;
  final out = Uint8List(units.length * 2 + 2);
  for (var i = 0; i < units.length; i++) {
    out[i * 2] = units[i] >> 8;
    out[i * 2 + 1] = units[i] & 0xFF;
  }
  return out;
}

Uint8List _decryptPbe(Tlv algorithm, Uint8List data, String password) {
  final parts = algorithm.children;
  final oid = parts[0].oid;
  final params = parts[1];

  try {
    if (oid == _oidPbes2) {
      return _decryptPbes2(params, data, password);
    }
    return _decryptLegacy(oid, params, data, password);
  } on Pkcs12Exception {
    rethrow;
  } catch (_) {
    throw const Pkcs12Exception(
      'The password is wrong, or the file uses an unsupported protection.',
      wrongPassword: true,
    );
  }
}

Uint8List _cbc(
  BlockCipher engine,
  Uint8List key,
  Uint8List iv,
  Uint8List data, {
  int? rc2Bits,
}) {
  final CipherParameters keyParams =
      rc2Bits == null ? KeyParameter(key) : RC2Parameters(key, bits: rc2Bits);
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(engine))
    ..init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<CipherParameters>, Null>(
        ParametersWithIV<CipherParameters>(keyParams, iv),
        null,
      ),
    );
  return cipher.process(data);
}

Uint8List _decryptPbes2(Tlv params, Uint8List data, String password) {
  final p = params.children;
  final kdf = p[0].children;
  if (kdf[0].oid != _oidPbkdf2) {
    throw const Pkcs12Exception('This key derivation is not supported.');
  }
  final kp = kdf[1].children;
  final salt = Uint8List.fromList(kp[0].octets);
  final iterations = kp[1].integer.toInt();
  int? keyLength;
  var prf = '1.2.840.113549.2.7'; // hmacWithSHA1
  for (final extra in kp.skip(2)) {
    if (extra.tag == Tlv.tagInteger) {
      keyLength = extra.integer.toInt();
    } else if (extra.tag == Tlv.tagSequence) {
      prf = extra.child(0).oid;
    }
  }

  final scheme = p[1].children;
  final schemeOid = scheme[0].oid;
  final iv = Uint8List.fromList(scheme[1].octets);

  final Digest digest;
  final int block;
  switch (prf) {
    case '1.2.840.113549.2.7':
      digest = SHA1Digest();
      block = 64;
    case '1.2.840.113549.2.8':
      digest = SHA224Digest();
      block = 64;
    case '1.2.840.113549.2.9':
      digest = SHA256Digest();
      block = 64;
    case '1.2.840.113549.2.10':
      digest = SHA384Digest();
      block = 128;
    case '1.2.840.113549.2.11':
      digest = SHA512Digest();
      block = 128;
    default:
      throw const Pkcs12Exception('This key derivation hash is not supported.');
  }

  final BlockCipher engine;
  int size;
  switch (schemeOid) {
    case '2.16.840.1.101.3.4.1.2':
      engine = AESEngine();
      size = 16;
    case '2.16.840.1.101.3.4.1.22':
      engine = AESEngine();
      size = 24;
    case '2.16.840.1.101.3.4.1.42':
      engine = AESEngine();
      size = 32;
    case '1.2.840.113549.3.7':
      engine = DESedeEngine();
      size = 24;
    default:
      throw const Pkcs12Exception('This encryption is not supported.');
  }
  size = keyLength ?? size;

  final kdfEngine = PBKDF2KeyDerivator(HMac(digest, block))
    ..init(Pbkdf2Parameters(salt, iterations, size));
  final key = kdfEngine.process(Uint8List.fromList(utf8.encode(password)));

  return _cbc(engine, key, iv, data);
}

Uint8List _decryptLegacy(
  String oid,
  Tlv params,
  Uint8List data,
  String password,
) {
  final p = params.children;
  final salt = Uint8List.fromList(p[0].octets);
  final iterations = p[1].integer.toInt();

  final int keyBytes;
  final bool rc2;
  final int rc2Bits;
  switch (oid) {
    case '1.2.840.113549.1.12.1.3': // 3-key 3DES
      keyBytes = 24;
      rc2 = false;
      rc2Bits = 0;
    case '1.2.840.113549.1.12.1.4': // 2-key 3DES
      keyBytes = 16;
      rc2 = false;
      rc2Bits = 0;
    case '1.2.840.113549.1.12.1.5': // RC2-128
      keyBytes = 16;
      rc2 = true;
      rc2Bits = 128;
    case '1.2.840.113549.1.12.1.6': // RC2-40
      keyBytes = 5;
      rc2 = true;
      rc2Bits = 40;
    default:
      throw const Pkcs12Exception('This encryption is not supported.');
  }

  final generator = PKCS12ParametersGenerator(SHA1Digest())
    ..init(_bmpPassword(password), salt, iterations);
  final derived = generator.generateDerivedParametersWithIV(keyBytes, 8);
  final key = (derived.parameters as KeyParameter).key;

  return _cbc(
    rc2 ? RC2Engine() : DESedeEngine(),
    key,
    derived.iv,
    data,
    rc2Bits: rc2 ? rc2Bits : null,
  );
}

void _checkMac(Tlv macData, Uint8List content, String password) {
  final parts = macData.children;
  final digestInfo = parts[0].children;
  final hashOid = digestInfo[0].child(0).oid;
  final expected = digestInfo[1].octets;
  final salt = Uint8List.fromList(parts[1].octets);
  final iterations = parts.length > 2 ? parts[2].integer.toInt() : 1;

  final Digest digest;
  final int block;
  switch (hashOid) {
    case Oids.sha1:
      digest = SHA1Digest();
      block = 64;
    case Oids.sha224:
      digest = SHA224Digest();
      block = 64;
    case Oids.sha256:
      digest = SHA256Digest();
      block = 64;
    case Oids.sha384:
      digest = SHA384Digest();
      block = 128;
    case Oids.sha512:
      digest = SHA512Digest();
      block = 128;
    default:
      return; // unknown MAC type: the decryption check still protects us
  }

  Uint8List compute(Uint8List passwordBytes) {
    final generator = PKCS12ParametersGenerator(digest)
      ..init(passwordBytes, salt, iterations);
    final key = generator.generateDerivedMacParameters(digest.digestSize).key;
    final mac = HMac(digest, block)..init(KeyParameter(key));
    return mac.process(content);
  }

  var ok = sameBytes(compute(_bmpPassword(password)), expected);
  if (!ok && password.isEmpty) {
    ok = sameBytes(compute(Uint8List(0)), expected);
  }
  if (!ok) {
    throw const Pkcs12Exception(
      'The password is wrong, or the file is damaged.',
      wrongPassword: true,
    );
  }
}
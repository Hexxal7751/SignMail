import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'asn1.dart';
import 'crypto_verify.dart';

const Map<String, String> _nameLabels = <String, String>{
  '2.5.4.3': 'CN',
  '2.5.4.4': 'SN',
  '2.5.4.5': 'serialNumber',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '2.5.4.42': 'GN',
  '1.2.840.113549.1.9.1': 'emailAddress',
};

/// A readable summary of an X.509 certificate (only what SignMail needs).
class X509Certificate {
  X509Certificate._({
    required this.der,
    required this.tbsBytes,
    required this.serial,
    required this.signatureAlgorithmOid,
    required this.signature,
    required this.issuerDer,
    required this.subjectDer,
    required this.issuerName,
    required this.subjectName,
    required this.commonName,
    required this.notBefore,
    required this.notAfter,
    required this.emails,
    required this.keyAlgorithmOid,
    required this.keyParameterOid,
    required this.publicKeyBytes,
    required this.spkiDer,
    required this.keyUsageBits,
    required this.extendedKeyUsages,
    required this.isCa,
    required this.subjectKeyId,
    required this.authorityKeyId,
  });

  final Uint8List der;
  final Uint8List tbsBytes;
  final BigInt serial;
  final String signatureAlgorithmOid;
  final Uint8List signature;
  final Uint8List issuerDer;
  final Uint8List subjectDer;
  final String issuerName;
  final String subjectName;
  final String commonName;
  final DateTime notBefore;
  final DateTime notAfter;

  /// Addresses the certificate is issued for (lower-case).
  final List<String> emails;

  final String keyAlgorithmOid;
  final String? keyParameterOid;
  final Uint8List publicKeyBytes;
  final Uint8List spkiDer;

  /// Raw key-usage bits, or null when the extension is absent.
  final Uint8List? keyUsageBits;

  /// Extended key usages (OIDs); empty when the extension is absent.
  final List<String> extendedKeyUsages;

  /// True/false from basic constraints, or null when absent.
  final bool? isCa;

  final Uint8List? subjectKeyId;
  final Uint8List? authorityKeyId;

  static const String _emailProtection = '1.3.6.1.5.5.7.3.4';
  static const String _anyExtendedKeyUsage = '2.5.29.37.0';

  /// Reads one certificate. Throws [Asn1Exception] when it is malformed.
  factory X509Certificate.fromDer(Uint8List der) {
    final cert = Tlv.parse(der);
    final top = cert.children;
    if (top.length < 3) {
      throw const Asn1Exception('certificate is incomplete');
    }

    final tbs = top[0];
    final fields = tbs.children;
    var i = 0;
    if (fields[i].tag == 0xA0) {
      i++; // version
    }
    final serial = fields[i++].integer;
    i++; // signature algorithm inside the TBS part
    final issuer = fields[i++];
    final validity = fields[i++];
    final subject = fields[i++];
    final spki = fields[i++];

    final validityParts = validity.children;
    final spkiParts = spki.children;
    final keyAlgorithm = spkiParts[0].children;

    final emails = <String>{};
    Uint8List? keyUsage;
    final ekus = <String>[];
    bool? isCa;
    Uint8List? ski;
    Uint8List? aki;

    for (final field in fields.skip(i)) {
      if (field.tag != 0xA3) {
        continue;
      }
      for (final ext in field.child(0).children) {
        final parts = ext.children;
        final extOid = parts[0].oid;
        final valueNode = parts.last; // OCTET STRING (critical flag skipped)
        final inner = Tlv.parse(valueNode.octets);

        switch (extOid) {
          case '2.5.29.17': // subjectAltName
            for (final name in inner.children) {
              if (name.tag == 0x81) {
                emails.add(latin1.decode(name.value).toLowerCase());
              }
            }
          case '2.5.29.15': // keyUsage
            keyUsage = inner.bitStringBytes;
          case '2.5.29.37': // extendedKeyUsage
            for (final usage in inner.children) {
              ekus.add(usage.oid);
            }
          case '2.5.29.19': // basicConstraints
            isCa = false;
            for (final part in inner.children) {
              if (part.tag == 0x01) {
                isCa = part.value.isNotEmpty && part.value[0] != 0;
              }
            }
          case '2.5.29.14': // subjectKeyIdentifier
            ski = inner.octets;
          case '2.5.29.35': // authorityKeyIdentifier
            for (final part in inner.children) {
              if (part.tag == 0x80) {
                aki = Uint8List.fromList(part.value);
              }
            }
        }
      }
    }

    final subjectName = _nameToString(subject, emails);

    return X509Certificate._(
      der: der,
      tbsBytes: tbs.encoded,
      serial: serial,
      signatureAlgorithmOid: top[1].child(0).oid,
      signature: top[2].bitStringBytes,
      issuerDer: issuer.encoded,
      subjectDer: subject.encoded,
      issuerName: _nameToString(issuer, null),
      subjectName: subjectName,
      commonName: _firstValue(subject, '2.5.4.3') ?? subjectName,
      notBefore: validityParts[0].time,
      notAfter: validityParts[1].time,
      emails: emails.toList(),
      keyAlgorithmOid: keyAlgorithm[0].oid,
      keyParameterOid: keyAlgorithm.length > 1 && keyAlgorithm[1].tag == 0x06
          ? keyAlgorithm[1].oid
          : null,
      publicKeyBytes: spkiParts[1].bitStringBytes,
      spkiDer: spki.encoded,
      keyUsageBits: keyUsage,
      extendedKeyUsages: ekus,
      isCa: isCa,
      subjectKeyId: ski,
      authorityKeyId: aki,
    );
  }

  /// Reads every certificate of a PEM text.
  static List<X509Certificate> fromPem(String pem) {
    final result = <X509Certificate>[];
    final pattern = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    );
    for (final match in pattern.allMatches(pem)) {
      try {
        final body = match.group(1)!.replaceAll(RegExp(r'\s'), '');
        result.add(X509Certificate.fromDer(base64.decode(body)));
      } catch (_) {
        // Skip entries that cannot be read.
      }
    }
    return result;
  }

  static String _nameToString(Tlv name, Set<String>? emailSink) {
    final parts = <String>[];
    for (final rdn in name.children) {
      for (final atv in rdn.children) {
        final parts2 = atv.children;
        final oid = parts2[0].oid;
        final value = parts2[1].text;
        if (oid == '1.2.840.113549.1.9.1') {
          emailSink?.add(value.toLowerCase());
        }
        parts.add('${_nameLabels[oid] ?? oid}=$value');
      }
    }
    return parts.join(', ');
  }

  static String? _firstValue(Tlv name, String wantedOid) {
    for (final rdn in name.children) {
      for (final atv in rdn.children) {
        final parts = atv.children;
        if (parts[0].oid == wantedOid) {
          return parts[1].text;
        }
      }
    }
    return null;
  }

  /// SHA-256 fingerprint as lower-case hex.
  String get fingerprint => toHex(SHA256Digest().process(der));

  /// "AB:CD:…" style fingerprint for display.
  String get fingerprintDisplay {
    final hex = fingerprint.toUpperCase();
    final pairs = <String>[
      for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
    ];
    return pairs.join(':');
  }

  bool get isSelfSigned => sameBytes(issuerDer, subjectDer);

  bool isValidAt(DateTime moment) {
    final utc = moment.toUtc();
    return !utc.isBefore(notBefore) && !utc.isAfter(notAfter);
  }

  bool _hasBit(int bit) {
    final bits = keyUsageBits;
    if (bits == null) {
      return true;
    }
    final index = bit ~/ 8;
    if (index >= bits.length) {
      return false;
    }
    return (bits[index] & (0x80 >> (bit % 8))) != 0;
  }

  /// Allowed to sign data (digital signature or non-repudiation).
  bool get canSignMessages => _hasBit(0) || _hasBit(1);

  /// Allowed to sign other certificates.
  bool get canSignCertificates => keyUsageBits == null || _hasBit(5);

  /// Allowed for e-mail protection (or no restriction given).
  bool get allowsEmailProtection =>
      extendedKeyUsages.isEmpty ||
      extendedKeyUsages.contains(_emailProtection) ||
      extendedKeyUsages.contains(_anyExtendedKeyUsage);

  /// The public key as a pointycastle key, or null when unsupported.
  Object? get publicKey {
    try {
      if (keyAlgorithmOid == Oids.rsaEncryption) {
        final seq = Tlv.parse(publicKeyBytes).children;
        return RSAPublicKey(seq[0].integer, seq[1].integer);
      }
      if (keyAlgorithmOid == Oids.ecPublicKey) {
        final ECDomainParameters? domain;
        switch (keyParameterOid) {
          case '1.2.840.10045.3.1.7':
            domain = ECCurve_secp256r1();
          case '1.3.132.0.34':
            domain = ECCurve_secp384r1();
          case '1.3.132.0.35':
            domain = ECCurve_secp521r1();
          default:
            domain = null;
        }
        if (domain == null) {
          return null;
        }
        final point = domain.curve.decodePoint(publicKeyBytes);
        return point == null ? null : ECPublicKey(point, domain);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// True when [child] was signed by this certificate's key.
  bool didSign(X509Certificate child) {
    final scheme = signatureSchemeFor(child.signatureAlgorithmOid);
    final key = publicKey;
    if (scheme == null || scheme.pss || scheme.hashOid == null || key == null) {
      return false;
    }
    return verifySignatureBytes(
      publicKey: key,
      hashOid: scheme.hashOid!,
      message: child.tbsBytes,
      signature: child.signature,
    );
  }

  /// True when the certificate's signature algorithm can be checked here.
  bool get hasCheckableSignature {
    final scheme = signatureSchemeFor(signatureAlgorithmOid);
    return scheme != null && !scheme.pss && scheme.hashOid != null;
  }
}
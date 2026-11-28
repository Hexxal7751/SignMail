import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../services/local_store.dart';
import 'pkcs12.dart';
import 'x509.dart';

/// The user's own S/MIME certificate with its private key, opened.
class SmimeIdentity {
  const SmimeIdentity({
    required this.certificate,
    required this.chain,
    required this.privateKey,
  });

  final X509Certificate certificate;
  final List<X509Certificate> chain;
  final Object privateKey;
}

/// What can be shown about the stored certificate without opening it.
class IdentityInfo {
  const IdentityInfo({
    required this.name,
    required this.issuer,
    required this.emails,
    required this.notBefore,
    required this.notAfter,
    required this.fingerprint,
    this.remembered = false,
  });

  factory IdentityInfo.fromCertificate(
    X509Certificate certificate, {
    bool remembered = false,
  }) {
    return IdentityInfo(
      name: certificate.commonName,
      issuer: certificate.issuerName,
      emails: certificate.emails,
      notBefore: certificate.notBefore,
      notAfter: certificate.notAfter,
      fingerprint: certificate.fingerprintDisplay,
      remembered: remembered,
    );
  }

  factory IdentityInfo.fromJson(Map<String, dynamic> json) {
    return IdentityInfo(
      name: '${json['name']}',
      issuer: '${json['issuer']}',
      emails: <String>[
        for (final e in (json['emails'] as List<dynamic>? ?? <dynamic>[]))
          '$e',
      ],
      notBefore: DateTime.parse('${json['notBefore']}'),
      notAfter: DateTime.parse('${json['notAfter']}'),
      fingerprint: '${json['fingerprint']}',
      remembered: json['remembered'] == true,
    );
  }

  final String name;
  final String issuer;
  final List<String> emails;
  final DateTime notBefore;
  final DateTime notAfter;
  final String fingerprint;

  /// True when the password is kept in the system's secure storage.
  final bool remembered;

  bool get isExpired => DateTime.now().toUtc().isAfter(notAfter);

  IdentityInfo withRemembered(bool value) => IdentityInfo(
        name: name,
        issuer: issuer,
        emails: emails,
        notBefore: notBefore,
        notAfter: notAfter,
        fingerprint: fingerprint,
        remembered: value,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'issuer': issuer,
        'emails': emails,
        'notBefore': notBefore.toIso8601String(),
        'notAfter': notAfter.toIso8601String(),
        'fingerprint': fingerprint,
        'remembered': remembered,
      };
}

/// Keeps the user's .p12 certificate on this device and opens it on request.
///
/// The file stays password-protected on disk. The opened key only exists in
/// memory until the app closes (or [lock] is called).
class IdentityVault {
  IdentityVault._();

  static final IdentityVault instance = IdentityVault._();

  static const String _fileName = 'smime_identity.p12';
  static const String _infoKey = 'signmail.smime.identity.info';
  static const String _passwordKey = 'signmail.smime.identity.password';
  static const LocalStore _store = LocalStore();
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  SmimeIdentity? _unlocked;
  bool _autoTried = false;

  SmimeIdentity? get unlocked => _unlocked;
  bool get isUnlocked => _unlocked != null;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<IdentityInfo?> info() async {
    final raw = await _store.read(key: _infoKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return IdentityInfo.fromJson(json);
      }
    } catch (_) {
      // Fall through.
    }
    return null;
  }

  Future<void> _writeInfo(IdentityInfo info) {
    return _store.write(key: _infoKey, value: jsonEncode(info.toJson()));
  }

  Future<bool> _rememberPassword(String? password) async {
    try {
      if (password == null) {
        await _secure.delete(key: _passwordKey);
        return false;
      }
      await _secure.write(key: _passwordKey, value: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks the file and its password, then stores it for later use.
  Future<IdentityInfo> importP12(
    Uint8List bytes,
    String password, {
    bool remember = false,
  }) async {
    final result = parsePkcs12(bytes, password); // throws Pkcs12Exception

    final file = await _file();
    await file.writeAsBytes(bytes, flush: true);

    final saved = await _rememberPassword(remember ? password : null);
    final info = IdentityInfo.fromCertificate(
      result.certificate,
      remembered: saved,
    );
    await _writeInfo(info);

    _unlocked = SmimeIdentity(
      certificate: result.certificate,
      chain: result.chain,
      privateKey: result.privateKey,
    );
    return info;
  }

  /// Opens the stored certificate with [password].
  Future<SmimeIdentity> unlock(String password, {bool remember = false}) async {
    final existing = _unlocked;
    if (existing != null) {
      return existing;
    }

    final file = await _file();
    if (!await file.exists()) {
      throw const Pkcs12Exception('No certificate has been imported yet.');
    }

    final result = parsePkcs12(await file.readAsBytes(), password);
    final identity = SmimeIdentity(
      certificate: result.certificate,
      chain: result.chain,
      privateKey: result.privateKey,
    );
    _unlocked = identity;

    if (remember) {
      final saved = await _rememberPassword(password);
      final current = await info();
      if (current != null) {
        await _writeInfo(current.withRemembered(saved));
      }
    }
    return identity;
  }

  /// Opens the certificate with the remembered password, if there is one.
  Future<void> tryAutoUnlock() async {
    if (_unlocked != null || _autoTried) {
      return;
    }
    _autoTried = true;
    try {
      final password = await _secure.read(key: _passwordKey);
      if (password != null && password.isNotEmpty) {
        await unlock(password);
      }
    } catch (_) {
      // The user is asked for the password instead.
    }
  }

  /// Forgets the opened key (the file stays stored).
  void lock() {
    _unlocked = null;
  }

  /// Removes the certificate, its file and any remembered password.
  Future<void> remove() async {
    _unlocked = null;
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Nothing else to do.
    }
    await _store.delete(key: _infoKey);
    await _rememberPassword(null);
  }
}

/// The stored certificate's description (null when none is imported).
final identityInfoProvider = FutureProvider<IdentityInfo?>(
  (ref) => IdentityVault.instance.info(),
);
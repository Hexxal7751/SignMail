import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../services/local_store.dart';
import 'chain.dart';
import 'x509.dart';

/// Supplies the certificates SignMail trusts: the public authorities from the
/// bundled list, plus certificates the user chose to trust.
class TrustService {
  TrustService._();

  static final TrustService instance = TrustService._();

  static const String _rootsAsset = 'assets/roots/cacert.pem';
  static const String _pinKey = 'signmail.smime.pinned';
  static const LocalStore _store = LocalStore();

  List<X509Certificate>? _roots;

  Future<List<X509Certificate>> _loadRoots() async {
    final cached = _roots;
    if (cached != null) {
      return cached;
    }
    try {
      final pem = await rootBundle.loadString(_rootsAsset);
      _roots = X509Certificate.fromPem(pem);
    } catch (_) {
      _roots = <X509Certificate>[];
    }
    return _roots!;
  }

  /// SHA-256 fingerprints of the certificates the user trusts.
  Future<Set<String>> pinnedFingerprints() async {
    final raw = await _store.read(key: _pinKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // Fall through to an empty list.
    }
    return <String>{};
  }

  /// Trust this exact certificate from now on.
  Future<void> pin(String fingerprint) async {
    final pinned = await pinnedFingerprints();
    pinned.add(fingerprint);
    await _store.write(key: _pinKey, value: jsonEncode(pinned.toList()));
  }

  /// Stop trusting a certificate that was trusted before.
  Future<void> unpin(String fingerprint) async {
    final pinned = await pinnedFingerprints();
    pinned.remove(fingerprint);
    await _store.write(key: _pinKey, value: jsonEncode(pinned.toList()));
  }

  Future<TrustStore> load() async {
    return TrustStore(
      roots: await _loadRoots(),
      pinnedFingerprints: await pinnedFingerprints(),
    );
  }
}
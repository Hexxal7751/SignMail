import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store.dart';
import 'x509.dart';

/// Other people's certificates, needed to encrypt messages for them.
///
/// SignMail saves a certificate when a message with a valid signature from
/// that person's own address is opened, or when the user adds a file.
class ContactCerts {
  ContactCerts._();

  static final ContactCerts instance = ContactCerts._();

  static const String _key = 'signmail.smime.contacts';
  static const LocalStore _store = LocalStore();

  Future<Map<String, String>> _load() async {
    final raw = await _store.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, String>{
          for (final entry in decoded.entries)
            if (entry.value is String) '${entry.key}': entry.value as String,
        };
      }
    } catch (_) {
      // Fall through to an empty list.
    }
    return <String, String>{};
  }

  Future<void> _save(Map<String, String> data) {
    return _store.write(key: _key, value: jsonEncode(data));
  }

  /// Every known certificate by e-mail address.
  Future<Map<String, X509Certificate>> all() async {
    final data = await _load();
    final result = <String, X509Certificate>{};
    for (final entry in data.entries) {
      try {
        result[entry.key] = X509Certificate.fromDer(base64.decode(entry.value));
      } catch (_) {
        // Skip entries that cannot be read.
      }
    }
    return result;
  }

  Future<X509Certificate?> forEmail(String email) async {
    final data = await _load();
    final value = data[email.trim().toLowerCase()];
    if (value == null) {
      return null;
    }
    try {
      return X509Certificate.fromDer(base64.decode(value));
    } catch (_) {
      return null;
    }
  }

  /// Remembers [certificate] for its addresses (or just [onlyFor]).
  Future<void> save(X509Certificate certificate, {String? onlyFor}) async {
    final addresses = onlyFor != null
        ? <String>[onlyFor.trim().toLowerCase()]
        : certificate.emails;
    if (addresses.isEmpty) {
      return;
    }

    final data = await _load();
    final encoded = base64.encode(certificate.der);
    var changed = false;

    for (final address in addresses) {
      if (data[address] == encoded) {
        continue;
      }
      // A newer valid certificate replaces an older one.
      if (data.containsKey(address) && !certificate.isValidAt(DateTime.now())) {
        continue;
      }
      data[address] = encoded;
      changed = true;
    }

    if (changed) {
      await _save(data);
    }
  }

  Future<void> remove(String email) async {
    final data = await _load();
    if (data.remove(email.trim().toLowerCase()) != null) {
      await _save(data);
    }
  }
}

/// All saved people's certificates.
final contactCertsProvider = FutureProvider<Map<String, X509Certificate>>(
  (ref) => ContactCerts.instance.all(),
);
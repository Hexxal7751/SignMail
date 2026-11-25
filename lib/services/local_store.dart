import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key/value storage for non-secret app data (account email, settings,
/// sync state). Unlike secure storage, it survives app updates reliably.
///
/// Values that older versions saved in secure storage are copied over the
/// first time they are read.
class LocalStore {
  const LocalStore();

  static const FlutterSecureStorage _legacy = FlutterSecureStorage();

  Future<String?> read({required String key}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Background isolates need a fresh view of what the app saved.
      await prefs.reload();
      final value = prefs.getString(key);
      if (value != null) {
        return value;
      }
    } catch (_) {
      // Fall through to the legacy store.
    }

    try {
      final old = await _legacy.read(key: key);
      if (old != null) {
        await write(key: key, value: old);
        return old;
      }
    } catch (_) {
      // Legacy storage can be unreadable; nothing to migrate then.
    }
    return null;
  }

  Future<void> write({required String key, required String value}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // Not critical; the value still applies for this session.
    }
  }

  Future<void> delete({required String key}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // Ignore.
    }
    try {
      await _legacy.delete(key: key);
    } catch (_) {
      // Ignore.
    }
  }
}
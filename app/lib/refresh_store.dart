import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Refresh credentials belong in Android Keystore-backed storage / iOS Keychain,
/// never in ordinary preferences or device backups. Access tokens stay in memory.
class RefreshStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'refresh_token';

  static Future<String?> read() async {
    final secure = await _storage.read(key: _key);
    final prefs = await SharedPreferences.getInstance();
    if (secure != null) {
      await prefs.remove(_key);
      return secure;
    }
    final legacy = prefs.getString(_key);
    if (legacy == null) return null;
    // Remove the legacy copy only after the secure write succeeds. A failed
    // migration must never silently destroy the user's existing session.
    await write(legacy);
    return legacy;
  }

  static Future<void> write(String value) async {
    await _storage.write(key: _key, value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> clear() async {
    // Clear the legacy copy first so it cannot resurrect a signed-out session.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await _storage.delete(key: _key);
  }
}

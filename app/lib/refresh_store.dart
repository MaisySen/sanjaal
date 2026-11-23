import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Refresh credentials belong in Android Keystore-backed storage / iOS Keychain,
/// never in ordinary preferences or device backups. Access tokens stay in memory.
class RefreshStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'refresh_token';
  static const _callKey = 'native_call_login_lease_v1';
  static final _uuid = RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');

  /// Metadata only, but kept with credentials so backups/preferences cannot
  /// resurrect an old login's native actions. Call only after verified /auth/me,
  /// under Session's serialized credential queue. Refresh rotation keeps it;
  /// every successful replacement grant invalidates it before writing tokens.
  static Future<String?> callLease(String owner) async {
    if (!_uuid.hasMatch(owner)) return null;
    final raw = await _storage.read(key: _callKey);
    if (raw != null) {
      try {
        final value = jsonDecode(raw);
        if (value is Map && value['owner'] == owner && value['lease'] is String &&
            _uuid.hasMatch(value['lease'] as String)) {
          return value['lease'] as String;
        }
      } catch (_) { /* Invalid metadata never grants native action authority. */ }
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final lease = '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
    await _storage.write(key: _callKey, value: jsonEncode({'owner': owner, 'lease': lease}));
    return lease;
  }

  static Future<void> clearCallLease() => _storage.delete(key: _callKey);

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
    await clearCallLease();
  }
}

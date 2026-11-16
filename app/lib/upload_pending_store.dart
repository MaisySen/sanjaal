import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A durable uncertainty marker, not a persisted media job. No media, caption,
/// token or recipient is stored here. Reopening never starts a request.
class UploadPendingStore {
  const UploadPendingStore();
  static const _storage = FlutterSecureStorage();
  static String _key(String owner) => 'upload_pending_v1_${sha256.convert(utf8.encode(owner))}';
  Future<Map<String, dynamic>?> read(String owner) async {
    final raw = await _storage.read(key: _key(owner));
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map || value['version'] != 1 || value['id'] is! String || !RegExp(r'^[0-9a-f]{48}$').hasMatch(value['id']) || !['post','reel','story'].contains(value['kind'])) throw const FormatException('Unrecognized upload marker');
    return value.cast<String, dynamic>();
  }
  Future<void> write(String owner, String id, String kind) async {
    await _storage.write(key: _key(owner), value: jsonEncode({'version':1,'id':id,'kind':kind}));
    final saved = await read(owner);
    if (saved?['id'] != id || saved?['kind'] != kind) throw StateError('Upload marker read-back failed');
  }
  Future<void> clear(String owner) async {
    await _storage.delete(key: _key(owner));
    if (await _storage.read(key: _key(owner)) != null) throw StateError('Upload marker clear read-back failed');
  }
}

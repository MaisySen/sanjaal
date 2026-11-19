import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A durable uncertainty marker, not a persisted media job. No media, caption,
/// token or recipient is stored here. Reopening never starts a request.
class UploadPendingStore {
  const UploadPendingStore();
  static const _storage = FlutterSecureStorage();
  static final Map<String, Future<void>> _tails = {};
  static String _key(String owner) {
    if (owner.isEmpty || owner.length > 256) throw ArgumentError('Account required');
    return 'upload_pending_v1_${sha256.convert(utf8.encode(owner))}';
  }
  Future<T> _serial<T>(String owner, Future<T> Function() action) async {
    final key = _key(owner);
    final before = _tails[key] ?? Future<void>.value();
    final done = (() async { await before; return action(); })();
    final tail = done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    try { return await done; }
    finally { if (identical(_tails[key], tail)) _tails.remove(key); }
  }
  static void _validate(String id, String kind) {
    if (!RegExp(r'^[0-9a-f]{48}$').hasMatch(id) || !['post','reel','story'].contains(kind)) {
      throw const FormatException('Unrecognized upload marker');
    }
  }
  Future<Map<String, dynamic>?> read(String owner) async {
    final raw = await _storage.read(key: _key(owner));
    if (raw == null) return null;
    if (raw.length > 2048) throw const FormatException('Upload marker exceeds its bound');
    final value = jsonDecode(raw);
    if (value is! Map || value['version'] != 1 || value['id'] is! String || !RegExp(r'^[0-9a-f]{48}$').hasMatch(value['id']) || !['post','reel','story'].contains(value['kind'])) throw const FormatException('Unrecognized upload marker');
    return value.cast<String, dynamic>();
  }
  Future<void> write(String owner, String id, String kind) => _serial(owner, () async {
    _validate(id, kind);
    final existing = await read(owner);
    if (existing != null && (existing['id'] != id || existing['kind'] != kind)) {
      throw StateError('Another upload safety marker must be checked first.');
    }
    await _storage.write(key: _key(owner), value: jsonEncode({'version':1,'id':id,'kind':kind}));
    final saved = await read(owner);
    if (saved?['id'] != id || saved?['kind'] != kind) throw StateError('Upload marker read-back failed');
  });
  Future<void> clear(String owner, {required String? expectedId}) => _serial(owner, () async {
    final existing = await read(owner);
    if (existing == null) return;
    if (existing['id'] != expectedId) {
      throw StateError('Upload safety info changed. Reopen it before clearing.');
    }
    await _storage.delete(key: _key(owner));
    if (await _storage.read(key: _key(owner)) != null) throw StateError('Upload marker clear read-back failed');
  });
}

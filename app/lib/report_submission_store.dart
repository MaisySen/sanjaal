import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// At most eight explicitly sent, unresolved report intents per account.
/// No credentials, content snapshots, background sends or automatic retries.
class ReportSubmissionStore {
  const ReportSubmissionStore();
  static const _storage = FlutterSecureStorage();
  static final Map<String, Future<void>> _tails = {};
  String _key(String owner) {
    if (owner.isEmpty || owner.length > 256) {
      throw ArgumentError('Account required');
    }
    return 'report_submissions_v1_${sha256.convert(utf8.encode(owner))}';
  }

  String _payload(String type, String target, String reason) {
    if (!const ['post', 'user', 'comment'].contains(type) ||
        target.trim().isEmpty ||
        target.runes.length > 40 ||
        !const [
          'spam',
          'abuse',
          'nudity',
          'violence',
          'scam',
          'other',
        ].contains(reason)) {
      throw const FormatException('Invalid report submission');
    }
    return jsonEncode([type, target, reason]);
  }

  Future<Map<String, String>> _read(String owner) async {
    final raw = await _storage.read(key: _key(owner));
    if (raw == null) return {};
    if (raw.length > 10000) {
      throw const FormatException('Invalid report storage');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['pending'] is! Map ||
        (data['pending'] as Map).length > 8) {
      throw const FormatException('Invalid report storage');
    }
    final result = <String, String>{};
    for (final e in (data['pending'] as Map).entries) {
      if (e.key is! String ||
          e.value is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(e.value)) {
        throw const FormatException('Invalid report storage');
      }
      final payload = jsonDecode(e.key);
      if (payload is! List ||
          payload.length != 3 ||
          payload.any((v) => v is! String) ||
          _payload(payload[0], payload[1], payload[2]) != e.key) {
        throw const FormatException('Invalid report storage');
      }
      result[e.key] = e.value;
    }
    if (result.values.toSet().length != result.length) {
      throw const FormatException('Duplicate report key');
    }
    return result;
  }

  Future<T> _serial<T>(String owner, Future<T> Function() action) async {
    final key = _key(owner);
    final before = _tails[key] ?? Future.value();
    Future<T> run() async {
      await before;
      return action();
    }

    final done = run();
    final tail = done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    try {
      return await done;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  Future<void> _write(String owner, Map<String, String> pending) async {
    final raw = jsonEncode({'version': 1, 'pending': pending});
    await _storage.write(key: _key(owner), value: raw);
    if (await _storage.read(key: _key(owner)) != raw) {
      throw StateError('Report retry could not be saved. Nothing was sent.');
    }
  }

  Future<String?> find(
    String owner,
    String type,
    String target,
    String reason,
  ) async => (await _read(owner))[_payload(type, target, reason)];
  Future<String> prepare(
    String owner,
    String type,
    String target,
    String reason,
  ) => _serial(owner, () async {
    final payload = _payload(type, target, reason);
    final pending = await _read(owner);
    if (pending.containsKey(payload)) return pending[payload]!;
    if (pending.length >= 8) {
      throw StateError(
        'Too many unconfirmed reports. Check Your reports before sending another.',
      );
    }
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    pending[payload] = id;
    await _write(owner, pending);
    return id;
  });
  Future<void> complete(
    String owner,
    String type,
    String target,
    String reason,
    String expected,
  ) => _serial(owner, () async {
    final payload = _payload(type, target, reason);
    final pending = await _read(owner);
    if (pending[payload] != expected) return;
    pending.remove(payload);
    await _write(owner, pending);
  });
}

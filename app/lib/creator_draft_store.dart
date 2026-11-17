import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Explicitly saved local text/poll drafts. No media, tokens, upload intent or
/// automatic sending. Account hashes separate storage keys, not authorization.
class CreatorDraft {
  CreatorDraft({
    required this.id,
    required this.text,
    required this.savedAt,
    required this.revision,
    List<String>? options,
  }) : options = options == null ? null : List.unmodifiable(options);
  final String id, text, savedAt, revision;
  final List<String>? options;
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'saved_at': savedAt,
    'revision': revision,
    'options': options,
  };
  static CreatorDraft decode(dynamic data) {
    if (data is! Map ||
        data['id'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['id']) ||
        data['revision'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['revision']) ||
        data['text'] is! String ||
        (data['text'] as String).length > 2000 ||
        data['saved_at'] is! String ||
        DateTime.tryParse(data['saved_at']) == null)
      throw const FormatException('Unrecognized draft');
    final options = data['options'];
    if (options != null &&
        (options is! List ||
            options.length < 2 ||
            options.length > 4 ||
            options.any((v) => v is! String || v.length > 80)))
      throw const FormatException('Unrecognized poll draft');
    return CreatorDraft(
      id: data['id'],
      text: data['text'],
      savedAt: data['saved_at'],
      revision: data['revision'],
      options: options == null ? null : List<String>.from(options),
    );
  }
}

class CreatorDraftStore {
  const CreatorDraftStore();
  static const _storage = FlutterSecureStorage();
  static final Map<String, Future<void>> _tails = {};
  static String _key(String owner) {
    if (owner.isEmpty || owner.length > 256)
      throw ArgumentError('Account required');
    return 'creator_text_drafts_v1_${sha256.convert(utf8.encode(owner))}';
  }

  Future<List<CreatorDraft>> read(String owner) async {
    final raw = await _storage.read(key: _key(owner));
    if (raw == null) return [];
    if (raw.length > 100000)
      throw const FormatException('Draft storage exceeds its bound');
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        value['drafts'] is! List ||
        (value['drafts'] as List).length > 8)
      throw const FormatException('Unrecognized drafts');
    final result = (value['drafts'] as List).map(CreatorDraft.decode).toList();
    if (result.map((d) => d.id).toSet().length != result.length)
      throw const FormatException('Duplicate draft');
    return result;
  }

  Future<T> _serial<T>(String owner, Future<T> Function() action) async {
    final key = _key(owner);
    final before = _tails[key] ?? Future.value();
    final done = actionAfter(before, action);
    final tail = done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    try {
      return await done;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  static Future<T> actionAfter<T>(
    Future<void> before,
    Future<T> Function() action,
  ) async {
    await before;
    return action();
  }

  Future<void> _write(String owner, List<CreatorDraft> drafts) async {
    final raw = jsonEncode({
      'version': 1,
      'drafts': drafts.map((d) => d.toJson()).toList(),
    });
    await _storage.write(key: _key(owner), value: raw);
    if (await _storage.read(key: _key(owner)) != raw)
      throw StateError('Draft save could not be verified');
  }

  Future<CreatorDraft> save(
    String owner, {
    String? id,
    String? expectedRevision,
    required String text,
    List<String>? options,
  }) => _serial(owner, () async {
    final random = Random.secure();
    String nonce() => List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final draft = CreatorDraft.decode({
      'id': id ?? nonce(),
      'revision': nonce(),
      'text': text,
      'options': options,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (text.trim().isEmpty && options == null)
      throw ArgumentError('Write something before saving a draft');
    final existing = await read(owner);
    final found = existing.any((d) => d.id == draft.id);
    if (id != null && !found)
      throw StateError(
        'This saved draft was removed. Open a new post to save another.',
      );
    if (found &&
        existing.firstWhere((d) => d.id == draft.id).revision !=
            expectedRevision)
      throw StateError(
        'This draft changed in another editor. Reopen the saved copy before saving again.',
      );
    if (!found && existing.length >= 8)
      throw StateError(
        'Eight drafts are saved. Delete one before saving another.',
      );
    await _write(owner, [draft, ...existing.where((d) => d.id != draft.id)]);
    return draft;
  });
  Future<void> remove(String owner, String id) => _serial(owner, () async {
    final existing = await read(owner);
    await _write(owner, existing.where((d) => d.id != id).toList());
  });
}

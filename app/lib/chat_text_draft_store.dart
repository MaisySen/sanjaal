import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One explicit text copy per account/conversation. Not an outbox.
class ChatTextDraft {
  const ChatTextDraft(this.text, this.revision);
  final String text, revision;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'text': text,
    'revision': revision,
  };
  static ChatTextDraft decode(dynamic value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['text'] is! String ||
        (value['text'] as String).trim().isEmpty ||
        (value['text'] as String).runes.length > 4000 ||
        value['revision'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['revision'])) {
      throw const FormatException('Invalid saved chat text');
    }
    return ChatTextDraft(value['text'], value['revision']);
  }
}

class ChatTextDraftLimit implements Exception {
  const ChatTextDraftLimit();
}

class ChatTextDraftStore {
  const ChatTextDraftStore();
  static const _storage = FlutterSecureStorage();
  static final _tails = <String, Future<void>>{};
  String _key(String owner, String conversation) {
    if (owner.isEmpty ||
        conversation.isEmpty ||
        owner.length > 256 ||
        conversation.length > 256) {
      throw ArgumentError('Account and conversation required');
    }
    return 'chat_text_draft_v1_${sha256.convert(utf8.encode(jsonEncode([owner, conversation])))}';
  }

  Future<ChatTextDraft?> read(String owner, String conversation) async {
    final raw = await _storage.read(key: _key(owner, conversation));
    if (raw == null) return null;
    if (raw.length > 50000) {
      throw const FormatException('Saved chat text exceeds bound');
    }
    return ChatTextDraft.decode(jsonDecode(raw));
  }

  Future<T> _serial<T>(
    String owner,
    String conversation,
    Future<T> Function() action,
  ) async {
    const key = 'all-chat-text-drafts';
    final before = _tails[key] ?? Future<void>.value();
    final work = before.then((_) => action());
    final tail = work.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _tails[key] = tail;
    try {
      return await work;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  Future<ChatTextDraft> save(
    String owner,
    String conversation,
    String text, {
    String? expectedRevision,
  }) => _serial(owner, conversation, () async {
    final old = await read(owner, conversation);
    if (old?.revision != expectedRevision) {
      throw StateError('Saved text changed. Reopen it before saving.');
    }
    if (old == null) {
      final all = await _storage.readAll();
      if (all.keys.where((k) => k.startsWith('chat_text_draft_v1_')).length >=
          20) {
        throw const ChatTextDraftLimit();
      }
    }
    final random = Random.secure();
    final revision = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final draft = ChatTextDraft.decode({
      'version': 1,
      'text': text,
      'revision': revision,
    });
    final raw = jsonEncode(draft.toJson());
    await _storage.write(key: _key(owner, conversation), value: raw);
    if (await _storage.read(key: _key(owner, conversation)) != raw) {
      throw StateError('Saved text could not be verified');
    }
    return draft;
  });
  Future<void> remove(String owner, String conversation, ChatTextDraft draft) =>
      _serial(owner, conversation, () async {
        final old = await read(owner, conversation);
        if (old?.revision != draft.revision) {
          throw StateError('Saved text changed. Reopen it before removing.');
        }
        await _storage.delete(key: _key(owner, conversation));
        if (await _storage.read(key: _key(owner, conversation)) != null) {
          throw StateError('Saved text removal could not be verified');
        }
      });
}

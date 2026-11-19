import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Explicit local copies only. Never holds a token, upload intent or send job.
class CreatorMediaDraft {
  CreatorMediaDraft(
    this.id,
    this.revision,
    this.text,
    this.video,
    this.attempted,
    this.names,
    this.sizes, {
    String? stamp,
    this.story = false,
    this.audience,
  }) : stamp = stamp ?? revision;
  final String id, revision, text, stamp;
  final bool video, attempted, story;
  final String? audience;
  final List<String> names;
  final List<int> sizes;
  Map<String, dynamic> toJson() => {
    'id': id,
    'revision': revision,
    'stamp': stamp,
    'story': story,
    'audience': audience,
    'text': text,
    'video': video,
    'attempted': attempted,
    'names': names,
    'sizes': sizes,
  };
  static CreatorMediaDraft decode(dynamic value) {
    if (value is! Map ||
        !CreatorMediaDraftStore.nonceValid(value['id']) ||
        !CreatorMediaDraftStore.nonceValid(value['revision']) ||
        !CreatorMediaDraftStore.nonceValid(value['stamp']) ||
        value['text'] is! String ||
        (value['text'] as String).length > 2000 ||
        value['video'] is! bool ||
        value['attempted'] is! bool ||
        value['names'] is! List ||
        value['sizes'] is! List)
      throw const FormatException('Unrecognized media draft');
    final story = value['story'] ?? false;
    final audience = value['audience'];
    if (story is! bool ||
        (story &&
            (!['followers', 'close_friends', 'only_me'].contains(audience) ||
                (value['text'] as String).length > 200)) ||
        (!story && audience != null))
      throw const FormatException('Unrecognized story draft audience');
    final names = value['names'] as List;
    final sizes = value['sizes'] as List;
    if (names.isEmpty ||
        names.length > (value['video'] == true || story ? 1 : 4) ||
        sizes.length != names.length ||
        names.any(
          (n) =>
              n is! String ||
              !RegExp(r'^media\.(jpg|jpeg|png|webp|heic|mp4|mov)$').hasMatch(n),
        ) ||
        sizes.any(
          (n) => n is! int || n < 1 || n > CreatorMediaDraftStore.fileLimit,
        ))
      throw const FormatException('Unrecognized media draft files');
    if (names.any(
      (n) => value['video'] == true
          ? !RegExp(r'^media\.(mp4|mov)$').hasMatch(n)
          : !RegExp(r'^media\.(jpg|jpeg|png|webp|heic)$').hasMatch(n),
    ))
      throw const FormatException('Media type does not match draft');
    return CreatorMediaDraft(
      value['id'],
      value['revision'],
      value['text'],
      value['video'],
      value['attempted'],
      List.unmodifiable(names.cast<String>()),
      List.unmodifiable(sizes.cast<int>()),
      stamp: value['stamp'],
      story: story,
      audience: audience,
    );
  }
}

class CreatorMediaDraftStore {
  const CreatorMediaDraftStore({this.testRoot});
  final Directory? testRoot;
  static const fileLimit = 25 * 1024 * 1024,
      accountLimit = 100 * 1024 * 1024,
      deviceLimit = 256 * 1024 * 1024;
  static const _storage = FlutterSecureStorage();
  static final _cipher = AesGcm.with256bits();
  static Future<void>? _tail;
  static bool nonceValid(dynamic v) =>
      v is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(v);
  static String _nonce() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static String _owner(String owner) {
    if (owner.isEmpty || owner.length > 256)
      throw ArgumentError('Account required');
    return sha256.convert(utf8.encode(owner)).toString();
  }

  Future<T> _serial<T>(Future<T> Function() action) async {
    final before = _tail;
    final done = (() async {
      if (before != null) await before;
      return action();
    })();
    final tail = done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tail = tail;
    try {
      return await done;
    } finally {
      if (identical(_tail, tail)) _tail = null;
    }
  }

  Future<Directory> _root() async {
    final root =
        testRoot ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/creator_media_drafts_v1',
        );
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link)
      throw StateError('Unsafe media storage');
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _directory(
    String owner, {
    String? id,
    String? revision,
  }) async {
    var dir = await _root();
    for (final part in [
      _owner(owner),
      if (id != null) id,
      if (revision != null) revision,
    ]) {
      if (!RegExp(r'^[0-9a-f]{32,64}$').hasMatch(part))
        throw StateError('Unsafe draft path');
      dir = Directory('${dir.path}/$part');
      if (await FileSystemEntity.type(dir.path, followLinks: false) ==
          FileSystemEntityType.link)
        throw StateError('Unsafe media storage');
    }
    return dir;
  }

  Future<List<CreatorMediaDraft>> _read(String owner) async {
    final raw = await _storage.read(key: 'media_drafts_v1_${_owner(owner)}');
    if (raw == null) return [];
    if (raw.length > 100000)
      throw const FormatException('Media draft index exceeds its bound');
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        value['drafts'] is! List ||
        (value['drafts'] as List).length > 8)
      throw const FormatException('Unrecognized media draft index');
    final list = (value['drafts'] as List)
        .map(CreatorMediaDraft.decode)
        .toList();
    if (list.expand((d) => d.sizes).fold<int>(0, (a, b) => a + b) >
        accountLimit)
      throw const FormatException('Media draft index exceeds account limit');
    if (list.map((d) => d.id).toSet().length != list.length)
      throw const FormatException('Duplicate media draft');
    return list;
  }

  Future<List<CreatorMediaDraft>> read(String owner) =>
      _serial(() => _read(owner));
  Future<void> _commit(String owner, List<CreatorMediaDraft> drafts) async {
    final raw = jsonEncode({
      'version': 1,
      'drafts': drafts.map((d) => d.toJson()).toList(),
    });
    final key = 'media_drafts_v1_${_owner(owner)}';
    await _storage.write(key: key, value: raw);
    if (await _storage.read(key: key) != raw)
      throw StateError('Media draft save could not be verified');
  }

  Future<SecretKey> _key(String owner, {bool create = false}) async {
    final key = 'media_draft_key_v1_${_owner(owner)}';
    var raw = await _storage.read(key: key);
    if (raw == null) {
      if (!create)
        throw StateError(
          'Media draft key is unavailable. Nothing was replaced.',
        );
      final secret = await _cipher.newSecretKey();
      raw = base64Encode(await secret.extractBytes());
      await _storage.write(key: key, value: raw);
      if (await _storage.read(key: key) != raw)
        throw StateError('Media draft key could not be saved');
    }
    final bytes = base64Decode(raw);
    if (bytes.length != 32)
      throw const FormatException('Invalid media draft key');
    return SecretKey(bytes);
  }

  Future<void> _cleanupOwner(String owner, List<CreatorMediaDraft> live) async {
    final dir = await _directory(owner);
    if (!await dir.exists()) return;
    final revisions = {for (final d in live) d.id: d.revision};
    await for (final item in dir.list(followLinks: false)) {
      final id = item.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (item is! Directory || !nonceValid(id))
        throw StateError('Unsafe media storage');
      final keep = revisions[id];
      if (keep == null) {
        await item.delete(recursive: true);
        continue;
      }
      await for (final revision in item.list(followLinks: false)) {
        final name = revision.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (revision is! Directory || !nonceValid(name))
          throw StateError('Unsafe media storage');
        if (name != keep) await revision.delete(recursive: true);
      }
    }
  }

  // Pure-Dart AES does synchronous work internally, despite its Future API.
  // Keep bounded large-file crypto and verification off the editor isolate.
  static Future<Uint8List> _encrypt(
    Uint8List bytes,
    List<int> key,
    List<int> aad,
  ) => Isolate.run(() async {
    final box = await AesGcm.with256bits().encrypt(
      bytes,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return box.concatenation();
  });
  static Future<Uint8List> _decrypt(
    Uint8List bytes,
    List<int> key,
    List<int> aad,
  ) => Isolate.run(() async {
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: 12,
      macLength: 16,
    );
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(key),
        aad: aad,
      ),
    );
  });
  static Future<bool> _sameBytes(Uint8List a, Uint8List b) =>
      Isolate.run(() => const ListEqualityBytes().equals(a, b));
  Future<Uint8List> _boundedBytes(XFile file, int expected) async {
    final bytes = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in file.openRead()) {
      count += chunk.length;
      if (count > expected || count > fileLimit)
        throw StateError('The selected file changed while saving');
      bytes.add(chunk);
    }
    if (count != expected)
      throw StateError('The selected file changed while saving');
    return bytes.takeBytes();
  }

  Future<int> _usage() async {
    var bytes = 0;
    await for (final entity in (await _root()).list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw StateError('Unsafe media storage');
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  Future<CreatorMediaDraft> save(
    String owner, {
    required String text,
    required bool video,
    required List<XFile> files,
    String? id,
    String? expectedRevision,
    String? expectedStamp,
    bool story = false,
    String? audience,
  }) => _serial(() async {
    if (story &&
            (!['followers', 'close_friends', 'only_me'].contains(audience) ||
                text.length > 200) ||
        !story && audience != null)
      throw ArgumentError('Choose a story audience before saving');
    if (text.length > 2000 ||
        files.isEmpty ||
        files.length > (video || story ? 1 : 4))
      throw ArgumentError('Choose up to four photos or one video');
    final list = await _read(owner);
    final found = list.where((d) => d.id == id).toList();
    if (id != null &&
        (found.length != 1 ||
            found.single.revision != expectedRevision ||
            found.single.stamp != expectedStamp ||
            found.single.story != story))
      throw StateError('This media draft changed. Reopen the saved copy.');
    if (found.isNotEmpty && found.single.attempted)
      throw StateError(
        'Check the earlier upload before changing this saved draft.',
      );
    if (id == null && list.length >= 8)
      throw StateError(
        'Eight media drafts are saved. Delete one before saving another.',
      );
    final sizes = <int>[];
    final names = <String>[];
    for (final f in files) {
      final size = await f.length();
      if (size < 1 || size > fileLimit)
        throw StateError('Each saved file must be at most 25 MB');
      sizes.add(size);
      final extension = f.name.toLowerCase().split('.').last;
      final allowed = video
          ? ['mp4', 'mov']
          : ['jpg', 'jpeg', 'png', 'webp', 'heic'];
      if (!allowed.contains(extension))
        throw StateError('This file type cannot be saved as a draft');
      names.add('media.$extension');
    }
    await _cleanupOwner(owner, list);
    final total = sizes.fold<int>(0, (a, b) => a + b);
    final existing = list
        .where((d) => d.id != id)
        .expand((d) => d.sizes)
        .fold<int>(0, (a, b) => a + b);
    if (existing + total > accountLimit ||
        await _usage() + total + 4096 > deviceLimit)
      throw StateError(
        'Local media draft storage is full. Delete a saved draft first.',
      );
    final key = await (await _key(owner, create: list.isEmpty)).extractBytes();
    final draft = CreatorMediaDraft(
      id ?? _nonce(),
      _nonce(),
      text,
      video,
      false,
      List.unmodifiable(names),
      List.unmodifiable(sizes),
      story: story,
      audience: audience,
    );
    final dir = await _directory(owner, id: draft.id, revision: draft.revision);
    await dir.create(recursive: true);
    // Unique immutable revision files are complete before the index can refer
    // to them. An interrupted copy leaves old metadata intact, never sends.
    for (var i = 0; i < files.length; i++) {
      final data = await _boundedBytes(files[i], sizes[i]);
      final encrypted = await _encrypt(
        data,
        key,
        utf8.encode('${_owner(owner)}:${draft.id}:${draft.revision}:$i'),
      );
      final output = File('${dir.path}/$i.bin');
      await output.writeAsBytes(encrypted, flush: true);
      final read = await output.readAsBytes();
      if (!await _sameBytes(read, encrypted))
        throw StateError('Saved media could not be verified');
    }
    await _commit(owner, [draft, ...list.where((d) => d.id != draft.id)]);
    // A future save can collect only unreferenced revisions for this owner.
    // Never delete revision files if the index commit could not be verified.
    return draft;
  });
  Future<List<XFile>> open(
    String owner,
    CreatorMediaDraft draft,
  ) => _serial(() async {
    final current = (await _read(owner))
        .where((d) => d.id == draft.id)
        .toList();
    if (current.length != 1 ||
        jsonEncode(current.single.toJson()) != jsonEncode(draft.toJson()))
      throw StateError('This media draft changed. Reopen the saved copy.');
    final key = await (await _key(owner)).extractBytes();
    final dir = await _directory(owner, id: draft.id, revision: draft.revision);
    final result = <XFile>[];
    for (var i = 0; i < draft.names.length; i++) {
      final file = File('${dir.path}/$i.bin');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != draft.sizes[i] + 28)
        throw StateError(
          'Saved media is missing or changed. Nothing was posted.',
        );
      final data = await _decrypt(
        await file.readAsBytes(),
        key,
        utf8.encode('${_owner(owner)}:${draft.id}:${draft.revision}:$i'),
      );
      result.add(
        XFile.fromData(
          data,
          path:
              'draft-memory://${draft.id}/${draft.revision}/$i/${draft.names[i]}',
          name: draft.names[i],
        ),
      );
    }
    return List.unmodifiable(result);
  });
  Future<CreatorMediaDraft> attempted(
    String owner,
    CreatorMediaDraft draft, {
    required bool value,
  }) => _serial(() async {
    final list = await _read(owner);
    final current = list.where((d) => d.id == draft.id).toList();
    if (current.length != 1 ||
        jsonEncode(current.single.toJson()) != jsonEncode(draft.toJson()))
      throw StateError('This media draft changed. Reopen the saved copy.');
    // Preserve file revision/AAD while changing the fail-closed send guard.
    final next = CreatorMediaDraft(
      draft.id,
      draft.revision,
      draft.text,
      draft.video,
      value,
      draft.names,
      draft.sizes,
      stamp: _nonce(),
      story: draft.story,
      audience: draft.audience,
    );
    await _commit(owner, [
      for (final d in list)
        if (d.id == draft.id) next else d,
    ]);
    return next;
  });
  Future<void> remove(String owner, CreatorMediaDraft draft) =>
      _serial(() async {
        final list = await _read(owner);
        final current = list.where((d) => d.id == draft.id).toList();
        if (current.isEmpty) return;
        if (jsonEncode(current.single.toJson()) != jsonEncode(draft.toJson()))
          throw StateError('This media draft changed. Reopen before deleting.');
        await _commit(owner, list.where((d) => d.id != draft.id).toList());
        final dir = await _directory(owner, id: draft.id);
        if (await dir.exists()) await dir.delete(recursive: true);
      });
}

class ListEqualityBytes {
  const ListEqualityBytes();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

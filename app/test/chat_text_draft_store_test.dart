// Secure-storage mock only. Not native process-restart evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sanjaal/chat_text_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = ChatTextDraftStore();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'exact account/conversation and text restore across instances',
    () async {
      final draft = await store.save(
        'one',
        'chat',
        ' नमस्ते\nprivate unsent text ',
      );
      expect(
        (await const ChatTextDraftStore().read('one', 'chat'))!.toJson(),
        draft.toJson(),
      );
      expect(await store.read('two', 'chat'), isNull);
      expect(await store.read('one', 'other-chat'), isNull);
    },
  );
  test('stale write or delete cannot replace a newer saved text', () async {
    final first = await store.save('one', 'chat', 'First');
    final second = await store.save(
      'one',
      'chat',
      'Second',
      expectedRevision: first.revision,
    );
    await expectLater(
      store.save('one', 'chat', 'Stale', expectedRevision: first.revision),
      throwsStateError,
    );
    await expectLater(store.remove('one', 'chat', first), throwsStateError);
    expect((await store.read('one', 'chat'))!.revision, second.revision);
    await store.remove('one', 'chat', second);
    expect(await store.read('one', 'chat'), isNull);
  });
  test('concurrent first saves cannot silently overwrite', () async {
    final results = await Future.wait([
      store
          .save('one', 'chat', 'First')
          .then((_) => true, onError: (_) => false),
      store
          .save('one', 'chat', 'Second')
          .then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((v) => v), hasLength(1));
  });
  test(
    'device cap blocks only new copies, never evicts existing text',
    () async {
      for (var i = 0; i < 20; i++) {
        await store.save('one', 'chat$i', 'Saved $i');
      }
      await expectLater(
        store.save('two', 'new-chat', 'No room'),
        throwsA(isA<ChatTextDraftLimit>()),
      );
      final first = (await store.read('one', 'chat0'))!;
      await store.save(
        'one',
        'chat0',
        'Replacement',
        expectedRevision: first.revision,
      );
      expect((await store.read('one', 'chat19'))!.text, 'Saved 19');
      await store.remove('one', 'chat19', (await store.read('one', 'chat19'))!);
      await store.save('two', 'new-chat', 'Now room');
    },
  );
  test('empty oversized corrupt and unsupported states fail closed', () async {
    await expectLater(store.save('one', 'chat', '  '), throwsFormatException);
    await expectLater(
      store.save('one', 'chat', List.filled(4001, 'x').join()),
      throwsFormatException,
    );
    await store.save('one', 'chat', 'Valid');
    const storage = FlutterSecureStorage();
    final keys = (await storage.readAll()).keys.toList();
    await storage.write(key: keys.single, value: 'broken fixture');
    await expectLater(store.read('one', 'chat'), throwsFormatException);
    await expectLater(
      store.save('one', 'chat', 'Replacement'),
      throwsFormatException,
    );
    expect(await storage.read(key: keys.single), 'broken fixture');
  });
}

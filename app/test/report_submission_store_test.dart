// Mock secure-storage persistence only, not native Keychain/Keystore proof.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sanjaal/report_submission_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = ReportSubmissionStore();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('same account payload restores same UUID after new instance', () async {
    final key = await store.prepare('a', 'post', 'original', 'spam');
    expect(
      await const ReportSubmissionStore().find('a', 'post', 'original', 'spam'),
      key,
    );
    expect(await store.prepare('a', 'post', 'original', 'spam'), key);
    expect(await store.find('b', 'post', 'original', 'spam'), isNull);
    expect(await store.prepare('b', 'post', 'original', 'spam'), isNot(key));
  });
  test(
    'member refs persist independently from legacy and reused handles',
    () async {
      const a = '11111111-1111-4111-8111-111111111111';
      const b = '22222222-2222-4222-8222-222222222222';
      final legacy = await store.prepare('me', 'user', 'asha', 'spam');
      final first = await store.prepare(
        'me',
        'user',
        'asha',
        'spam',
        memberRef: a,
      );
      final second = await store.prepare(
        'me',
        'user',
        'asha',
        'spam',
        memberRef: b,
      );
      expect({legacy, first, second}.length, 3);
      expect(
        (await store.pending('me'))
            .where((row) => row['target_public_id'] == a)
            .single['submission_id'],
        first,
      );
      await store.complete('me', 'user', 'asha', 'spam', first, memberRef: b);
      expect(
        await store.find('me', 'user', 'asha', 'spam', memberRef: a),
        first,
      );
      await store.complete('me', 'user', 'asha', 'spam', first, memberRef: a);
      expect(
        await store.find('me', 'user', 'asha', 'spam', memberRef: a),
        isNull,
      );
      expect(
        await store.find('me', 'user', 'asha', 'spam', memberRef: b),
        second,
      );
    },
  );
  test('changed reason or target keeps independent durable keys', () async {
    final keys = await Future.wait([
      store.prepare('a', 'post', 'one', 'spam'),
      store.prepare('a', 'post', 'one', 'other'),
      store.prepare('a', 'post', 'two', 'spam'),
    ]);
    expect(keys.toSet().length, 3);
    expect(await store.find('a', 'post', 'one', 'spam'), keys.first);
  });
  test('stale completion cannot remove new intent', () async {
    final old = await store.prepare('a', 'post', 'one', 'spam');
    await store.complete('a', 'post', 'one', 'spam', old);
    final newer = await store.prepare('a', 'post', 'one', 'spam');
    await store.complete('a', 'post', 'one', 'spam', old);
    expect(await store.find('a', 'post', 'one', 'spam'), newer);
  });
  test(
    'concurrent identical prepares serialize and bounded storage refuses ninth',
    () async {
      final keys = await Future.wait(
        List.generate(4, (_) => store.prepare('a', 'post', 'one', 'spam')),
      );
      expect(keys.toSet().length, 1);
      for (var i = 1; i < 8; i++) {
        await store.prepare('a', 'post', 'other-$i', 'spam');
      }
      await expectLater(
        store.prepare('a', 'post', 'ninth', 'spam'),
        throwsStateError,
      );
      expect(await store.find('a', 'post', 'one', 'spam'), keys.first);
    },
  );
  test(
    'malformed duplicate or oversized persisted state fails closed',
    () async {
      final key = 'report_submissions_v1_${sha256.convert(utf8.encode('a'))}';
      for (final raw in [
        'not json',
        jsonEncode({'version': 2, 'pending': {}}),
        jsonEncode({
          'version': 1,
          'pending': {'["post","one","spam"]': 'bad'},
        }),
        List.filled(10001, 'x').join(),
      ]) {
        FlutterSecureStorage.setMockInitialValues({key: raw});
        await expectLater(
          store.prepare('a', 'post', 'one', 'spam'),
          throwsA(anything),
        );
      }
    },
  );
}

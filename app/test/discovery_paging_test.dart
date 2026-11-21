import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/discovery_paging.dart';
import 'package:sanjaal/api.dart';

class OwnerSession extends Session {
  int epoch = 0;
  @override
  int get generation => epoch;
  void loginAs(String id) {
    user = {'public_id': id};
    epoch++;
    notifyListeners();
  }
}

DiscoveryPageData<String> page(
  List<String> items, [
  String? cursor,
  String version = 'v1',
]) => DiscoveryPageData(items: items, nextCursor: cursor, version: version);
void main() {
  test('deduplicates stable pages and stops at exhaustion', () async {
    final cursors = <String?>[];
    final p = DiscoveryPaging<String>(
      read: (q, c) async {
        cursors.add(c);
        return c == null ? page(['a', 'b'], 'one') : page(['b', 'c']);
      },
      keyOf: (x) => x,
      ownerActive: () => true,
      maxItems: 9,
      maxPageSize: 3,
    );
    addTearDown(p.dispose);
    await p.load();
    await p.load();
    await p.load();
    expect(p.items, ['a', 'b', 'c']);
    expect(cursors, [null, 'one']);
    expect(p.exhausted, isTrue);
  });
  test(
    'synchronous provider failure releases loading and supports explicit retry',
    () async {
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) {
          if (++reads == 1) throw StateError('sync failure');
          return Future.value(page(['a']));
        },
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      expect(p.loading, isFalse);
      expect(p.error, isNotNull);
      await p.load();
      expect(p.items, ['a']);
      expect(p.error, isNull);
      expect(reads, 2);
    },
  );
  test('repeated load cannot overlap its IO', () async {
    final pending = Completer<DiscoveryPageData<String>>();
    var reads = 0;
    final p = DiscoveryPaging<String>(
      read: (q, c) {
        reads++;
        return pending.future;
      },
      keyOf: (x) => x,
      ownerActive: () => true,
      maxItems: 9,
      maxPageSize: 3,
    );
    addTearDown(p.dispose);
    final first = p.load();
    await p.load();
    expect(reads, 1);
    pending.complete(page(['a']));
    await first;
    expect(p.items, ['a']);
  });
  test('latest filter wins while old read settles without overlap', () async {
    final old = Completer<DiscoveryPageData<String>>();
    final reads = <Map<String, String>>[];
    final p = DiscoveryPaging<String>(
      read: (q, c) {
        reads.add(q);
        return q.isEmpty ? old.future : Future.value(page([q['kind']!]));
      },
      keyOf: (x) => x,
      ownerActive: () => true,
      maxItems: 9,
      maxPageSize: 3,
    );
    addTearDown(p.dispose);
    final first = p.load();
    final second = p.reset({'kind': 'post'});
    final third = p.reset({'kind': 'reel'});
    expect(reads.length, 1);
    old.complete(page(['old']));
    await Future.wait([first, second, third]);
    expect(reads, [
      {},
      {'kind': 'reel'},
    ]);
    expect(p.items, ['reel']);
  });
  test(
    'failed refresh retains usable content and explicit retry replaces it',
    () async {
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) async {
          reads++;
          if (reads == 2) throw StateError('offline');
          return page([reads == 1 ? 'old' : 'new']);
        },
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      await p.reset({}, retain: true);
      expect(p.items, ['old']);
      expect(p.error, isNotNull);
      await p.load();
      expect(p.items, ['new']);
      expect(p.error, isNull);
    },
  );
  for (final failure in ['oversized', 'blank-id', 'version', 'cursor']) {
    test('rejects $failure atomically and retains previous content', () async {
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) async {
          if (++reads == 1) return page(['a'], 'one');
          return switch (failure) {
            'oversized' => page(['b', 'c', 'd', 'e']),
            'blank-id' => page(['b', '']),
            'version' => page(['b'], null, 'v2'),
            _ => page(['b'], 'one'),
          };
        },
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      await p.load();
      expect(p.items, ['a']);
      expect(p.error, isA<FormatException>());
      expect(p.exhausted, isFalse);
    });
  }
  test(
    'cursor cycles cannot silently loop or append an inconsistent page',
    () async {
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) async => switch (++reads) {
          1 => page(['a'], 'one'),
          2 => page(['b'], 'two'),
          _ => page(['c'], 'one'),
        },
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      await p.load();
      await p.load();
      expect(p.items, ['a', 'b']);
      expect(p.error, isA<FormatException>());
    },
  );
  test(
    'owner retirement clears loaded state and ignores pending reply forever',
    () async {
      var active = true, reads = 0;
      final pending = Completer<DiscoveryPageData<String>>();
      final p = DiscoveryPaging<String>(
        read: (q, c) async =>
            ++reads == 1 ? page(['private'], 'one') : pending.future,
        keyOf: (x) => x,
        ownerActive: () => active,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      final next = p.load();
      active = false;
      p.checkOwner();
      expect(p.items, isEmpty);
      expect(p.query, isEmpty);
      active = true;
      pending.complete(page(['late']));
      await next;
      await p.load();
      expect(reads, 2);
      expect(p.items, isEmpty);
      expect(p.retired, isTrue);
    },
  );
  test(
    'retained bound is distinct from server exhaustion and resets explicitly',
    () async {
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) async => page([
          for (var i = 0; i < 3; i++) '${reads * 3 + i}',
        ], 'c${++reads}'),
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 5,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.load();
      await p.load();
      await p.load();
      expect(p.items.length, 5);
      expect(p.atLimit, isTrue);
      expect(p.exhausted, isFalse);
      expect(reads, 2);
      await p.reset({});
      expect(reads, 3);
      expect(p.items.length, 3);
    },
  );
  test('changing filter cannot retain prior-filter content', () async {
    final p = DiscoveryPaging<String>(
      read: (q, c) async => page(['a']),
      keyOf: (x) => x,
      ownerActive: () => true,
      maxItems: 9,
      maxPageSize: 3,
    );
    addTearDown(p.dispose);
    await p.load();
    await expectLater(
      p.reset({'kind': 'reel'}, retain: true),
      throwsArgumentError,
    );
    expect(p.items, ['a']);
    expect(p.query, isEmpty);
  });
  for (final same in [false, true]) {
    test(
      'source Session notification retires ${same ? 'same' : 'other'} member re-login immediately',
      () async {
        final s = OwnerSession()..loginAs('a');
        var reads = 0;
        final p = DiscoveryPaging<String>.forSession(
          currentSession: () => s,
          read: (q, c) async {
            reads++;
            return page(['private']);
          },
          keyOf: (x) => x,
          maxItems: 9,
          maxPageSize: 3,
        );
        addTearDown(p.dispose);
        await p.load();
        expect(p.items, ['private']);
        s.loginAs(same ? 'a' : 'b');
        expect(p.retired, isTrue);
        expect(p.items, isEmpty);
        await p.load();
        expect(reads, 1);
      },
    );
  }
  test('replacement Session object with same owner/generation retires on ownership check', () async {
    var s = OwnerSession()..loginAs('a');
    final p = DiscoveryPaging<String>.forSession(
      currentSession: () => s,
      read: (q, c) async => page(['private']),
      keyOf: (x) => x,
      maxItems: 9,
      maxPageSize: 3,
    );
    addTearDown(p.dispose);
    await p.load();
    s = OwnerSession()..loginAs('a');
    p.checkOwner();
    expect(p.items, isEmpty);
    expect(p.retired, isTrue);
  });
  test(
    'disposal during read cannot repopulate state or notify listeners',
    () async {
      final pending = Completer<DiscoveryPageData<String>>();
      var notices = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) => pending.future,
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      )..addListener(() => notices++);
      final first = p.load();
      p.dispose();
      final before = notices;
      pending.complete(page(['late']));
      await first;
      expect(notices, before);
      expect(p.items, isEmpty);
    },
  );
  test(
    'invalidation preserves filter but rejects an old pending page without IO',
    () async {
      final pending = Completer<DiscoveryPageData<String>>();
      var reads = 0;
      final p = DiscoveryPaging<String>(
        read: (q, c) {
          reads++;
          return reads == 1
              ? Future.value(page(['before'], 'next'))
              : pending.future;
        },
        keyOf: (x) => x,
        ownerActive: () => true,
        maxItems: 9,
        maxPageSize: 3,
      );
      addTearDown(p.dispose);
      await p.reset({'kind': 'reel'});
      final flight = p.load();
      expect(reads, 2);
      p.invalidate();
      expect(p.items, isEmpty);
      expect(p.query, {'kind': 'reel'});
      expect(reads, 2);
      pending.complete(page(['late-withdrawn']));
      await flight;
      expect(p.items, isEmpty);
      expect(p.error, isNull);
      expect(reads, 2);
    },
  );
}

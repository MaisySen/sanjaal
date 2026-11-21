// Local acknowledgement ownership only. No server, account or media effects.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/media_visibility.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/upload_pending_store.dart';

class AckStore extends UploadPendingStore {
  int clears = 0;
  @override
  Future<Map<String, dynamic>?> read(String owner) async => null;
  @override
  Future<void> write(String owner, String id, String kind) async {}
  @override
  Future<void> clear(String owner, {required String? expectedId}) async {
    clears++;
  }
}

class AckSession extends Session {
  AckSession() {
    user = {'public_id': 'member', 'username': 'member'};
  }
  int epoch = 0, reads = 0;
  @override
  int get generation => epoch;
  void retire() {
    epoch++;
    notifyListeners();
  }

  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    reads++;
    return {'post': post('original')};
  }
}

Map<String, dynamic> post(String id) => {
  'public_id': id,
  'kind': 'post',
  'body': 'Confirmed $id',
  'media': [],
  'author': {'public_id': 'member', 'username': 'member'},
};
Future<void> flush(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> fixture(
  WidgetTester t,
  Future<void> Function(
    AckSession,
    UploadCenter,
    AckStore,
    GlobalKey<NavigatorState>,
    ValueNotifier<int>,
  )
  run,
) async {
  final s = AckSession(),
      store = AckStore(),
      nav = GlobalKey<NavigatorState>(),
      tab = ValueNotifier(0);
  final c = UploadCenter.of(s, store: store);
  await flush(t);
  await t.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [mediaRoutes],
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, value, _) => Column(
            children: [
              UploadStrip(center: c, destination: value),
              const Text('Current content'),
            ],
          ),
        ),
      ),
    ),
  );
  await flush(t);
  await run(s, c, store, nav, tab);
  await t.pumpWidget(const SizedBox());
  await t.pump();
  tab.dispose();
}

void main() {
  testWidgets(
    'clean acknowledgement expires but confirmed content and marker clearing stay intact',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        expect(find.text('Your post is up.'), findsOneWidget);
        expect(store.clears, 1);
        await t.pump(const Duration(seconds: 7));
        expect(find.text('Your post is up.'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
        await t.pump();
        expect(find.text('Your post is up.'), findsNothing);
        expect(find.text('Open original'), findsNothing);
        expect(c.confirmedPosts.single['public_id'], 'first');
        expect(c.result, isNull);
        expect(c.occupied, isFalse);
        expect(store.clears, 1);
      });
    },
  );
  testWidgets(
    'route cover consumes success and it does not return as unrelated chrome',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Search')),
          ),
        );
        await t.pumpAndSettle();
        expect(c.result, isNull);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(find.text('Your post is up.'), findsNothing);
        expect(c.confirmedPosts, hasLength(1));
      });
    },
  );
  testWidgets(
    'tab change consumes success while a later job gets a fresh acknowledgement',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        tab.value = 4;
        await flush(t);
        expect(find.text('Open original'), findsNothing);
        c.start('post', () async => post('second'));
        await flush(t);
        expect(find.text('Your post is up.'), findsOneWidget);
        expect(c.confirmedPosts.map((p) => p['public_id']), [
          'second',
          'first',
        ]);
      });
    },
  );
  testWidgets('completion on a covered route expires before a later return', (
    t,
  ) async {
    await fixture(t, (s, c, store, nav, tab) async {
      final pending = Completer<Map<String, dynamic>>();
      c.start('post', () => pending.future);
      await flush(t);
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Chat')),
        ),
      );
      await t.pumpAndSettle();
      pending.complete(post('first'));
      await flush(t);
      await t.pump(const Duration(seconds: 9));
      await flush(t);
      expect(c.result, isNull);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('Open original'), findsNothing);
      expect(c.confirmedPosts, hasLength(1));
    });
  });
  testWidgets(
    'busy and error recovery survive route tab and elapsed-time changes',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        final pending = Completer<Map<String, dynamic>>();
        c.start('post', () => pending.future);
        await flush(t);
        tab.value = 2;
        await flush(t);
        await t.pump(const Duration(seconds: 20));
        expect(c.busy, isTrue);
        pending.completeError(
          UploadError(
            'The upload result is unknown. Check your posts or stories before sharing again.',
            uncertain: true,
          ),
        );
        await flush(t);
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Profile')),
          ),
        );
        await t.pumpAndSettle();
        await t.pump(const Duration(seconds: 20));
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(c.error, isA<UploadError>());
        expect(c.occupied, isTrue);
        expect(c.canRetry, isFalse);
        expect(find.text('Details'), findsOneWidget);
        expect(store.clears, 0);
      });
    },
  );
  testWidgets(
    'background consumes a clean success without clearing recovery markers',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await flush(t);
        expect(c.result, isNull);
        expect(c.confirmedPosts, hasLength(1));
        expect(store.clears, 1);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await flush(t);
        expect(find.text('Your post is up.'), findsNothing);
      });
    },
  );
  testWidgets(
    'covered route rejects retained original callback before the next frame',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        final callback = t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Open original'),
            )
            .onPressed!;
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Current search')),
          ),
        );
        callback();
        await t.pumpAndSettle();
        expect(find.byType(PostPage), findsNothing);
        expect(s.reads, 0);
        expect(find.text('Current search'), findsOneWidget);
        nav.currentState!.pop();
        await t.pumpAndSettle();
      });
    },
  );
  testWidgets(
    'earlier success dismiss callback cannot clear a new uncertain upload',
    (t) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        final callback = t
            .widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Dismiss'))
            .onPressed!;
        c.start(
          'post',
          () async =>
              throw UploadError('Unconfirmed later upload', uncertain: true),
        );
        await flush(t);
        final error = c.error;
        callback();
        await flush(t);
        expect(identical(error, c.error), isTrue);
        expect(c.occupied, isTrue);
        expect(store.clears, 1);
      });
    },
  );
  for (final change in ['retirement', 'new job', 'expiry']) {
    testWidgets('retained original action cannot navigate after $change', (
      t,
    ) async {
      await fixture(t, (s, c, store, nav, tab) async {
        c.start('post', () async => post('first'));
        await flush(t);
        final callback = t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Open original'),
            )
            .onPressed!;
        if (change == 'retirement') {
          s.retire();
          await flush(t);
        }
        if (change == 'new job') {
          c.start('post', () async => post('second'));
          await flush(t);
        }
        if (change == 'expiry') {
          await t.pump(const Duration(seconds: 9));
          await flush(t);
        }
        callback();
        await flush(t);
        expect(find.byType(PostPage), findsNothing);
        expect(s.reads, 0);
        if (change == 'new job') expect(c.result?['public_id'], 'second');
      });
    });
  }
  testWidgets('current original action opens exactly the confirmed post', (
    t,
  ) async {
    await fixture(t, (s, c, store, nav, tab) async {
      c.start('post', () async => post('first'));
      await flush(t);
      await t.tap(find.text('Open original'));
      await t.pumpAndSettle();
      expect(find.byType(PostPage), findsOneWidget);
      expect(t.widget<PostPage>(find.byType(PostPage)).postId, 'first');
      expect(c.result, isNull);
      expect(c.confirmedPosts, hasLength(1));
      nav.currentState!.pop();
      await t.pumpAndSettle();
    });
  });
}

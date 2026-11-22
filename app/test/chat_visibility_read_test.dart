// Synthetic visibility boundaries only. No real messages or read receipts.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/api.dart' show Session;
import 'package:sanjaal/media_visibility.dart';

import 'upload_center_test.dart' as h;

Map<String, dynamic> message([int seq = 1]) => {
  'public_id': 'message-$seq',
  'seq': seq,
  'body': seq == 1 ? 'Visible after return' : 'Second visible message',
  'kind': 'text',
  'created_at': '2026-11-20T00:00:00Z',
  'sender': {'public_id': 'other', 'username': 'other'},
};
void pause(WidgetTester t) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    t.binding.handleAppLifecycleStateChanged(state);
  }
}

void resume(WidgetTester t) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(state);
  }
}

Widget thread(Session session) => MaterialApp(
  navigatorObservers: [mediaRoutes],
  home: ChatPage(
    session: session,
    convo: {'public_id': 'chat', 'title': 'Synthetic thread', 'type': 'direct'},
  ),
);
void main() {
  for (final cover in ['background', 'route']) {
    testWidgets('chat does not acknowledge an unseen reply during $cover', (
      t,
    ) async {
      final first = Completer<http.Response>();
      final pending = <Completer<http.Response>>[];
      var reads = 0, acknowledgements = 0;
      var resumed = false;
      await h.fixture(
        t,
        (s, c) async {
          final navigator = GlobalKey<NavigatorState>();
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              navigatorObservers: [mediaRoutes],
              home: ChatPage(
                session: s,
                convo: {
                  'public_id': 'chat',
                  'title': 'Synthetic thread',
                  'type': 'direct',
                },
              ),
            ),
          );
          await h.flush(t);
          if (cover == 'background') {
            pause(t);
          } else {
            navigator.currentState!.push(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Cover route')),
              ),
            );
          }
          await h.flush(t);
          first.complete(
            h.json({
              'data': [message()],
            }),
          );
          await h.flush(t);
          await t.pump(const Duration(seconds: 10));
          await h.flush(t);
          final hiddenAcks = acknowledgements, hiddenReads = reads;
          final hiddenRendered = find
              .text('Visible after return', skipOffstage: false)
              .evaluate()
              .isNotEmpty;
          resumed = true;
          for (final p in List.of(pending)) {
            if (!p.isCompleted) {
              p.complete(
                h.json({
                  'data': [message()],
                }),
              );
            }
          }
          if (cover == 'background') {
            resume(t);
          } else {
            navigator.currentState!.pop();
          }
          await h.flush(t);
          final returned = find.text('Visible after return').evaluate().length;
          final visibleAcks = acknowledgements;
          await t.pumpWidget(const SizedBox());
          for (final p in pending) {
            if (!p.isCompleted) p.complete(h.json({'data': []}));
          }
          await h.flush(t);
          expect(hiddenAcks, 0);
          expect(hiddenReads, 1);
          expect(hiddenRendered, isFalse);
          expect(returned, 1);
          expect(visibleAcks, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/read')) {
            acknowledgements++;
            return h.json({});
          }
          if (r.url.path.endsWith('/messages')) {
            reads++;
            if (reads == 1) return first.future;
            if (resumed && reads == 2) {
              return h.json({
                'data': [message()],
              });
            }
            final p = Completer<http.Response>();
            pending.add(p);
            return p.future;
          }
          return h.json({'data': []});
        },
      );
    });
  }
  testWidgets(
    'chat constructed while paused defers its initial read until resume',
    (t) async {
      var reads = 0, acks = 0;
      final pending = <Completer<http.Response>>[];
      await h.fixture(
        t,
        (s, c) async {
          pause(t);
          await t.pumpWidget(thread(s));
          // Force a synthetic startup frame. A normal paused pump does not build.
          t.binding.scheduleForcedFrame();
          await t.pump();
          expect(find.byType(ChatPage), findsOneWidget);
          await h.flush(t);
          await t.pump(const Duration(seconds: 10));
          await h.flush(t);
          final pausedReads = reads;
          resume(t);
          await h.flush(t);
          final shown = find.text('Visible after return').evaluate().length;
          final visibleAcks = acks;
          await t.pumpWidget(const SizedBox());
          for (final p in pending) {
            if (!p.isCompleted) p.complete(h.json({'data': []}));
          }
          await h.flush(t);
          expect(pausedReads, 0);
          expect(shown, 1);
          expect(visibleAcks, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/read')) {
            acks++;
            return h.json({});
          }
          if (++reads == 1) {
            return h.json({
              'data': [message()],
            });
          }
          final p = Completer<http.Response>();
          pending.add(p);
          return p.future;
        },
      );
    },
  );
  testWidgets(
    'hidden normal long poll resumes from the last displayed cursor',
    (t) async {
      var reads = 0, acks = 0;
      String? resumedCursor;
      final pending = <Completer<http.Response>>[];
      final hidden = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(thread(s));
          await h.flush(t);
          pause(t);
          hidden.complete(
            h.json({
              'data': [message(2)],
            }),
          );
          await h.flush(t);
          await t.pump(const Duration(seconds: 10));
          await h.flush(t);
          final hiddenAcks = acks, hiddenReads = reads;
          final hiddenRow = find
              .text('Second visible message', skipOffstage: false)
              .evaluate()
              .isNotEmpty;
          resume(t);
          await h.flush(t);
          final visibleRow = find
              .text('Second visible message')
              .evaluate()
              .length;
          final visibleAcks = acks;
          await t.pumpWidget(const SizedBox());
          for (final p in pending) {
            if (!p.isCompleted) p.complete(h.json({'data': []}));
          }
          await h.flush(t);
          expect(hiddenAcks, 1);
          expect(hiddenReads, 2);
          expect(hiddenRow, isFalse);
          expect(resumedCursor, '1');
          expect(visibleRow, 1);
          expect(visibleAcks, 2);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/read')) {
            acks++;
            return h.json({});
          }
          reads++;
          if (reads == 1) {
            return h.json({
              'data': [message()],
            });
          }
          if (reads == 2) return hidden.future;
          if (reads == 3) {
            resumedCursor = r.url.queryParameters['after_seq'];
            return h.json({
              'data': [message(2)],
            });
          }
          final p = Completer<http.Response>();
          pending.add(p);
          return p.future;
        },
      );
    },
  );
  for (final end in ['dispose', 'replace login']) {
    testWidgets('paused chat $end cannot restart reads on resume', (t) async {
      var reads = 0;
      final writes = <String>[];
      final observed = <String>[];
      final pending = <Completer<http.Response>>[];
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(thread(s));
          await h.flush(t);
          expect(reads, 1);
          pause(t);
          pending.single.complete(h.json({'data': []}));
          await h.flush(t);
          await t.pump(const Duration(seconds: 10));
          await h.flush(t);
          if (end == 'dispose') {
            await t.pumpWidget(const SizedBox());
            t.binding.scheduleForcedFrame();
            await t.pump();
          } else {
            await s.login('replacement', 'fixture');
            await h.flush(t);
          }
          resume(t);
          await h.flush(t);
          if (end != 'dispose') {
            expect(
              find.textContaining('another signed-in session'),
              findsOneWidget,
            );
          }
          await t.pump(const Duration(seconds: 10));
          await h.flush(t);
          await t.pumpWidget(const SizedBox());
          for (final p in pending) {
            if (!p.isCompleted) p.complete(h.json({'data': []}));
          }
          await h.flush(t);
          expect(reads, 1, reason: observed.join(', '));
          expect(writes, isEmpty);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          observed.add('${r.method} ${r.url.path}');
          if (r.method != 'GET') {
            writes.add('${r.method} ${r.url.path}');
            return h.json({});
          }
          reads++;
          final p = Completer<http.Response>();
          pending.add(p);
          return p.future;
        },
      );
    });
  }
  for (final hidden in ['covered', 'background']) {
    testWidgets(
      '$hidden inbox does not spend its 12 second polls until return',
      (t) async {
        var reads = 0;
        await h.fixture(
          t,
          (s, c) async {
            final navigator = GlobalKey<NavigatorState>();
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: navigator,
                navigatorObservers: [mediaRoutes],
                home: ChatsPage(session: s),
              ),
            );
            await h.flush(t);
            if (hidden == 'background') {
              pause(t);
            } else {
              navigator.currentState!.push(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('Cover route')),
                ),
              );
            }
            await h.flush(t);
            for (var i = 0; i < 3; i++) {
              await t.pump(const Duration(seconds: 12));
              await h.flush(t);
            }
            final coveredReads = reads;
            if (hidden == 'background') {
              resume(t);
            } else {
              navigator.currentState!.pop();
            }
            await h.flush(t);
            await t.pump(const Duration(seconds: 12));
            await h.flush(t);
            final returnedReads = reads;
            await t.pumpWidget(const SizedBox());
            await h.flush(t);
            expect(coveredReads, 1);
            expect(returnedReads, 2);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            reads++;
            return h.json({'data': []});
          },
        );
      },
    );
  }
}

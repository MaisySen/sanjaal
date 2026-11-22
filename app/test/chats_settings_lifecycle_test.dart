// Synthetic pending requests, lifecycle and callbacks only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'upload_center_test.dart' as h;

const flags = {'pinned': false, 'muted': true, 'archived': false};
Map<String, dynamic> row([String title = 'Original thread']) => {
  'public_id': 'thread',
  'type': 'direct',
  'title': title,
  'unread': 0,
  ...flags,
};
VoidCallback menu(WidgetTester t, [String title = 'Original thread']) => t
    .widget<InkWell>(
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
    )
    .onLongPress!;
void main() {
  for (final end in ['replacement', 'dispose']) {
    for (final stage in ['write', 'read', 'retry']) {
      for (final fail in [false, true]) {
        testWidgets('$end retires pending settings $stage fail=$fail', (
          t,
        ) async {
          var reads = 0, writes = 0;
          final pending = Completer<http.Response>();
          await h.fixture(
            t,
            (s, c) async {
              await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
              await h.flush(t);
              menu(t)();
              await h.flush(t);
              await t.tap(find.widgetWithText(ListTile, 'Unmute'));
              await h.flush(t);
              if (stage == 'retry') {
                await t.tap(find.text('Try again'));
                await h.flush(t);
              }
              final originalReads = reads;
              if (end == 'replacement') {
                await s.login('replacement', 'fixture');
                await h.flush(t);
              } else {
                await t.pumpWidget(const SizedBox());
                await h.flush(t);
              }
              final leaked = find
                  .text('Original thread', skipOffstage: false)
                  .evaluate()
                  .length;
              final busy = find
                  .text('Updating chat settings', skipOffstage: false)
                  .evaluate()
                  .length;
              pending.complete(
                fail
                    ? h.json({'message': 'Synthetic failure'}, 503)
                    : stage == 'write'
                    ? h.json(flags)
                    : h.json({
                        'data': [row('Late private thread')],
                      }),
              );
              await h.flush(t);
              await t.pump(const Duration(seconds: 13));
              await h.flush(t);
              final late = find
                  .text('Late private thread', skipOffstage: false)
                  .evaluate()
                  .length;
              await t.pumpWidget(const SizedBox());
              await h.flush(t);
              expect(
                originalReads,
                stage == 'write'
                    ? 1
                    : stage == 'read'
                    ? 2
                    : 3,
              );
              expect(reads, originalReads);
              expect(writes, 1);
              expect(leaked, 0);
              expect(busy, 0);
              expect(late, 0);
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.method == 'PATCH') {
                writes++;
                return stage == 'write' ? pending.future : h.json(flags);
              }
              reads++;
              if (reads == 2 && stage == 'read') return pending.future;
              if (stage == 'retry') {
                if (reads == 2) {
                  return h.json({'message': 'Synthetic read failure'}, 503);
                }
                if (reads == 3) return pending.future;
              }
              return h.json({
                'data': [row()],
              });
            },
          );
        });
      }
    }
  }
  testWidgets(
    'pending settings suppress poll and retained refresh/archive callbacks',
    (t) async {
      var reads = 0, writes = 0;
      final pending = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          final refresh = t
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh;
          final archive = t
              .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>),
              )
              .onSelected!;
          menu(t)();
          await h.flush(t);
          await t.tap(find.widgetWithText(ListTile, 'Unmute'));
          await h.flush(t);
          await refresh();
          archive('archive');
          await h.flush(t);
          await t.pump(const Duration(seconds: 12));
          await h.flush(t);
          final pendingReads = reads;
          final title = find.text('Archived').evaluate().length;
          final disabledArchive = !t
              .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>),
              )
              .enabled;
          final canBrowse =
              t
                  .widget<InkWell>(
                    find.ancestor(
                      of: find.text('Original thread'),
                      matching: find.byType(InkWell),
                    ),
                  )
                  .onTap !=
              null;
          pending.complete(h.json(flags));
          await h.flush(t);
          final recovered = t
              .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>),
              )
              .enabled;
          await t.pumpWidget(const SizedBox());
          await h.flush(t);
          expect(pendingReads, 1);
          expect(reads, 2);
          expect(writes, 1);
          expect(title, 0);
          expect(disabledArchive, isTrue);
          expect(canBrowse, isTrue);
          expect(recovered, isTrue);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'PATCH') {
            writes++;
            return pending.future;
          }
          reads++;
          return h.json({
            'data': [row()],
          });
        },
      );
    },
  );
  testWidgets(
    'pre-change poll cannot replace rows while settings write is pending',
    (t) async {
      var reads = 0;
      final old = Completer<http.Response>(),
          pending = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          await t.pump(const Duration(seconds: 12));
          await h.flush(t);
          menu(t)();
          await h.flush(t);
          await t.tap(find.widgetWithText(ListTile, 'Unmute'));
          await h.flush(t);
          old.complete(
            h.json({
              'data': [row('Stale progress')],
            }),
          );
          await h.flush(t);
          final original = find.text('Original thread').evaluate().length,
              stale = find.text('Stale progress').evaluate().length;
          pending.complete(h.json(flags));
          await h.flush(t);
          final fresh = find.text('Fresh thread').evaluate().length;
          await t.pumpWidget(const SizedBox());
          await h.flush(t);
          expect(original, 1);
          expect(stale, 0);
          expect(fresh, 1);
          expect(reads, 3);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'PATCH') return pending.future;
          reads++;
          if (reads == 2) return old.future;
          return h.json({
            'data': [row(reads == 1 ? 'Original thread' : 'Fresh thread')],
          });
        },
      );
    },
  );
  testWidgets('pending settings still allow conversation entry and Back', (
    t,
  ) async {
    var reads = 0, writes = 0, messageReads = 0;
    final pending = Completer<http.Response>(),
        poll = Completer<http.Response>();
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
        await h.flush(t);
        menu(t)();
        await h.flush(t);
        await t.tap(find.widgetWithText(ListTile, 'Unmute'));
        await h.flush(t);
        await t.tap(find.text('Original thread'));
        await h.flush(t);
        final opened = find.byType(ChatPage).evaluate().length;
        await t.pageBack();
        await h.flush(t);
        final busy = find.text('Updating chat settings').evaluate().length,
            duringReads = reads;
        pending.complete(h.json(flags));
        await h.flush(t);
        final settled = find.text('Updating chat settings').evaluate().length;
        await t.pumpWidget(const SizedBox());
        if (!poll.isCompleted) poll.complete(h.json({'data': []}));
        await h.flush(t);
        expect(opened, 1);
        expect(busy, 1);
        expect(settled, 0);
        expect(duringReads, 1);
        expect(reads, 2);
        expect(writes, 1);
        expect(messageReads, greaterThanOrEqualTo(1));
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.url.path.endsWith('/messages')) {
          messageReads++;
          return messageReads == 1 ? h.json({'data': []}) : poll.future;
        }
        if (r.url.path.endsWith('/read')) return h.json({});
        if (r.method == 'PATCH') {
          writes++;
          return pending.future;
        }
        reads++;
        return h.json({
          'data': [row()],
        });
      },
    );
  });
}

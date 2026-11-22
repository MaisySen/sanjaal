// Synthetic parent inbox navigation and create/open ordering only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'chats_entry_ownership_test.dart' as e;
import 'profile_chat_receipt_test.dart' as receipt;
import 'upload_center_test.dart' as h;

Future<void> cover(WidgetTester t) async {
  Navigator.of(t.element(find.byType(ChatsPage))).push(
    MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Keep this cover')),
    ),
  );
  await h.flush(t);
}

Map<String, dynamic> inboxRow([String id = 'chat']) => {
  'public_id': id,
  'type': 'direct',
  'title': 'Synthetic conversation',
};
void main() {
  menuCases();
  for (final label in ['Calls', 'Live rooms', 'New chat', 'Conversation']) {
    for (final hidden in ['cover', 'inactive tab']) {
      testWidgets('$label retained entry cannot navigate from $hidden', (
        t,
      ) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        await h.fixture(
          t,
          (s, c) async {
            final routes = e.Routes();
            await t.pumpWidget(
              MaterialApp(
                navigatorObservers: [routes],
                home: ValueListenableBuilder(
                  valueListenable: active,
                  builder: (_, value, child) =>
                      ChatsPage(session: s, active: value),
                ),
              ),
            );
            await h.flush(t);
            final old = e.action(t, label);
            if (hidden == 'cover') {
              await cover(t);
            } else {
              active.value = false;
              await h.flush(t);
            }
            final before = routes.pushes;
            old();
            await h.flush(t);
            await t.pumpAndSettle();
            expect(routes.pushes, before);
            expect(t.takeException(), isNull);
          },
          respond: (r) async => h.json({
            'data': r.url.path.endsWith('/conversations') ? [inboxRow()] : [],
          }),
        );
      });
    }
  }
  testWidgets(
    'retained inbox row cannot open after the current list replaced it',
    (t) async {
      var reads = 0, chatReads = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          final old = e.action(t, 'Conversation');
          t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
          await h.flush(t);
          old();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(ChatPage), findsNothing);
          expect(chatReads, 0);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/conversations')) {
            return h.json({
              'data': ++reads == 1 ? [inboxRow()] : [],
            });
          }
          if (r.url.path.contains('/conversations/')) chatReads++;
          return h.json({'data': [], 'has_more': false});
        },
      );
    },
  );
  for (final hidden in ['cover', 'inactive tab']) {
    testWidgets('parent retires a returned child receipt under $hidden', (
      t,
    ) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      var chatReads = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder(
                valueListenable: active,
                builder: (_, value, child) =>
                    ChatsPage(session: s, active: value),
              ),
            ),
          );
          await h.flush(t);
          await t.tap(find.byTooltip('New chat'));
          await h.flush(t);
          final nav = Navigator.of(t.element(find.byType(NewChatPage)));
          if (hidden == 'inactive tab') {
            active.value = false;
            await h.flush(t);
          }
          nav.pop<Map<String, dynamic>>(receipt.conversation());
          if (hidden == 'cover') {
            nav.push(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Keep this cover')),
              ),
            );
          }
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(ChatPage), findsNothing);
          expect(chatReads, 0);
          if (hidden == 'cover') {
            expect(find.text('Keep this cover'), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.contains('/conversations/')) chatReads++;
          return h.json({'data': [], 'has_more': false});
        },
      );
    });
  }
  testWidgets(
    'verified new direct chat opens before any subsequent inbox request completes',
    (t) async {
      final slowInbox = Completer<http.Response>();
      var inboxReads = 0, messageReads = 0, creates = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          await t.tap(find.byTooltip('New chat'));
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'asha');
          await h.flush(t);
          await t.tap(find.text('Asha Gurung'));
          await h.flush(t);
          await h.flush(t);
          final opened = find.byType(ChatPage).evaluate().length,
              messagesBefore = messageReads,
              inboxBefore = inboxReads;
          slowInbox.complete(
            h.json({
              'data': [receipt.conversation()],
            }),
          );
          await h.flush(t);
          await t.pumpAndSettle();
          expect(opened, 1);
          expect(messagesBefore, greaterThanOrEqualTo(1));
          expect(inboxBefore, 1);
          expect(creates, 1);
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(ChatsPage), findsOneWidget);
          expect(inboxReads, 2);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/users/search')) {
            return h.json({
              'users': [
                {
                  'public_id': 'asha',
                  'username': 'asha',
                  'name': 'Asha Gurung',
                },
              ],
            });
          }
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            creates++;
            return h.json({'conversation': receipt.conversation()});
          }
          if (r.url.path.endsWith('/conversations')) {
            return ++inboxReads == 1 ? h.json({'data': []}) : slowInbox.future;
          }
          if (r.method == 'GET' && r.url.path.endsWith('/messages')) {
            messageReads++;
          }
          return h.json({'data': [], 'has_more': false});
        },
      );
    },
  );
  testWidgets(
    'Check Chats after an uncertain creation refreshes without another creation or auto-open',
    (t) async {
      var creates = 0, inboxReads = 0, messageReads = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          await t.tap(find.byTooltip('New chat'));
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'asha');
          await h.flush(t);
          await t.tap(find.text('Asha Gurung'));
          await h.flush(t);
          await t.tap(find.text('Back to Chats'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(inboxReads, 2);
          expect(creates, 1);
          expect(messageReads, 0);
          expect(find.text('Selected member'), findsOneWidget);
          expect(find.byType(ChatPage), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/users/search')) {
            return h.json({
              'users': [
                {
                  'public_id': 'asha',
                  'username': 'asha',
                  'name': 'Asha Gurung',
                },
              ],
            });
          }
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            creates++;
            return h.json({'message': 'Synthetic unknown result'}, 503);
          }
          if (r.url.path.endsWith('/conversations')) {
            inboxReads++;
            return h.json({
              'data': creates > 0 ? [receipt.conversation()] : [],
            });
          }
          if (r.url.path.endsWith('/messages')) messageReads++;
          return h.json({'data': [], 'has_more': false});
        },
      );
    },
  );
}

void menuCases() {
  for (final kind in ['More', 'row menu']) {
    for (final hidden in ['cover', 'inactive tab']) {
      testWidgets('$kind retained callback is inert under $hidden', (t) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        var reads = 0;
        await h.fixture(
          t,
          (s, c) async {
            final routes = e.Routes();
            await t.pumpWidget(
              MaterialApp(
                navigatorObservers: [routes],
                home: ValueListenableBuilder(
                  valueListenable: active,
                  builder: (_, value, child) =>
                      ChatsPage(session: s, active: value),
                ),
              ),
            );
            await h.flush(t);
            final VoidCallback old;
            if (kind == 'More') {
              final selected = t
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .onSelected!;
              old = () => selected('archive');
            } else {
              old = t
                  .widget<InkWell>(
                    find
                        .ancestor(
                          of: find.text('Synthetic conversation'),
                          matching: find.byType(InkWell),
                        )
                        .first,
                  )
                  .onLongPress!;
            }
            if (hidden == 'cover') {
              await cover(t);
            } else {
              active.value = false;
              await h.flush(t);
            }
            final before = routes.pushes, readsBefore = reads;
            old();
            await h.flush(t);
            await t.pumpAndSettle();
            expect(routes.pushes, before);
            expect(reads, readsBefore);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            reads++;
            return h.json({
              'data': [inboxRow()],
            });
          },
        );
      });
    }
  }
}

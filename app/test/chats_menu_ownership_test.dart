// Synthetic inbox/menu callbacks and HTTP only. No real conversation setting.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'upload_center_test.dart' as h;

void main() {
  for (final shape in [
    'normal',
    'overlap',
    'dismissed',
    'covered',
    'duplicate menu',
    'refreshed row',
    'changed row',
  ]) {
    testWidgets('Chats setting callback rejects $shape', (t) async {
      var writes = 0;
      final pending = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          final nav = GlobalKey<NavigatorState>();
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Text('Root fixture')),
            ),
          );
          nav.currentState!.push(
            MaterialPageRoute(builder: (_) => ChatsPage(session: s)),
          );
          await h.flush(t);
          final row = t.widget<InkWell>(
            find.ancestor(
              of: find.text('Private thread'),
              matching: find.byType(InkWell),
            ),
          );
          final open = row.onLongPress!;
          final refresh = t
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh;
          if (shape == 'refreshed row') {
            await refresh();
            await h.flush(t);
          }
          open();
          if (shape == 'duplicate menu') open();
          await h.flush(t);
          final menus = find.widgetWithText(ListTile, 'Mute').evaluate().length;
          if (shape != 'duplicate menu' && shape != 'refreshed row') {
            final action = t
                .widget<ListTile>(find.widgetWithText(ListTile, 'Mute'))
                .onTap!;
            if (shape == 'dismissed') {
              nav.currentState!.pop();
              await h.flush(t);
            }
            if (shape == 'covered') {
              nav.currentState!.push(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('Cover fixture')),
                ),
              );
              await h.flush(t);
            }
            if (shape == 'changed row') {
              await refresh();
              await h.flush(t);
            }
            action();
            if (shape == 'overlap') action();
            await h.flush(t);
          }
          final mutations = writes;
          final inbox = find
              .byType(ChatsPage, skipOffstage: false)
              .evaluate()
              .length;
          final cover = find.text('Cover fixture').evaluate().length;
          pending.complete(h.json({}));
          await h.flush(t);
          if (shape == 'normal' || shape == 'dismissed') {
            final current = t.widget<InkWell>(
              find.ancestor(
                of: find.text('Private thread'),
                matching: find.byType(InkWell),
              ),
            );
            current.onLongPress!();
            await h.flush(t);
            expect(find.widgetWithText(ListTile, 'Mute'), findsOneWidget);
          }
          nav.currentState!.popUntil((r) => r.isFirst);
          await h.flush(t);
          await t.pumpWidget(const SizedBox());
          await h.flush(t);
          expect(mutations, shape == 'overlap' || shape == 'normal' ? 1 : 0);
          if (shape == 'refreshed row') expect(menus, 0);
          if (shape == 'duplicate menu') expect(menus, 1);
          if (shape == 'overlap' || shape == 'dismissed') expect(inbox, 1);
          if (shape == 'covered') expect(cover, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'PATCH') {
            writes++;
            return pending.future;
          }
          return h.json({
            'data': [
              {
                'public_id': 'thread',
                'type': 'direct',
                'title': 'Private thread',
                'unread': 0,
              },
            ],
          });
        },
      );
    });
  }
}

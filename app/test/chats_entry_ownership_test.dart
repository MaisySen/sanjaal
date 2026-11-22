// Synthetic conversation/Calls/Rooms entry only. No call, room or message action.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'upload_center_test.dart' as h;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

VoidCallback action(WidgetTester t, String label) => switch (label) {
  'New chat' =>
    t
        .widget<IconButton>(
          find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label),
        )
        .onPressed!,
  'Conversation' =>
    t
        .widget<InkWell>(
          find
              .ancestor(
                of: find.text('Synthetic conversation'),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap!,
  _ => t.widget<TextButton>(find.widgetWithText(TextButton, label)).onPressed!,
};
void main() {
  for (final label in ['Calls', 'Live rooms', 'New chat', 'Conversation']) {
    testWidgets('Chats $label retained callback rejects replacement login', (
      t,
    ) async {
      await h.fixture(
        t,
        (s, c) async {
          final routes = Routes();
          await t.pumpWidget(
            MaterialApp(
              navigatorObservers: [routes],
              home: ChatsPage(session: s),
            ),
          );
          await h.flush(t);
          final old = action(t, label);
          await s.login('fixture', 'not-a-password');
          await h.flush(t);
          old();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) async => h.json({
          'data': r.url.path.endsWith('/conversations')
              ? [
                  {
                    'public_id': 'chat',
                    'title': 'Synthetic conversation',
                    'type': 'direct',
                  },
                ]
              : [],
        }),
      );
    });
    testWidgets('Chats $label opens once and reopens after Back', (t) async {
      await h.fixture(
        t,
        (s, c) async {
          final routes = Routes();
          await t.pumpWidget(
            MaterialApp(
              navigatorObservers: [routes],
              home: ChatsPage(session: s),
            ),
          );
          await h.flush(t);
          final open = action(t, label);
          open();
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 2);
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          action(t, label)();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 3);
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
        respond: (r) async => h.json({
          'data': r.url.path.endsWith('/conversations')
              ? [
                  {
                    'public_id': 'chat',
                    'title': 'Synthetic conversation',
                    'type': 'direct',
                  },
                ]
              : [],
        }),
      );
    });
  }
  testWidgets(
    'retired Chats callbacks never revive when original member returns',
    (t) async {
      await h.fixture(t, (s, c) async {
        final routes = Routes();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: ChatsPage(session: s),
          ),
        );
        await h.flush(t);
        final old = action(t, 'New chat');
        final original = s.user;
        s.user = {'public_id': 'other'};
        s.notifyListeners();
        await t.pump();
        s.user = original;
        s.notifyListeners();
        await t.pump();
        old();
        await h.flush(t);
        await t.pumpAndSettle();
        expect(routes.pushes, 1);
        expect(find.byType(NewChatPage), findsNothing);
        expect(t.takeException(), isNull);
      });
    },
  );
}

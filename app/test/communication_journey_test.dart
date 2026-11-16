// Offline fixture assertions only. No live calls, room creation or messages.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, Avatar;
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object body, [int code = 200]) => http.Response(jsonEncode(body), code);
Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}
Future<void> withSession(WidgetTester t, Future<void> Function(Session) run, Future<http.Response> Function(http.Request) api) async {
  SharedPreferences.setMockInitialValues({});
  prefs.lang = 'en';
  await http.runWithClient(() async {
    final session = Session();
    await session.login('fixture', 'not-a-password');
    await run(session);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture', 'expires_in': 3600});
    if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': 'me', 'username': 'fixture'}});
    return api(r);
  }));
}
Widget app(Widget home) => MaterialApp(theme: buildTheme(Brightness.light), home: home);

void main() {
  testWidgets('empty inbox has a direct create action and visible calls and rooms', (t) async {
    await withSession(t, (s) async {
      await t.pumpWidget(app(ChatsPage(session: s)));
      await flush(t);
      expect(find.text('Start a conversation'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Calls'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Live rooms'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'New chat'));
      await flush(t);
      expect(find.byType(NewChatPage), findsOneWidget);
    }, (_) async => reply({'data': []}));
  });

  for (final destination in ['Calls', 'Live rooms']) {
    testWidgets('inbox opens $destination without a menu', (t) async {
      await withSession(t, (s) async {
        await t.pumpWidget(app(ChatsPage(session: s)));
        await flush(t);
        await t.tap(find.widgetWithText(TextButton, destination));
        await flush(t);
        expect(find.byType(destination == 'Calls' ? CallsPage : RoomsPage), findsOneWidget);
        expect(t.takeException(), isNull);
      }, (_) async => reply({'data': []}));
    });
  }

  for (final page in ['chats', 'calls', 'rooms']) {
    testWidgets('$page load failure has retry, not a misleading create action', (t) async {
      var fail = true;
      var reads = 0;
      await withSession(t, (s) async {
        await t.pumpWidget(app(switch (page) { 'chats' => ChatsPage(session: s), 'calls' => CallsPage(session: s), _ => RoomsPage(session: s) }));
        await flush(t);
        expect(find.text('Fixture unavailable'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
        expect(find.text('Start a conversation'), findsNothing);
        expect(find.text('No rooms live right now'), findsNothing);
        fail = false;
        await t.tap(find.text('Try again'));
        await flush(t);
        expect(reads, 2);
        expect(find.text('Fixture unavailable'), findsNothing);
        expect(t.takeException(), isNull);
      }, (_) async { reads++; return reply(fail ? {'message': 'Fixture unavailable'} : {'data': []}, fail ? 503 : 200); });
    });
  }

  testWidgets('outgoing call avatar represents the conversation, not the current caller', (t) async {
    await withSession(t, (s) async {
      await t.pumpWidget(app(CallsPage(session: s)));
      await flush(t);
      expect(t.widget<Avatar>(find.byType(Avatar)).user!['name'], 'Asha Gurung');
      expect(find.text('Asha Gurung'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, (_) async => reply({'data': [
      {'public_id': 'call', 'conversation_id': 'chat', 'title': 'Asha Gurung', 'caller': {'username': 'me', 'name': 'Current member'}, 'direction': 'outgoing', 'kind': 'voice', 'status': 'ended', 'duration_s': 185, 'created_at': '2026-11-16T14:00:00Z'},
    ]}));
  });

  testWidgets('archive selection ignores a late inbox response', (t) async {
    final inbox = Completer<http.Response>();
    await withSession(t, (s) async {
      await t.pumpWidget(app(ChatsPage(session: s)));
      await t.pump();
      await t.tap(find.byTooltip('More'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Archived chats'));
      await flush(t);
      expect(find.text('No archived chats'), findsOneWidget);
      inbox.complete(reply({'data': [{'public_id': 'old', 'title': 'Stale inbox'}]}));
      await flush(t);
      expect(find.text('Stale inbox'), findsNothing);
      expect(find.text('No archived chats'), findsOneWidget);
    }, (r) async => r.url.queryParameters['archived'] == '1' ? reply({'data': []}) : inbox.future);
  });

  testWidgets('room creation requires a meaningful title and cancel sends nothing', (t) async {
    var writes = 0;
    await withSession(t, (s) async {
      await t.pumpWidget(app(RoomsPage(session: s)));
      await flush(t);
      await t.tap(find.widgetWithText(FilledButton, 'Go live').first);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed, isNull);
      await t.enterText(find.byType(TextField), '  ');
      await t.pump();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed, isNull);
      await t.enterText(find.byType(TextField), 'Community music');
      await t.pump();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed, isNotNull);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(writes, 0);
      expect(t.takeException(), isNull);
    }, (r) async { if (r.method != 'GET') writes++; return reply({'data': []}); });
  });

  for (final action in ['Accept', 'Decline']) {
    testWidgets('failed incoming $action stays on ring screen, allows retry, and suppresses duplicate taps', (t) async {
      final pending = Completer<http.Response>();
      var actions = 0;
      var tokens = 0;
      await withSession(t, (s) async {
        await t.pumpWidget(app(IncomingCallPage(session: s, call: {'public_id': 'call', 'conversation_id': 'convo', 'title': 'Fixture', 'kind': 'voice', 'caller': {'username': 'caller'}})));
        await t.tap(find.byTooltip(action));
        await t.pump();
        await t.tap(find.byTooltip(action));
        await t.pump();
        expect(actions, 1);
        pending.complete(reply({'message': 'Call update failed'}, 503));
        await flush(t);
        expect(find.text('Call update failed'), findsOneWidget);
        expect(find.byType(IncomingCallPage), findsOneWidget);
        expect(find.byType(CallPage), findsNothing);
        expect(tokens, 0);
        expect(t.widget<IconButton>(find.byType(IconButton).at(action == 'Accept' ? 1 : 0)).onPressed, isNotNull);
        await t.tap(find.byTooltip(action));
        await flush(t);
        expect(actions, 2);
        expect(t.takeException(), isNull);
      }, (r) async { if (r.url.path.endsWith('/action')) { actions++; return pending.future; } tokens++; return reply({}); });
    });
  }
}

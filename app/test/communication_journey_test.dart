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
import 'package:sanjaal/main.dart' show buildTheme, HomeShell;
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
  testWidgets('confirmed inbox settings force fresh data past an older pending poll',(t)async{
    final old=Completer<http.Response>();var reads=0,writes=0;
    Map<String,dynamic> row(String title)=>{'public_id':'chat','title':title};
    await withSession(t,(s)async{
      await t.pumpWidget(app(ChatsPage(session:s)));await flush(t);await t.pump(const Duration(seconds:12));await flush(t);expect(reads,2);
      await t.longPress(find.text('Community music'));await t.pumpAndSettle();await t.tap(find.text('Pin to top'));await flush(t);expect(writes,1);expect(reads,3);expect(find.text('Updated conversation'),findsOneWidget);
      old.complete(reply({'data':[row('Stale conversation')]}));await flush(t);expect(find.text('Stale conversation'),findsNothing);expect(find.text('Updated conversation'),findsOneWidget);expect(t.takeException(),isNull);
    },(r)async{if(r.method=='PATCH'){writes++;return reply({});}reads++;return reads==2?old.future:reply({'data':[row(reads==1?'Community music':'Updated conversation')]});});
  });

  testWidgets('slow inbox polling does not overlap while current list is pending',(t)async{
    final pending=Completer<http.Response>();var reads=0;
    await withSession(t,(s)async{
      await t.pumpWidget(app(ChatsPage(session:s)));await flush(t);await t.pump(const Duration(seconds:36));await flush(t);expect(reads,1);
      pending.complete(reply({'data':[]}));await flush(t);expect(find.text('Start a conversation'),findsOneWidget);expect(t.takeException(),isNull);
    },(_)async{reads++;return pending.future;});
  });
  testWidgets('malformed inbox data retries without offering a broken chat destination',(t)async{
    var reads=0;
    await withSession(t,(s)async{
      await t.pumpWidget(app(ChatsPage(session:s)));await flush(t);expect(find.text('Chats could not be loaded.'),findsOneWidget);expect(find.text('Start a conversation'),findsNothing);
      await t.tap(find.text('Try again'));await flush(t);expect(find.text('Community music'),findsOneWidget);expect(t.takeException(),isNull);
    },(_)async=>reply({'data':++reads==1?[{'title':'Missing identity'}]:[{'public_id':'chat','title':'Community music'}]}));
  });
  testWidgets('failed inbox refresh retains content and has an explicit retry',(t)async{
    var reads=0;
    await withSession(t,(s)async{
      await t.pumpWidget(app(ChatsPage(session:s)));await flush(t);
      await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();await flush(t);
      expect(find.text('Community music'),findsOneWidget);expect(find.text('Shared a post'),findsOneWidget);expect(find.text('Could not refresh.'),findsOneWidget);
      await t.tap(find.text('Try again'));await flush(t);expect(reads,3);expect(find.text('Could not refresh.'),findsNothing);expect(t.takeException(),isNull);
    },(_)async=>++reads==2?reply({'message':'Temporary failure'},503):reply({'data':[{'public_id':'chat','title':'Community music','last_message':{'kind':'post','created_at':'2026-11-17T00:00:00Z'}}]}));
  });

  for(final page in ['calls','rooms']){
    final row=page=='calls'?{'public_id':'call','conversation_id':'chat','title':'Asha Gurung','caller':{'username':'asha'},'direction':'incoming','kind':'voice','status':'ended','duration_s':125,'created_at':'2026-11-17T00:00:00Z'}:{'public_id':'room','title':'Community music','host_name':'Asha Gurung'};
    testWidgets('$page malformed initial read is retryable without routing unknown identities',(t)async{
      var reads=0;
      await withSession(t,(session)async{
        await t.pumpWidget(app(page=='calls'?CallsPage(session:session):RoomsPage(session:session)));await flush(t);
        expect(find.text(page=='calls'?'Calls could not be loaded.':'Rooms could not be loaded.'),findsOneWidget);expect(t.takeException(),isNull);
        await t.tap(find.text('Try again'));await flush(t);expect(find.text(page=='calls'?'Asha Gurung':'Community music'),findsOneWidget);
      },(_)async=>reply({'data':++reads==1?[{'title':'Malformed'}]:[row]}));
    });
    testWidgets('$page refresh keeps rows, offers retry and suppresses duplicate reads',(t)async{
      var reads=0;final pending=Completer<http.Response>();
      await withSession(t,(session)async{
        await t.pumpWidget(app(page=='calls'?CallsPage(session:session):RoomsPage(session:session)));await flush(t);
        final refresh=t.widget<RefreshIndicator>(find.byType(RefreshIndicator));final first=refresh.onRefresh();await refresh.onRefresh();await flush(t);expect(reads,2);
        pending.complete(reply({'message':'Temporary failure'},503));await first;await flush(t);
        expect(find.text(page=='calls'?'Asha Gurung':'Community music'),findsOneWidget);expect(find.text('Could not refresh.'),findsOneWidget);
        await t.tap(find.text('Try again'));await flush(t);expect(reads,3);expect(find.text('Could not refresh.'),findsNothing);expect(t.takeException(),isNull);
      },(_)async=>++reads==2?pending.future:reply({'data':[row]}));
    });
  }

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
        expect(find.text('Could not load this.'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
        expect(find.text('Start a conversation'), findsNothing);
        expect(find.text('No rooms live right now'), findsNothing);
        fail = false;
        await t.tap(find.text('Try again'));
        await flush(t);
        expect(reads, 2);
        expect(find.text('Could not load this.'), findsNothing);
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

  testWidgets('incoming-call polling does not overlap a slow request', (t) async {
    final pending = Completer<http.Response>();
    var incomingReads = 0;
    await withSession(t, (s) async {
      await t.pumpWidget(app(HomeShell(session: s)));
      await flush(t);
      await t.pump(const Duration(seconds: 5));
      await flush(t);
      expect(incomingReads, 1);
      await t.pump(const Duration(seconds: 10));
      await flush(t);
      expect(incomingReads, 1, reason: 'do not stack polls or competing ring screens on a slow connection');
      pending.complete(reply({'data': []}));
      await flush(t);
      await t.pump(const Duration(seconds: 5));
      await flush(t);
      expect(incomingReads, 2);
      expect(t.takeException(), isNull);
    }, (r) async {
      if (r.url.path.endsWith('/calls/incoming')) { incomingReads++; return pending.future; }
      if (r.url.path.endsWith('/wallet')) return reply({'balance': 0, 'entries': [], 'topup': {}});
      return reply({'data': [], 'next_cursor': null, 'unread_messages': 0});
    });
  });

  testWidgets('call media controls are disabled while changing native state, end stays available', (t) async {
    var ended = false;
    await t.pumpWidget(app(CallView(
      title: 'Fixture', status: 'Connecting...', failed: false, video: true,
      muted: false, camOn: false, tiles: const [], controlsBusy: true,
      onMute: () => fail('microphone must be disabled'),
      onCamera: () => fail('camera must be disabled'), onEnd: () => ended = true,
    )));
    expect(t.widget<Text>(find.text('Fixture')).style?.color, Colors.white, reason: 'call header must stay readable on its black surface in the light theme');
    final buttons = t.widgetList<IconButton>(find.byType(IconButton)).toList();
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNull);
    expect(buttons[2].onPressed, isNotNull);
    await t.tap(find.byTooltip('End call'));
    expect(ended, isTrue);
    await t.pumpWidget(const SizedBox());
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
    testWidgets('uncertain incoming $action checks exact state without repeating the action', (t) async {
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
        expect(find.text('Call status is unknown.'), findsOneWidget);
        expect(find.byType(IncomingCallPage), findsOneWidget);
        expect(find.byType(CallPage), findsNothing);
        expect(tokens, 0);
        expect(find.byTooltip('Accept'), findsNothing);
        expect(find.byTooltip('Decline'), findsNothing);
        await t.tap(find.text('Check call status'));
        await flush(t);
        expect(actions, 1);
        expect(t.takeException(), isNull);
      }, (r) async { if (r.url.path.endsWith('/action')) { actions++; return pending.future; } if (r.method == 'GET' && r.url.path.endsWith('/calls/call')) return reply({}, 503); tokens++; return reply({}); });
    });
  }
}

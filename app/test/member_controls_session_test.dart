// Synthetic settings only. No live account changes.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/member_controls_page.dart';
http.Response reply(Object value) => http.Response(jsonEncode(value),200);
Object controls([int revision=4]) => {'controls':{'revision':revision,'comments_from':'following','share_to_chat':false}};
Future<void> flush(WidgetTester t) async { await t.pump(); await t.pump(const Duration(milliseconds:400)); await t.pump(); }
void locked(WidgetTester t) {
  expect(find.byType(SwitchListTile),findsNothing);
  expect(t.widget<TextButton>(find.widgetWithText(TextButton,'Save')).onPressed,isNull);
  expect(find.text("Sign in again to view this account's settings."),findsOneWidget);
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final same in [false,true]) for (final stage in ['loaded choices','pending read','pending save']) {
    testWidgets('privacy settings permanently retire $stage on ${same?'same':'other'} member login',(t) async {
      final pending=Completer<http.Response>(); var reads=0,writes=0; String owner='a';
      await http.runWithClient(() async {
        final s=Session(); await s.login('fixture','not-a-password');
        await t.pumpWidget(MaterialApp(home:MemberControlsPage(session:s))); await flush(t);
        if(stage!='pending read') { await t.tap(find.text('Nobody else')); await flush(t); }
        if(stage=='pending save') { await t.tap(find.text('Save')); await flush(t); expect(writes,1); }
        if(!same)owner='b'; await s.login('replacement','not-a-password'); await flush(t); locked(t);
        if(stage=='pending read' || stage=='pending save') { pending.complete(reply(controls(5))); await flush(t); }
        // Returning to the old member must not revive a retired route.
        owner='a'; await s.login('returning','not-a-password'); await flush(t); locked(t);
        expect(find.text('Settings saved.'),findsNothing);
        expect(t.widget<TextButton>(find.widgetWithText(TextButton,'Reload current settings')).onPressed,isNull);
        expect(reads,1); expect(writes,stage=='pending save'?1:0); expect(t.takeException(),isNull);
        await t.pumpWidget(const SizedBox());
      },()=>MockClient((r)async {
        if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
        if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
        if(r.method=='PATCH'){writes++;return pending.future;}
        reads++; return stage=='pending read'?pending.future:reply(controls());
      }));
    });
  }
  testWidgets('same owner map restoration cannot revive privacy controls',(t)async {
    var writes=0;
    await http.runWithClient(()async {
      final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:MemberControlsPage(session:s)));await flush(t);
      await t.tap(find.text('Nobody else'));await flush(t);
      s.user={'public_id':'b'};s.notifyListeners();await flush(t);locked(t);
      s.user={'public_id':'a'};s.notifyListeners();await flush(t);locked(t);expect(writes,0);
      await t.pumpWidget(const SizedBox());
    },()=>MockClient((r)async {
      if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
      if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'aaa'}});
      if(r.method=='PATCH')writes++;return reply(controls());
    }));
  });
  testWidgets('new Session object with same member and generation retires privacy controls',(t)async {
    await http.runWithClient(()async {
      final a=Session(),b=Session();await a.login('fixture','not-a-password');await b.login('fixture','not-a-password');expect(a.generation,b.generation);
      await t.pumpWidget(MaterialApp(home:MemberControlsPage(session:a)));await flush(t);await t.tap(find.text('Nobody else'));await flush(t);
      await t.pumpWidget(MaterialApp(home:MemberControlsPage(session:b)));await flush(t);locked(t);expect(t.takeException(),isNull);
      await t.pumpWidget(const SizedBox());
    },()=>MockClient((r)async=>r.url.path.endsWith('/oauth/token')?reply({'access_token':'fixture','expires_in':3600}):r.url.path.endsWith('/auth/me')?reply({'user':{'public_id':'a','username':'aaa'}}):reply(controls())));
  });
}

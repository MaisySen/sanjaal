// Synthetic discovery routes only, no production reads or writes.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/notifications_page.dart';
import 'package:sanjaal/search_page.dart';
http.Response reply(Object body) => http.Response(jsonEncode(body),200);
Future<void> flush(WidgetTester t) async { await t.pump(); await t.pump(const Duration(milliseconds:450)); await t.pump(); }
Object rows(String page) => page=='activity'
  ? {'data':[{'type':'comment','actor':'privateactor','text':'Private activity detail','post_id':'private-post','created_at':'2026-11-21T00:00:00Z'}]}
  : {'users':[{'public_id':'private-person','username':'privateactor','name':'Private search result'}],'hashtags':['privatequery']};
void retired() {
  expect(find.textContaining('another signed-in session'),findsOneWidget);
  expect(find.textContaining('Private activity detail'),findsNothing);
  expect(find.text('Private search result'),findsNothing);
  expect(find.byType(TextField),findsNothing);
  expect(find.byTooltip('Refresh'),findsNothing);
}
void main() {
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final same in [false,true]) for(final page in ['activity','search']) for(final pending in [false,true]) {
  testWidgets('$page retires ${pending?'pending':'loaded'} content after ${same?'same':'other'} member login',(t)async {
   var reads=0,writes=0;String owner='a';final response=Completer<http.Response>();
   await http.runWithClient(()async {
    final s=Session();await s.login('fixture','not-a-password');
    await t.pumpWidget(MaterialApp(home:page=='activity'?NotificationsPage(session:s):SearchPage(session:s)));
    if(page=='search')await t.enterText(find.byType(TextField),'private query');await flush(t);expect(reads,1);
    if(!pending)expect(find.textContaining(page=='activity'?'Private activity detail':'Private search result'),findsOneWidget);
    if(!same)owner='b';await s.login('replacement','not-a-password');await flush(t);retired();
    if(pending){response.complete(reply(rows(page)));await flush(t);retired();}
    owner='a';await s.login('returning','not-a-password');await flush(t);retired();
    expect(reads,1);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
   },()=>MockClient((r)async {
    if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
    if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
    if(r.method!='GET')writes++;reads++;return pending?response.future:reply(rows(page));
   }));
  });
 }
 for(final same in [false,true]) {
  testWidgets('search cancels queued debounce before ${same?'same':'other'} member login',(t)async {
   var reads=0;String owner='a';
   await http.runWithClient(()async {
    final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:SearchPage(session:s)));
    await t.enterText(find.byType(TextField),'private queued query');await t.pump(const Duration(milliseconds:100));expect(reads,0);
    if(!same)owner='b';await s.login('replacement','not-a-password');await flush(t);retired();expect(reads,0);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());
   },()=>MockClient((r)async {
    if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
    if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
    reads++;return reply(rows('search'));
   }));
  });
 }
 for(final page in ['activity','search']) {
  testWidgets('$page retires replacement Session object with same member and epoch',(t)async {
   await http.runWithClient(()async {
    final a=Session(),b=Session();await a.login('fixture','not-a-password');await b.login('fixture','not-a-password');expect(a.generation,b.generation);
    Widget screen(Session s)=>MaterialApp(home:page=='activity'?NotificationsPage(session:s):SearchPage(session:s));
    await t.pumpWidget(screen(a));if(page=='search')await t.enterText(find.byType(TextField),'private query');await flush(t);
    await t.pumpWidget(screen(b));await flush(t);retired();expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
   },()=>MockClient((r)async=>r.url.path.endsWith('/oauth/token')?reply({'access_token':'fixture','expires_in':3600}):r.url.path.endsWith('/auth/me')?reply({'user':{'public_id':'a','username':'aaa'}}):reply(rows(page))));
  });
 }
}

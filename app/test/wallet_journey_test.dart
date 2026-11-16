import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/wallet_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';
http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type':'application/json; charset=utf-8'});
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25))); await t.pump(); await t.pump(const Duration(milliseconds: 400)); }
Future<void> fixture(WidgetTester t, Widget Function(Session) page, Future<void> Function() run, {Future<http.Response> Function(http.Request)? respond, Brightness brightness = Brightness.light, double scale = 1, String language = 'en', bool intents = true, double keyboard = 0}) async {
  SharedPreferences.setMockInitialValues({});
  prefs.lang = language; addTearDown(() => prefs.lang = 'en');
  await http.runWithClient(() async {
    final s = Session(); await s.login('fixture','not-a-password');
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('review'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness, fontFamily: 'Roboto', fontFamilyFallback: ['NotoDev']), builder: (c,w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: keyboard)), child: w!), home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => page(s))), child: const Text('Create fixture')))))));
    await t.tap(find.text('Create fixture')); await flush(t);
    await run();
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return json({'access_token':'fixture','expires_in':3600});
    if (r.method=='GET' && r.url.path.endsWith('/auth/me')) return json({'features':{'polls':true,'upload_intents':intents},'user':{'public_id':'me','username':'fixture','name':'Fixture Name','bio':'Original bio'}});
    if (respond != null) return respond(r);
    return r.url.path.endsWith('/wallet/withdrawals') ? json({'data':[]}) : json(wallet());
  }));
}

Map<String,dynamic> wallet({int balance=1200,List<Map<String,dynamic>> entries=const[]}) => {'balance':balance,'entries':entries,'topup':{'esewa':false},'cashout':{'available':false,'min':500}};
Future<void> sendForm(WidgetTester t)async{await t.ensureVisible(find.widgetWithText(OutlinedButton,'Send'));await t.tap(find.widgetWithText(OutlinedButton,'Send'));await flush(t);await t.pumpAndSettle();}
Future<void> fillTransfer(WidgetTester t)async{await t.enterText(find.byType(TextFormField).at(0),'asha');await t.enterText(find.byType(TextFormField).at(1),'25');await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);}
Future<void> shot(WidgetTester t,String name) async {await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('review')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());});}
void main(){
  setUpAll(()async{
    for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(p.$2);if(f.existsSync()){final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}
  });

 testWidgets('malformed first load has retry and never invents zero balance',(t)async{
  var reads=0;await fixture(t,(s)=>WalletPage(session:s),()async{expect(find.text('Wallet could not be loaded.'),findsOneWidget);expect(find.text('0'),findsNothing);await t.tap(find.text('Try again'));await flush(t);expect(find.text('1200'),findsOneWidget);expect(t.takeException(),isNull);},respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==1?http.Response('malformed',200):json(wallet()));
 });
 testWidgets('failed refresh retains real last balance but disables mutations until retry',(t)async{
  var reads=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();await flush(t);expect(find.text('1200'),findsOneWidget);expect(find.text('Showing the last loaded balance. Refresh before making changes.'),findsOneWidget);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
   await t.tap(find.text('Try again'));await flush(t);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNotNull);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==2?json({'message':'Fixture unavailable'},503):json(wallet()));
 });
 testWidgets('out-of-order wallet refresh cannot replace a newer balance',(t)async{
  final pending=Completer<http.Response>();var reads=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   final refresh=t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
   final older=refresh();await flush(t);final newer=refresh();await flush(t);await newer;expect(find.text('900'),findsOneWidget);
   pending.complete(json(wallet(balance:700)));await older;await flush(t);expect(find.text('900'),findsOneWidget);expect(find.text('700'),findsNothing);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==2?pending.future:json(wallet(balance:reads==1?1200:900)));
 });
 testWidgets('secondary withdrawal error is visible and independently recoverable',(t)async{
  var secondary=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   expect(find.text('Cash-out history could not be loaded.'),findsOneWidget);await t.ensureVisible(find.text('Retry cash-out history'));await t.tap(find.text('Retry cash-out history'));await flush(t);expect(find.text('Cash-out history could not be loaded.'),findsNothing);expect(find.text('1200'),findsOneWidget);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?(++secondary==1?json({'message':'Unavailable'},503):json({'data':[]})):json(wallet()));
 });
 testWidgets('transfer validates locally before making a request',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   await sendForm(t);await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);expect(find.text('Required'),findsOneWidget);expect(writes,0);
   await t.enterText(find.byType(TextFormField).at(0),'asha');await t.enterText(find.byType(TextFormField).at(1),'1201');await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);expect(find.text('Enter a whole coin amount within your balance.'),findsOneWidget);expect(writes,0);
   await t.tap(find.text('Cancel'));await t.pumpAndSettle();expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST')writes++;return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 testWidgets('pending transfer freezes all wallet actions and snapshots one request',(t)async{
  final pending=Completer<http.Response>();var writes=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   final original=t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed!;await sendForm(t);await fillTransfer(t);expect(writes,1);original();await flush(t);expect(writes,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
   pending.complete(json({'balance':1175}));await flush(t);await t.pumpAndSettle();expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNotNull);expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST'){writes++;expect(jsonDecode(r.body),{'username':'asha','amount':25});return pending.future;}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 for(final rejected in [true,false]){
 testWidgets('transfer ${rejected?'explicit rejection permits correction':'ambiguous outcome blocks repeat in this wallet'}',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s),()async{
   await sendForm(t);await fillTransfer(t);await t.pumpAndSettle();expect(writes,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,rejected?isNotNull:isNull);if(!rejected){expect(find.text('Transfer result unconfirmed. Check Activity before sending again.'),findsWidgets);await shot(t,'wallet_transfer_unknown');}expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST'){writes++;return json({'message':'Fixture rejected'},rejected?422:503);}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });}
 for(final write in [false,true]){
 testWidgets('forced disposal during wallet ${write?'transfer':'read'} ignores late response',(t)async{
  final pending=Completer<http.Response>();await fixture(t,(s)=>WalletPage(session:s),()async{if(write){await sendForm(t);await fillTransfer(t);}await t.pumpWidget(const SizedBox());pending.complete(write?json({'balance':1175}):json(wallet()));await flush(t);expect(t.takeException(),isNull);},respond:(r)async=>r.method=='POST'||!write&&!r.url.path.endsWith('/withdrawals')?pending.future:r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet()));
 });}
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){for(final scale in [1.0,1.8]){
 testWidgets('wallet honest unavailable and activity $lang ${mode.name} $scale',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s),()async{
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,lang=='en'?'Add coins':'सिक्का थप्नुहोस्')).onPressed,isNull);expect(t.takeException(),isNull);await shot(t,'wallet_overview_${lang}_${mode.name}_${scale==1?'normal':'large'}');
   final history=find.text(lang=='en'?'Your coin history appears here.':'तपाईंको सिक्काको विवरण यहाँ देखिन्छ।');await t.scrollUntilVisible(history,200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();expect(t.getBottomRight(history).dy,lessThanOrEqualTo(640));expect(t.takeException(),isNull);await shot(t,'wallet_activity_${lang}_${mode.name}_${scale==1?'normal':'large'}');
  },brightness:mode,scale:scale,language:lang);
 });}}}
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){
 testWidgets('wallet transfer dialog large text and keyboard $lang ${mode.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s),()async{
   final action=find.widgetWithText(OutlinedButton,lang=='en'?'Send':'पठाउनुहोस्');await t.scrollUntilVisible(action,150,scrollable:find.byType(Scrollable).last);await t.tap(action);await flush(t);await t.pumpAndSettle();
   expect(find.byType(AlertDialog),findsOneWidget);expect(t.takeException(),isNull);await shot(t,'wallet_send_${lang}_${mode.name}');
   final amount=find.byType(TextFormField).at(1);await Scrollable.ensureVisible(t.element(amount), alignment: 0.5);await t.pumpAndSettle();expect(t.getBottomRight(amount).dy,lessThanOrEqualTo(400));await shot(t,'wallet_send_amount_${lang}_${mode.name}');
   final note=find.byType(TextFormField).last;await Scrollable.ensureVisible(t.element(note), alignment: 0.5);await t.pumpAndSettle();expect(t.getBottomRight(note).dy,lessThanOrEqualTo(400));
   final cancel=find.widgetWithText(TextButton,lang=='en'?'Cancel':'रद्द');await t.ensureVisible(cancel);await t.tap(cancel);await t.pumpAndSettle();expect(t.takeException(),isNull);
  },brightness:mode,scale:1.8,language:lang,keyboard:240);
 });
 testWidgets('wallet populated history and long balance stays readable $lang ${mode.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s),()async{
   expect(t.takeException(),isNull);await shot(t,'wallet_balance_long_${lang}_${mode.name}');
   final item=find.textContaining('@long_fixture_member');await t.scrollUntilVisible(item,200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();expect(find.text('+100000'),findsOneWidget);expect(t.takeException(),isNull);await shot(t,'wallet_history_${lang}_${mode.name}');
  },brightness:mode,scale:1.8,language:lang,respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet(balance:123456789,entries:[{'kind':'transfer_in','counterparty':'long_fixture_member','amount':100000,'note':'Fixture history note','created_at':'2026-11-16T00:00:00Z'}])));
 });
 }}

}

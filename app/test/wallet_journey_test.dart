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
import 'package:sanjaal/wallet_transfer_store.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:shared_preferences/shared_preferences.dart';
// Fake persistence adapter for offline journeys only, not device keystore evidence.
class FixtureTransferStore extends WalletTransferStore {
 const FixtureTransferStore();
 @override
 Future<String?> read(String key)async=>(await SharedPreferences.getInstance()).getString(key);
 @override
 Future<void> write(String key,String value)async{if(!await (await SharedPreferences.getInstance()).setString(key,value))throw StateError('fixture write failed');}
 @override
 Future<void> remove(String key)async{if(!await (await SharedPreferences.getInstance()).remove(key))throw StateError('fixture remove failed');}
}
class FaultTransferStore extends FixtureTransferStore {
 FaultTransferStore({this.failWrite=false,this.failRemove=false,this.delay});
 final bool failWrite, failRemove;
 final Completer<void>? delay;
 @override
 Future<void> write(String key,String value)async{if(failWrite)throw StateError('fixture write failure');await super.write(key,value);if(delay!=null)await delay!.future;}
 @override
 Future<void> remove(String key)async{if(failRemove)throw StateError('fixture remove failure');await super.remove(key);}
}
http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type':'application/json; charset=utf-8'});
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25))); await t.pump(); await t.pump(const Duration(milliseconds: 400)); }
Future<void> fixture(WidgetTester t, Widget Function(Session) page, Future<void> Function() run, {Future<http.Response> Function(http.Request)? respond, Brightness brightness = Brightness.light, double scale = 1, String language = 'en', bool intents = true, double keyboard = 0, Map<String,Object> stored = const {}}) async {
  SharedPreferences.setMockInitialValues(stored);
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

Map<String,dynamic> wallet({int balance=1200,List<Map<String,dynamic>> entries=const[]}) => {'balance':balance,'transfer_replay':true,'transfers_available':true,'entries':entries,'topup':{'esewa':false},'cashout':{'available':false,'min':500}};
Future<void> sendForm(WidgetTester t)async{await t.ensureVisible(find.widgetWithText(OutlinedButton,'Send'));await t.tap(find.widgetWithText(OutlinedButton,'Send'));await flush(t);await t.pumpAndSettle();}
Future<void> fillTransfer(WidgetTester t)async{await t.enterText(find.byType(TextFormField).at(0),'asha');await t.enterText(find.byType(TextFormField).at(1),'25');await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);await t.pumpAndSettle();await t.tap(find.widgetWithText(FilledButton,'Confirm send'));await flush(t);}
Future<void> shot(WidgetTester t,String name) async {await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('review')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());});}
void main(){
  setUpAll(()async{
    for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(p.$2);if(f.existsSync()){final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}
  });

 testWidgets('malformed first load has retry and never invents zero balance',(t)async{
  var reads=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{expect(find.text('Wallet could not be loaded.'),findsOneWidget);expect(find.text('0'),findsNothing);await t.tap(find.text('Try again'));await flush(t);expect(find.text('1200'),findsOneWidget);expect(t.takeException(),isNull);},respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==1?http.Response('malformed',200):json(wallet()));
 });
 testWidgets('failed refresh retains real last balance but disables mutations until retry',(t)async{
  var reads=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();await flush(t);expect(find.text('1200'),findsOneWidget);expect(find.text('Showing the last loaded balance. Refresh before making changes.'),findsOneWidget);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
   await t.tap(find.text('Try again'));await flush(t);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNotNull);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==2?json({'message':'Fixture unavailable'},503):json(wallet()));
 });
 testWidgets('out-of-order wallet refresh cannot replace a newer balance',(t)async{
  final pending=Completer<http.Response>();var reads=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   final refresh=t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
   final older=refresh();await flush(t);final newer=refresh();await flush(t);await newer;expect(find.text('900'),findsOneWidget);
   pending.complete(json(wallet(balance:700)));await older;await flush(t);expect(find.text('900'),findsOneWidget);expect(find.text('700'),findsNothing);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):++reads==2?pending.future:json(wallet(balance:reads==1?1200:900)));
 });
 testWidgets('secondary withdrawal error is visible and independently recoverable',(t)async{
  var secondary=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   expect(find.text('Cash-out history could not be loaded.'),findsOneWidget);await t.ensureVisible(find.text('Retry cash-out history'));await t.tap(find.text('Retry cash-out history'));await flush(t);expect(find.text('Cash-out history could not be loaded.'),findsNothing);expect(find.text('1200'),findsOneWidget);
  },respond:(r)async=>r.url.path.endsWith('/withdrawals')?(++secondary==1?json({'message':'Unavailable'},503):json({'data':[]})):json(wallet()));
 });
 testWidgets('transfer validates locally before making a request',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   await sendForm(t);await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);expect(find.text('Required'),findsOneWidget);expect(writes,0);
   await t.enterText(find.byType(TextFormField).at(0),'asha');await t.enterText(find.byType(TextFormField).at(1),'1201');await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);expect(find.text('Enter a whole coin amount within your balance.'),findsOneWidget);expect(writes,0);
   await t.tap(find.text('Cancel'));await t.pumpAndSettle();expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST')writes++;return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 testWidgets('pending transfer freezes all wallet actions and snapshots one request',(t)async{
  final pending=Completer<http.Response>();var writes=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   final original=t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed!;await sendForm(t);await fillTransfer(t);expect(writes,1);original();await flush(t);expect(writes,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
   final stored=(await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me')!;pending.complete(json({'balance':1175,'transfer':{'status':'completed','client_id':jsonDecode(stored)['client_id'],'amount':25,'public_id':'fixture-receipt'}}));await flush(t);await t.pumpAndSettle();expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNotNull);expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST'){writes++;expect((jsonDecode(r.body) as Map)['username'],'asha');expect((jsonDecode(r.body) as Map)['amount'],25);return pending.future;}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 for(final rejected in [true,false]){
 testWidgets('transfer ${rejected?'explicit rejection permits correction':'ambiguous outcome blocks repeat in this wallet'}',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   await sendForm(t);await fillTransfer(t);await t.pumpAndSettle();expect(writes,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,rejected?isNotNull:isNull);if(!rejected){expect(find.text('Original transfer needs confirmation.'),findsOneWidget);await shot(t,'wallet_transfer_unknown');}expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST'){writes++;return json({'message':'Fixture rejected'},rejected?422:503);}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });}
 for(final write in [false,true]){
 testWidgets('forced disposal during wallet ${write?'transfer':'read'} ignores late response',(t)async{
  final pending=Completer<http.Response>();await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{if(write){await sendForm(t);await fillTransfer(t);}await t.pumpWidget(const SizedBox());pending.complete(write?json({'balance':1175}):json(wallet()));await flush(t);expect(t.takeException(),isNull);},respond:(r)async=>r.method=='POST'||!write&&!r.url.path.endsWith('/withdrawals')?pending.future:r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet()));
 });}
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){for(final scale in [1.0,1.8]){
 testWidgets('wallet honest unavailable and activity $lang ${mode.name} $scale',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,lang=='en'?'Add coins':'सिक्का थप्नुहोस्')).onPressed,isNull);expect(t.takeException(),isNull);await shot(t,'wallet_overview_${lang}_${mode.name}_${scale==1?'normal':'large'}');
   final history=find.text(lang=='en'?'Your coin history appears here.':'तपाईंको सिक्काको विवरण यहाँ देखिन्छ।');await t.scrollUntilVisible(history,200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();expect(t.getBottomRight(history).dy,lessThanOrEqualTo(640));expect(t.takeException(),isNull);await shot(t,'wallet_activity_${lang}_${mode.name}_${scale==1?'normal':'large'}');
  },brightness:mode,scale:scale,language:lang);
 });}}}
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){
 testWidgets('wallet transfer dialog large text and keyboard $lang ${mode.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   final action=find.widgetWithText(OutlinedButton,lang=='en'?'Send':'पठाउनुहोस्');await t.scrollUntilVisible(action,150,scrollable:find.byType(Scrollable).last);await t.tap(action);await flush(t);await t.pumpAndSettle();
   expect(find.byType(AlertDialog),findsOneWidget);expect(t.takeException(),isNull);await shot(t,'wallet_send_${lang}_${mode.name}');
   final amount=find.byType(TextFormField).at(1);await Scrollable.ensureVisible(t.element(amount), alignment: 0.5);await t.pumpAndSettle();expect(t.getBottomRight(amount).dy,lessThanOrEqualTo(400));await shot(t,'wallet_send_amount_${lang}_${mode.name}');
   final note=find.byType(TextFormField).last;await Scrollable.ensureVisible(t.element(note), alignment: 0.5);await t.pumpAndSettle();expect(t.getBottomRight(note).dy,lessThanOrEqualTo(400));
   final cancel=find.widgetWithText(TextButton,lang=='en'?'Cancel':'रद्द');await t.ensureVisible(cancel);await t.tap(cancel);await t.pumpAndSettle();expect(t.takeException(),isNull);
  },brightness:mode,scale:1.8,language:lang,keyboard:240);
 });
 testWidgets('wallet populated history and long balance stays readable $lang ${mode.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   expect(t.takeException(),isNull);await shot(t,'wallet_balance_long_${lang}_${mode.name}');
   final item=find.textContaining('@long_fixture_member');await t.scrollUntilVisible(item,200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();expect(find.text('+100000'),findsOneWidget);expect(t.takeException(),isNull);await shot(t,'wallet_history_${lang}_${mode.name}');
  },brightness:mode,scale:1.8,language:lang,respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet(balance:123456789,entries:[{'kind':'transfer_in','counterparty':'long_fixture_member','amount':100000,'note':'Fixture history note','created_at':'2026-11-16T00:00:00Z'}])));
 });
 }}

 for (final language in ['en','ne']) {
 testWidgets('held wallet clearly disables all money actions $language',(t)async{
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
     expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,t_('Add coins'))).onPressed,isNull);
     for(final label in ['Send','Cash out']){
       expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,t_(label))).onPressed,isNull);
     }
     await shot(t,'wallet_hold_${language}_top');
     await t.ensureVisible(find.text(t_('Transfers are unavailable until live verification is complete.')));
     await t.pumpAndSettle();
     await shot(t,'wallet_hold_${language}_notice');
   },language:language,brightness:language=='en'?Brightness.dark:Brightness.light,scale:1.8,
   respond:(r)async {
     expect(r.method,'GET',reason:'held capabilities must not produce a money request');
     if(r.url.path.endsWith('/withdrawals')) return json({'data':[]});
     final held=(jsonDecode(File('test/fixtures/live_wallet_capabilities_20261119.json').readAsStringSync()) as Map<String,dynamic>)..remove('url')..remove('at');
     return json({'balance':0,'entries':[],...held});
   });
 });
 }
 for (final availability in [false, null]) {
 testWidgets('server transfer hold or missing availability cannot enable Send $availability',(t)async{
   await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
     expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);
     expect(find.text('Transfers are unavailable until live verification is complete.'),findsOneWidget);
   },respond:(r)async{
     expect(r.method,'GET',reason:'the held screen must never attempt a transfer');
     if(r.url.path.endsWith('/withdrawals'))return json({'data':[]});
     final data=wallet();
     if(availability==null){data.remove('transfers_available');}else{data['transfers_available']=availability;}
     return json(data);
   });
 });
 }
 testWidgets('unsupported server never permits legacy unkeyed send',(t)async{
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);expect(find.text('Transfers are unavailable until live verification is complete.'),findsOneWidget);},respond:(r)async=>r.url.path.endsWith('/withdrawals')?json({'data':[]}):json({...wallet(),'transfer_replay':false}));
 });
 testWidgets('navigation and fresh session restore only original transfer and same immutable key',(t)async{
  final sent=<Map<String,dynamic>>[];String? persisted;
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   await sendForm(t);await fillTransfer(t);await t.pumpAndSettle();persisted=(await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me');expect(persisted,isNotNull);
   await t.pageBack();await t.pumpAndSettle();await t.tap(find.text('Create fixture'));await flush(t);expect(find.text('Original transfer needs confirmation.'),findsOneWidget);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);expect(sent.length,1);
  },respond:(r)async{if(r.method=='POST'){sent.add((jsonDecode(r.body) as Map).cast<String,dynamic>());return json({'message':'uncertain'},503);}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   expect(find.text('25 coins to @asha'),findsOneWidget);expect(find.text('Original transfer needs confirmation.'),findsOneWidget);expect(sent.length,1);
   await t.ensureVisible(find.text('Retry original transfer'));await t.tap(find.text('Retry original transfer'));await flush(t);await t.pumpAndSettle();expect(sent.length,2);expect(sent[1],sent[0]);expect(find.text('Original transfer needs confirmation.'),findsNothing);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),isNull);
  },stored:{'wallet_transfer_v1_me':persisted!},respond:(r)async{if(r.method=='POST'){final data=(jsonDecode(r.body) as Map).cast<String,dynamic>();sent.add(data);return json({'balance':1175,'transfer':{'status':'completed','client_id':data['client_id'],'amount':data['amount'],'public_id':'fixture-receipt'}});}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet(balance:1175));});
 });
 testWidgets('another member pending transfer is neither displayed replayed nor removed',(t)async{
  final other=jsonEncode({'client_id':'fixture-original-key-other','username':'private_other','amount':7});
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{expect(find.textContaining('private_other'),findsNothing);expect(find.text('Retry original transfer'),findsNothing);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNotNull);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_other'),other);},stored:{'wallet_transfer_v1_other':other});
 });
 testWidgets('corrupt own pending storage fails closed instead of losing uncertain outcome',(t)async{
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{expect(find.text('Pending transfer could not be read. Sending is paused.'),findsOneWidget);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),'not json');},stored:{'wallet_transfer_v1_me':'not json'});
 });
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){
 testWidgets('complete filled transfer form confirmation and refreshed activity $lang ${mode.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);var sent=false;Map<String,dynamic>? payload;
  await fixture(t,(s)=>WalletPage(session:s, transferStore: const FixtureTransferStore()),()async{
   final open=find.widgetWithText(OutlinedButton,lang=='en'?'Send':'पठाउनुहोस्');await t.scrollUntilVisible(open,150,scrollable:find.byType(Scrollable).last);await t.tap(open);await flush(t);await t.pumpAndSettle();
   for(final pair in [(0,'asha'),(1,'25'),(2,'Fixture momo')]){final field=find.byType(TextFormField).at(pair.$1);await Scrollable.ensureVisible(t.element(field),alignment:.5);await t.pumpAndSettle();await t.enterText(field,pair.$2);await flush(t);}
   await shot(t,'wallet_filled_${lang}_${mode.name}');
   final submit=find.widgetWithText(FilledButton,lang=='en'?'Send':'पठाउनुहोस्');await t.ensureVisible(submit);await t.tap(submit);await flush(t);await t.pumpAndSettle();expect(sent,isFalse);expect(find.text(lang=='en'?'25 coins to @asha':'@asha लाई 25 सिक्का'),findsOneWidget);await shot(t,'wallet_review_${lang}_${mode.name}');
   await t.tap(find.widgetWithText(FilledButton,lang=='en'?'Confirm send':'पठाउने पुष्टि गर्नुहोस्'));await flush(t);await t.pumpAndSettle();expect(sent,isTrue);expect(payload!['amount'],25);expect(payload!['username'],'asha');expect(payload!['note'],'Fixture momo');expect(payload!['client_id'],matches(RegExp(r'^[a-f0-9]{48}$')));await t.drag(find.byType(ListView),const Offset(0,1500));await t.pumpAndSettle();expect(find.text('1175'),findsOneWidget);
   final entry=find.text(lang=='en'?'To @asha':'@asha लाई');await t.scrollUntilVisible(entry,200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();expect(find.text('-25'),findsOneWidget);expect(t.takeException(),isNull);await t.pump(const Duration(seconds:5));await t.pumpAndSettle();await shot(t,'wallet_confirmed_${lang}_${mode.name}');
  },brightness:mode,scale:1.8,language:lang,keyboard:240,respond:(r)async{if(r.method=='POST'){sent=true;payload=(jsonDecode(r.body) as Map).cast<String,dynamic>();return json({'balance':1175,'transfer':{'status':'completed','client_id':payload!['client_id'],'amount':25,'public_id':'fixture-receipt'}});}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet(balance:sent?1175:1200,entries:sent?[{'kind':'transfer_out','amount':-25,'counterparty':'asha','note':'Fixture momo','created_at':'2026-11-16T00:00:00Z'}]:[]));});
 });}}

 testWidgets('failed persistence never sends a transfer',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s,transferStore:FaultTransferStore(failWrite:true)),()async{await sendForm(t);await fillTransfer(t);await t.pumpAndSettle();expect(writes,0);expect(find.text('Original transfer needs confirmation.'),findsOneWidget);expect(find.text('Transfer was not sent because its details could not be saved.'),findsOneWidget);},respond:(r)async{if(r.method=='POST')writes++;return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 testWidgets('confirmed receipt with failed storage clear cannot permit a fresh send',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s,transferStore:FaultTransferStore(failRemove:true)),()async{await sendForm(t);await fillTransfer(t);await t.pumpAndSettle();expect(writes,1);expect(find.text('Original transfer needs confirmation.'),findsOneWidget);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Send')).onPressed,isNull);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),isNotNull);},respond:(r)async{if(r.method=='POST'){writes++;final b=jsonDecode(r.body);return json({'transfer':{'client_id':b['client_id'],'amount':25,'public_id':'fixture','status':'completed'}});}return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 testWidgets('leaving during persistence keeps original but does not send after disposal',(t)async{
  final gate=Completer<void>();var writes=0;await fixture(t,(s)=>WalletPage(session:s,transferStore:FaultTransferStore(delay:gate)),()async{await sendForm(t);await fillTransfer(t);await t.pumpWidget(const SizedBox());gate.complete();await flush(t);expect(writes,0);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),isNotNull);expect(t.takeException(),isNull);},respond:(r)async{if(r.method=='POST')writes++;return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });
 testWidgets('canceling review does not persist or send',(t)async{
  var writes=0;await fixture(t,(s)=>WalletPage(session:s,transferStore:const FixtureTransferStore()),()async{await sendForm(t);await t.enterText(find.byType(TextFormField).at(0),'asha');await t.enterText(find.byType(TextFormField).at(1),'25');await t.tap(find.widgetWithText(FilledButton,'Send'));await flush(t);await t.pumpAndSettle();expect(find.text('Review transfer'),findsOneWidget);await t.tap(find.text('Cancel'));await t.pumpAndSettle();expect(writes,0);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),isNull);},respond:(r)async{if(r.method=='POST')writes++;return r.url.path.endsWith('/withdrawals')?json({'data':[]}):json(wallet());});
 });

}

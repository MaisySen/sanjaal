// Synthetic responses only, never a live wallet, payment or account.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/wallet_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallet_journey_test.dart' show FixtureTransferStore, wallet, sendForm, flush;

http.Response reply(Object value,[int status=200])=>http.Response(jsonEncode(value),status);
class DelayedStore extends FixtureTransferStore {
 DelayedStore(this.gate);final Completer<void> gate;
 @override Future<void> write(String key,String value)async{await super.write(key,value);await gate.future;}
}
void main(){
 setUpAll(()async{
  Directory('test/renders').createSync(recursive:true);
  for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
   final f=File(p.$2);if(f.existsSync()){final font=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await font.load();}
  }
 });
 setUp((){debugDefaultTargetPlatformOverride=TargetPlatform.iOS;SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});});
 tearDown((){debugDefaultTargetPlatformOverride=null;});
 for(final replacement in ['same member','other member','logout']){
 testWidgets('old wallet transfer confirmation cannot borrow $replacement session',(t)async{
  var account='me',writes=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:WalletPage(session:s,transferStore:const FixtureTransferStore())));await flush(t);
   await sendForm(t);
   await t.enterText(find.byType(TextFormField).at(0),'private_recipient');
   await t.enterText(find.byType(TextFormField).at(1),'25');
   await t.tap(find.widgetWithText(FilledButton,'Send'));await t.pumpAndSettle();
   final staleConfirm=t.widget<FilledButton>(find.widgetWithText(FilledButton,'Confirm send')).onPressed!;
   if(replacement=='logout'){final signingOut=s.logout();await t.pump();await signingOut;}else{if(replacement=='other member')account='other';await s.login('replacement','not-a-password');}
   await t.pump();
   // Invoke the captured callback too: hiding a button is not a send guard.
   staleConfirm();await flush(t);await t.pumpAndSettle();
   expect(writes,0);expect(find.textContaining('private_recipient'),findsNothing);
   expect(find.text('1200'),findsNothing);
   expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:1));
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':account,'username':account}});
   if(r.url.path.endsWith('/devices/remove'))return reply({});
   if(r.method=='POST'){writes++;return reply({'message':'Synthetic rejection'},422);}
   return r.url.path.endsWith('/withdrawals')?reply({'data':[]}):reply(wallet());
  }));
 },timeout:const Timeout(Duration(seconds:60)));
 }
 for(final language in ['en','ne']){
 testWidgets('retired wallet dialog protects private text at large scale $language',(t)async{
  prefs.lang=language;addTearDown(()=>prefs.lang='en');
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('wallet-retired'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:WalletPage(session:s,transferStore:const FixtureTransferStore()))));await flush(t);
   // Choose the button by type and its middle position if translated labels differ.
   await t.ensureVisible(find.byType(OutlinedButton).first);await t.tap(find.byType(OutlinedButton).first);await t.pumpAndSettle();
   await t.enterText(find.byType(TextFormField).first,'private_recipient');
   await s.login('replacement','not-a-password');await t.pumpAndSettle();
   expect(find.textContaining('private_recipient'),findsNothing);expect(find.text('1200'),findsNothing);
   expect(find.byType(TextFormField),findsNothing);expect(t.takeException(),isNull);
   await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('wallet-retired')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/wallet_retired_${language}_1.8.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:1));
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'me','username':'me'}});
   return r.url.path.endsWith('/withdrawals')?reply({'data':[]}):reply(wallet());
  }));
 },timeout:const Timeout(Duration(seconds:60)));
 }
 testWidgets('delayed transfer persistence cannot send after same-member replacement login',(t)async{
  final gate=Completer<void>();var writes=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:WalletPage(session:s,transferStore:DelayedStore(gate))));await flush(t);
   await sendForm(t);await t.enterText(find.byType(TextFormField).at(0),'private_recipient');await t.enterText(find.byType(TextFormField).at(1),'25');
   await t.tap(find.widgetWithText(FilledButton,'Send'));await t.pumpAndSettle();await t.tap(find.widgetWithText(FilledButton,'Confirm send'));await flush(t);
   await s.login('replacement','not-a-password');gate.complete();await flush(t);await t.pumpAndSettle();
   expect(writes,0);expect((await SharedPreferences.getInstance()).getString('wallet_transfer_v1_me'),isNotNull);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:1));
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'me','username':'me'}});
   if(r.method=='POST'){writes++;return reply({'message':'Synthetic rejection'},422);}
   return r.url.path.endsWith('/withdrawals')?reply({'data':[]}):reply(wallet());
  }));
 });

}

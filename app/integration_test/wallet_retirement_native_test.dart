// Native-engine UI check with synthetic HTTP and memory-only credentials/store.
// iOS platform override prevents unrelated Firebase registration traffic. The
// Android engine and native screenshot surface are real; this is not APNs proof.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:sanjaal/wallet_page.dart';
import 'package:sanjaal/wallet_transfer_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTransferStore extends WalletTransferStore {
 const MemoryTransferStore();
 @override Future<String?> read(String key) async => null;
 @override Future<void> write(String key,String value) async { throw StateError('Unexpected persistence'); }
 @override Future<void> remove(String key) async { throw StateError('Unexpected removal'); }
}
void main() {
 final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('native wallet retires private data and safely reopens current account', (t) async {
  debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
  addTearDown(()=>debugDefaultTargetPlatformOverride=null);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  var account='first',writes=0;
  final s=Session(unregisterPush: (_) async {});
  http.Response reply(Object body)=>http.Response(jsonEncode(body),200,headers:{'content-type':'application/json; charset=utf-8'});
  await http.runWithClient(() async {
   await s.login('synthetic','not-a-password');
   for(final language in ['en','ne']) {
    prefs.lang=language;
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:WalletPage(key:ValueKey(language),session:s,transferStore:const MemoryTransferStore())));
    await t.pumpAndSettle();
    expect(find.text(account=='first'?'1200':'777'),findsOneWidget);
    await t.ensureVisible(find.widgetWithText(OutlinedButton,t_('Send')));
    await t.tap(find.widgetWithText(OutlinedButton,t_('Send')));await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first,'private_native_recipient');
    account='replacement';await s.login('synthetic-next','not-a-password');await t.pumpAndSettle();
    expect(find.textContaining('private_native_recipient'),findsNothing);
    expect(find.text('1200'),findsNothing);expect(find.text('777'),findsNothing);
    expect(find.byType(TextFormField),findsNothing);
    if(language=='en') {await binding.convertFlutterSurfaceToImage();await t.pumpAndSettle();}
    await binding.takeScreenshot('wallet_native_retired_$language');
    await t.tap(find.widgetWithText(TextButton,t_('Close')));await t.pumpAndSettle();
    await binding.takeScreenshot('wallet_native_reopen_$language');
    await t.tap(find.widgetWithText(FilledButton,t_('Open current wallet')));await t.pumpAndSettle();
    expect(find.text('777'),findsOneWidget);expect(writes,0);
    await binding.takeScreenshot('wallet_native_current_$language');
    await t.pumpWidget(const SizedBox());await t.pumpAndSettle();
   }
   prefs.lang='en';await s.logout();expect(writes,0);
  },()=>MockClient((r) async {
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'synthetic','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':account,'username':account}});
   if(r.method=='POST'){writes++;return http.Response('{}',422);}
   if(r.url.path.endsWith('/withdrawals'))return reply({'data':[]});
   return reply({'balance':account=='first'?1200:777,'entries':[],'transfer_replay':true,'transfers_available':true,'topup':{'esewa':false},'cashout':{'available':false}});
  }));
  expect(t.takeException(),isNull);
 });
}

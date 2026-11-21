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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/wallet_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallet_journey_test.dart' show FixtureTransferStore, wallet, sendForm, flush;

http.Response reply(Object value,[int status=200])=>http.Response(jsonEncode(value),status);
void main(){
 setUp((){SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});});
 for(final replacement in ['same member','other member']){
 testWidgets('disabled-money wallet never exposes previous balance after $replacement replacement',(t)async{
  var account='me',writes=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:WalletPage(session:s,transferStore:const FixtureTransferStore())));await flush(t);
   expect(find.text('1200'),findsOneWidget);
   if(replacement=='logout'){await t.runAsync(s.logout);}else{if(replacement=='other member')account='other';await s.login('replacement','not-a-password');}
   await t.pump();
   await flush(t);await t.pumpAndSettle();
   expect(writes,0);expect(find.textContaining('private_recipient'),findsNothing);
   expect(find.text('1200'),findsNothing);
   expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:1));
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':account,'username':account}});
   if(r.url.path.endsWith('/devices/remove'))return reply({});
   if(r.method=='POST'){writes++;return reply({'message':'Synthetic rejection'},422);}
   return r.url.path.endsWith('/withdrawals')?reply({'data':[]}):reply({...wallet(),'transfer_replay':false,'transfers_available':false,'topup':{'esewa':false},'cashout':{'available':false}});
  }));
 },timeout:const Timeout(Duration(seconds:60)));
 }
}

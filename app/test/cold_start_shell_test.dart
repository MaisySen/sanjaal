// Synthetic root-to-home sequencing only. No real identity, API or media calls.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object value, [int status = 200]) => http.Response(jsonEncode(value), status);
Map<String,dynamic> bundle() => {
  'feed': {'data': [{'public_id':'cold-post','kind':'post','body':'Cold-start fixture post','author':{'public_id':'other','username':'fixture_other','name':'Other'},'created_at':'2026-11-17T00:00:00Z','media':[],'hashtags':[],'comments_count':0,'likes_count':0}], 'next_cursor':null},
  'stories': {'data':[]}, 'unread_messages':2,
};
Future<void> flush(WidgetTester t) async {
  for (var i=0; i<4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds:30)));
    await t.pump(const Duration(milliseconds:50));
  }
}
void main() {
  for (final failHome in [false,true]) {
    testWidgets('root waits for refreshed identity; ${failHome ? 'bundle failure falls back once' : 'slow bundle is consumed without duplicate reads'}', (t) async {
      SharedPreferences.setMockInitialValues({'onboarded':true});
      FlutterSecureStorage.setMockInitialValues({'refresh_token':'saved-fixture'});
      final token=Completer<http.Response>(), me=Completer<http.Response>(), home=Completer<http.Response>();
      final reads=<String>[];
      await http.runWithClient(() async {
        await t.pumpWidget(const SanjaalApp()); await flush(t);
        final dynamic root=t.state(find.byType(SanjaalApp));
        final s=root.session as Session; s.homeBundleEnabled=true;
        expect(reads,['/oauth/token']); expect(find.byType(HomeShell),findsNothing);
        token.complete(json({'access_token':'fixture-access','refresh_token':'rotated-fixture','expires_in':3600})); await flush(t);
        expect(reads,['/oauth/token','/api/v1/auth/me']); expect(find.byType(HomeShell),findsNothing);
        me.complete(json({'user':{'public_id':'member','username':'fixture','name':'Fixture'},'features':{}})); await flush(t);
        expect(reads,['/oauth/token','/api/v1/auth/me','/api/v1/home']);
        expect(find.byType(HomeShell),findsOneWidget);
        // Real elapsed time is deliberate: the freshness guard uses DateTime.now.
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds:5300)));
        home.complete(failHome ? json({'message':'synthetic unavailable'},503) : json(bundle())); await flush(t);
        final homeReads=reads.where((x)=>x=='/api/v1/home').length;
        expect(homeReads,1);
        if (failHome) {
          for (final p in ['/api/v1/posts','/api/v1/stories','/api/v1/notifications/summary']) {
            expect(reads.where((x)=>x==p).length,1,reason:p);
          }
          expect(reads.length,6);
        } else {
          expect(reads.length,3); expect(find.text('Cold-start fixture post'),findsWidgets);
        }
        expect(t.takeException(),isNull);
        await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds:1));
      },()=>MockClient((r) async {
        reads.add(r.url.path);
        if (r.url.path=='/oauth/token') return token.future;
        expect(r.headers['Authorization'],'Bearer fixture-access');
        switch (r.url.path) {
          case '/api/v1/auth/me': return me.future;
          case '/api/v1/home': return home.future;
          case '/api/v1/posts':
          case '/api/v1/stories': return json({'data':[],'next_cursor':null});
          case '/api/v1/notifications/summary': return json({'unread_messages':0});
          default: throw StateError('Unexpected request ${r.method} ${r.url.path}');
        }
      }));
    });
  }
}

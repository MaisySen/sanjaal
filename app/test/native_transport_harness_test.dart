// Harness boundaries only, not native-device or network-quality proof.
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../integration_test/native_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'refresh_token':'harness-fixture'});
    apiKeepAliveInTests=true;resetApiKeepAlive();
  });
  tearDown(() { apiKeepAliveInTests=false;resetApiKeepAlive(); });
  for (final held in [false,true]) {
    test(held ? 'transport failure holds offline across background reads then reconnects'
        : 'reachable poll clears a manually set offline flag, reproducing old harness race', () async {
      var requests=0;
      final real=MockClient((r) async {
        requests++;
        return http.Response(jsonEncode(r.url.path.endsWith('/oauth/token')
          ? {'access_token':'fixture','expires_in':3600}
          : {'user':{'public_id':'harness-only'},'data':[]}),200);
      });
      final transport=NativeTransport(real:real);
      final s=Session();
      try {
        await http.runWithClient(() async {
          await s.restore();expect(s.user?['public_id'],'harness-only');
          s.setOffline(true);
          if (held) {
            transport.offline=true;await transport.idle();
            final before=requests;
            for (var i=0;i<3;i++) {
              await expectLater(s.call('GET','/calls/incoming'),throwsA(isA<ApiError>()));
              expect(s.offline,isTrue);
            }
            expect(requests,before);expect(transport.rejected,3);
            transport.offline=false;
          }
          await s.call('GET','/calls/incoming');
          expect(s.offline,isFalse);expect(transport.pending,0);
        },()=>transport);
      } finally { transport.dispose(); }
    });
  }
}

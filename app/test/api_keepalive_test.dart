import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

MockClient fixture(String token, List<String> log, String name) => MockClient((r) async {
  if (r.url.path.endsWith('/oauth/token')) return ok({'access_token': token, 'expires_in': 3600});
  log.add('$name ${r.url.path} ${r.headers['Authorization']}');
  return ok({'user': {'public_id': 'member-$token'}, 'data': []});
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'saved-fixture'});
    resetApiKeepAlive();
  });
  tearDown(() { apiKeepAliveInTests = false; resetApiKeepAlive(); });

  test('under test without the switch each zone keeps its own client', () async {
    final log = <String>[];
    final s = Session();
    await http.runWithClient(s.restore, () => fixture('a1', log, 'A'));
    await http.runWithClient(() => s.call('GET', '/x'), () => fixture('a1', log, 'B'));
    expect(log.last, startsWith('B /'));
  });

  test('production path reuses one client across calls and never shares credentials', () async {
    apiKeepAliveInTests = true;
    final log = <String>[];
    final s1 = Session();
    await http.runWithClient(s1.restore, () => fixture('tok-one', log, 'A'));
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'saved-two'});
    final s2 = Session();
    await http.runWithClient(s2.restore, () => fixture('tok-two', log, 'B'));
    await http.runWithClient(() => s1.call('GET', '/one'), () => fixture('tok-one', log, 'C'));
    await http.runWithClient(() => s2.call('GET', '/two'), () => fixture('tok-two', log, 'C'));
    // Every request went through the first client created, and each carried only its own session's token.
    expect(log.where((l) => l.startsWith('C')), isEmpty);
    expect(log.any((l) => l.contains('/one') && l.endsWith('Bearer tok-one')), isTrue);
    expect(log.any((l) => l.contains('/two') && l.endsWith('Bearer tok-two')), isTrue);
    expect(log.any((l) => l.contains('/one') && l.contains('tok-two')), isFalse);
    expect(log.any((l) => l.contains('/two') && l.contains('tok-one')), isFalse);
  });
}

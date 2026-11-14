// Runs the app's real Session client against a live API.
// LIVE_API=https://sanjaal-api.onrender.com/api/v1 flutter test test/live_api_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final live = Platform.environment['LIVE_API'] != null;
  test('register, post, comment, like, chat against the live API', () async {
    SharedPreferences.setMockInitialValues({});
    final n = 'lt${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final a = Session();
    await a.register('$n@example.com', n, 'Sanjaal-Test-9x!');
    expect(a.user!['username'], n);

    Object? rejected;
    try {
      await a.createPost('bad image', image: List<int>.filled(10, 1), mime: 'image/png', filename: 'x.png');
    } catch (e) {
      rejected = e;
    }
    expect(rejected, isA<ApiError>()); // an invalid image is refused

    final ok = await a.createPost('hello from test');
    final id = ok['public_id'] as String;
    final feed = await a.call('GET', '/posts') as Map;
    expect((feed['data'] as List).any((p) => p['public_id'] == id), isTrue);
    final liked = await a.call('POST', '/posts/$id/like') as Map;
    expect(liked['liked'], isTrue);
    await a.call('POST', '/posts/$id/comments', body: {'body': 'nice'});
    final cs = await a.call('GET', '/posts/$id/comments') as Map;
    expect((cs['data'] as List).length, 1);

    final m = 'lu${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final b = Session();
    await b.register('$m@example.com', m, 'Sanjaal-Test-9x!');
    final c = (await a.call('POST', '/conversations', body: {'type': 'direct', 'username': m}) as Map)['conversation'] as Map;
    await a.call('POST', '/conversations/${c['public_id']}/messages', body: {'body': 'namaste', 'client_id': 'k1'});
    final got = await b.call('GET', '/conversations/${c['public_id']}/messages') as Map;
    expect((got['data'] as List).single['body'], 'namaste');
    await a.call('DELETE', '/posts/$id');

    await a.logout();
    expect(a.user, isNull);
  }, skip: live ? false : 'LIVE_API not set', timeout: const Timeout(Duration(minutes: 3)));
}

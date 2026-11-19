// Synthetic HTTP responses only. No real account mutation or media upload.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(jsonEncode(data), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  final file = UploadFile([1, 2, 3], 'image/png', 'synthetic.png');
  for (final operation in ['avatar', 'post', 'story', 'chat']) {
    for (final change in ['logout', 'other account', 'same account new login']) {
      test('$operation rejects late response after $change', () async {
        final pending = Completer<http.Response>();
        final entered = Completer<void>();
        final session = Session();
        var account = 'owner-a';
        var uploadCalls = 0;
        await http.runWithClient(() async {
          await session.login('fixture', 'not-a-password');
          final Future<dynamic> upload = switch (operation) {
            'avatar' => session.uploadAvatar(file),
            'post' => session.createPost('Synthetic', files: [file], intent: 'fixture-post'),
            'story' => session.upload('/stories', file: file, intent: 'fixture-story'),
            _ => session.upload('/conversations/fixture/messages', file: file),
          };
          await entered.future;
          // Attach the expectation before completing the delayed response.
          final rejected = expectLater(upload, throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
          if (change == 'logout') {
            await session.logout();
          } else {
            if (change == 'other account') account = 'owner-b';
            await session.login('replacement', 'not-a-password');
          }
          final expectedUser = session.user == null ? null : Map<String, dynamic>.from(session.user!);
          pending.complete(reply(switch (operation) {
            'avatar' => {'user': {'public_id': 'owner-a', 'name': 'OLD UPLOAD'}},
            'post' => {'post': {'public_id': 'old-post'}},
            'story' => {'story': {'public_id': 'old-story'}},
            _ => {'message': {'public_id': 'old-message'}},
          }, operation == 'avatar' ? 200 : 201));
          await rejected;
          expect(session.user, expectedUser);
          expect(uploadCalls, 1);
        }, () => MockClient((r) async {
          if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture-access', 'expires_in': 3600});
          if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': account, 'username': account}, 'features': {'upload_intents': true}});
          if (r.url.path.endsWith('/devices/remove')) return reply({});
          uploadCalls++;
          if (!entered.isCompleted) entered.complete();
          return pending.future;
        }));
      });
    }
  }

  test('unchanged session accepts avatar response normally', () async {
    final session = Session();
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-password');
      await session.uploadAvatar(file);
      expect(session.user?['public_id'], 'owner-a');
      expect(session.user?['name'], 'Updated fixture');
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return reply({'access_token': 'fixture-access', 'expires_in': 3600});
      if (r.url.path.endsWith('/auth/me')) return reply({'user': {'public_id': 'owner-a'}});
      return reply({'user': {'public_id': 'owner-a', 'name': 'Updated fixture'}});
    }));
  });
}

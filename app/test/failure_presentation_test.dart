// Offline response and presentation boundaries only.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/api_failure.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('arbitrary API diagnostics and reflection are never product copy', () {
    for (final status in [400, 403, 404, 409, 422, 429, 500, 503]) {
      for (final value in ['fixture internal path', '<html>fixture</html>',
        'SQLSTATE fixture', 'That member fixture@example.com is missing',
        ['nested fixture'], {'debug': 'fixture'}, 42]) {
        final message = apiFailureMessage(status, [value]);
        expect(message, isNot(contains('fixture')));
        expect(message, isNot(contains('<html>')));
      }
    }
    expect(apiFailureMessage(422, ['Not enough coins.']), 'Not enough coins.');
    expect(apiFailureMessage(409, ['This transfer key already belongs to different details.']),
      'This transfer key already belongs to different details.');
  });
  for (final body in [
    {'message': '<html>fixture path</html>'},
    {'errors': {'email': ['fixture@example.com is invalid']}},
    {'message': {'debug': 'fixture'}},
  ]) {
    test('real Session preserves status while suppressing response payload $body', () async {
      await http.runWithClient(() async {
        final session = Session();
        await session.login('fixture', 'fixture-value');
        await expectLater(session.call('GET', '/posts'), throwsA(isA<ApiError>()
          .having((e) => e.status, 'status', 422)
          .having((e) => e.message, 'safe copy', 'Check the details and try again.')));
      }, () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) return http.Response(jsonEncode({'access_token': 'fixture-token', 'expires_in': 3600}), 200);
        if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user': {'public_id': 'fixture-owner'}}), 200);
        return http.Response(jsonEncode(body), 422);
      }));
    });
  }
  test('runtime/platform errors cannot leak paths codes or diagnostic payloads', () {
    for (final error in [
      const FileSystemException('fixture private path', '/fixture/private'),
      const FormatException('fixture payload'),
      PlatformException(code: 'fixture', message: 'fixture credentials'),
      StateError('fixture arbitrary'),
    ]) {
      expect(failureMessage(error), 'Something went wrong. Check the current state before trying again.');
    }
    expect(failureMessage(ApiError('The upload result is unknown. Check your posts or stories before sharing again.')),
      'The upload result is unknown. Check your posts or stories before sharing again.');
    expect(failureMessage(StateError('This media draft changed. Reopen before deleting.')),
      'This media draft changed. Reopen before deleting.');
  });
  testWidgets('error snackbar reads safe message and remains a live announcement', (t) async {
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showError(context, StateError('fixture path')), child: const Text('show')),
    ))));
    await t.tap(find.text('show')); await t.pump();
    expect(find.textContaining('fixture path'), findsNothing);
    expect(find.text('Something went wrong. Check the current state before trying again.'), findsOneWidget);
    expect(t.widgetList<Semantics>(find.byType(Semantics)).any((s) => s.properties.liveRegion == true), isTrue);
  });
}
// Poll composition and voting with a mock API. No production writes.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/poll_card.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> poll({int? mine, int a = 0, int b = 0}) => {'options': [{'choice': 0, 'text': 'Saturday', 'votes': a}, {'choice': 1, 'text': 'Sunday', 'votes': b}], 'total_votes': a + b, 'my_choice': mine};
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40))); await t.pumpAndSettle(); }
Future<void> fixture(WidgetTester t, Future<void> Function(Session) run, Future<http.Response> Function(http.Request) respond, {bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({});
  await http.runWithClient(() async {
    final s = Session(); await s.login('fixture', 'not-a-password'); await run(s);
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds: 1));
  }, () => MockClient((r) async {
    if (r.url.path.endsWith('/oauth/token')) return http.Response(jsonEncode({'access_token': 'fixture', 'expires_in': 3600}), 200);
    if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'features': {'polls': enabled}, 'user': {'public_id': 'me', 'username': 'fixture'}}), 200);
    return respond(r);
  }));
}
void main() {
  for (final enabled in [true, false]) {
    testWidgets('poll composition follows server capability $enabled', (t) async {
      await fixture(t, (s) async {
        await t.pumpWidget(MaterialApp(home: ComposePage(session: s)));
        await t.pumpAndSettle();
        expect(find.text('Poll'), enabled ? findsOneWidget : findsNothing);
      }, (_) async => http.Response('{}', 200), enabled: enabled);
    });
  }
  testWidgets('compose validates poll and sends question/options without media', (t) async {
    String? sent;
    await fixture(t, (s) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ComposePage(session: s)));
      await t.pumpAndSettle();
      await t.tap(find.text('Poll')); await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Post')); await t.pump();
      expect(sent, isNull);
      expect(find.text('Add a question and different, non-empty options.'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'Meetup day?');
      await t.enterText(find.byType(TextField).at(1), 'Saturday');
      await t.enterText(find.widgetWithText(TextField, 'Option 2'), 'Sunday');
      await t.tap(find.widgetWithText(FilledButton, 'Post')); await flush(t);
      expect(sent, contains('poll_options[0]'));
      expect(sent, contains('Saturday'));
      expect(sent, contains('Sunday'));
      expect(sent, isNot(contains('filename=')));
      expect(t.takeException(), isNull);
    }, (r) async { sent = latin1.decode(r.bodyBytes); return http.Response(jsonEncode({'post': {'public_id': 'p', 'kind': 'post'}}), 201); });
  });
  testWidgets('vote failure retains confirmed counts and can be retried and removed', (t) async {
    var fail = true;
    var writes = 0;
    final post = {'public_id': 'p', 'poll': poll()};
    await fixture(t, (s) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: PollCard(session: s, post: post))));
      await t.tap(find.text('Saturday')); await flush(t);
      expect(find.text('Vote fixture failed'), findsOneWidget);
      expect(find.text('0 votes'), findsOneWidget);
      expect(find.text('Remove vote'), findsNothing);
      fail = false;
      await t.tap(find.text('Saturday')); await flush(t);
      expect(find.text('1 vote'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      await t.tap(find.text('Remove vote')); await flush(t);
      expect(find.text('0 votes'), findsOneWidget);
      expect(writes, 3);
      expect(t.takeException(), isNull);
    }, (r) async {
      writes++;
      return http.Response(jsonEncode(fail ? {'message': 'Vote fixture failed'} : {'poll': r.method == 'DELETE' ? poll() : poll(mine: 0, a: 1)}), fail ? 503 : 200);
    });
  });
  testWidgets('large-text poll controls remain above simulated keyboard and remove safely while focused', (t) async {
    t.view.physicalSize = const Size(640, 1280);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await fixture(t, (s) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.8)), child: child!), home: ComposePage(session: s)));
      await t.pumpAndSettle();
      await t.tap(find.text('Poll')); await t.pumpAndSettle();
      t.view.viewInsets = const FakeViewPadding(bottom: 480);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Option 2'), 120, scrollable: find.byType(Scrollable).first);
      await t.enterText(find.widgetWithText(TextField, 'Option 2'), 'Sunday');
      await t.pumpAndSettle();
      final remove = find.widgetWithText(TextButton, 'Remove poll');
      expect(t.getBottomLeft(remove).dy, lessThanOrEqualTo(400));
      expect(remove.hitTestable(), findsOneWidget);
      expect(find.text('Photos'), findsNothing);
      expect(t.takeException(), isNull);
      await t.tap(remove); await t.pumpAndSettle();
      expect(find.text('Remove poll'), findsNothing);
      expect(find.text('Photos'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, (_) async => http.Response('{}', 200));
  });
  testWidgets('vote blocks duplicate taps while pending', (t) async {
    var writes = 0;
    final pending = Completer<http.Response>();
    await fixture(t, (s) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PollCard(session: s, post: {'public_id': 'p', 'poll': poll()}))));
      await t.tap(find.text('Saturday')); await t.pump();
      await t.tap(find.text('Sunday')); await t.pump();
      expect(writes, 1);
      pending.complete(http.Response(jsonEncode({'poll': poll(mine: 0, a: 1)}), 200));
      await flush(t);
      expect(find.text('1 vote'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, (_) { writes++; return pending.future; });
  });
}

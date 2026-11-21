// Exact-call reconciliation fixtures. No real calls, microphones or API access.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

Map<String, dynamic> row(String status, {String id = 'call'}) => {
  'public_id': id, 'conversation_id': 'convo', 'kind': 'voice', 'status': status,
  'caller': {'username': 'fixture', 'name': 'Sample caller'},
  'ring_expires_at': DateTime.now().add(const Duration(seconds: 40)).toIso8601String(),
};
class CallsFixture extends Session {
  CallsFixture() { user = {'public_id': 'fixture-owner'}; }
  Object? readResult;
  Object? writeResult;
  Completer<Object?>? readPending;
  int actions = 0, reads = 0, tokens = 0;
  @override Future<dynamic> call(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    if (path == '/calls/call/action') {
      actions++;
      if (writeResult is Exception) throw writeResult!;
      return writeResult;
    }
    if (method == 'GET' && path == '/calls/call') {
      reads++;
      if (readPending != null) return readPending!.future;
      if (readResult is Exception) throw readResult!;
      return readResult;
    }
    tokens++;
    throw StateError('Unexpected fixture request');
  }
}
Future<void> screen(WidgetTester t, CallsFixture s, {String lang = 'en', bool large = false}) async {
  prefs.lang = lang; addTearDown(() => prefs.lang = 'en');
  if (large) {
    t.view.physicalSize = const Size(320, 640); t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(RepaintBoundary(key: const ValueKey('call-proof'), child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.dark, fontFamily: 'Roboto'),
    builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(large ? 1.8 : 1)), child: w!),
    home: IncomingCallPage(session: s, call: row('ringing')),
  )));
  await t.pump();
}
void main() {
  setUpAll(() async {
    for (final f in [('Roboto', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
      ('MaterialIcons', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf')]) {
      final loader = FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));
      await loader.load();
    }
  });
  for (final action in ['Accept', 'Decline']) {
    for (final result in [null, {'call': row('ended', id: 'wrong')}, ApiError('fixture read', 503), ApiError('fixture absent', 404)]) {
      testWidgets('$action unknown result does not resend or infer ringing from $result', (t) async {
        final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = result;
        await screen(t, s);
        await t.tap(find.byTooltip(action)); await t.pumpAndSettle();
        expect(s.actions, 1); expect(s.reads, 1); expect(s.tokens, 0);
        expect(find.byTooltip('Accept'), findsNothing); expect(find.byTooltip('Decline'), findsNothing);
        expect(find.text('Call status is unknown.'), findsOneWidget);
        await t.tap(find.text('Check call status')); await t.pumpAndSettle();
        expect(s.actions, 1); expect(s.reads, 2);
        await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
      });
    }
  }
  testWidgets('only a fresh exact ringing response restores explicit actions', (t) async {
    final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = {'call': row('ringing')};
    await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pumpAndSettle();
    expect(s.actions, 1); expect(find.byTooltip('Accept'), findsOneWidget); expect(find.byTooltip('Decline'), findsOneWidget);
    expect(s.tokens, 0);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  testWidgets('expired ringing response stays unknown and cannot create a read loop', (t) async {
    final stale = row('ringing')..['ring_expires_at'] = DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String();
    final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = {'call': stale};
    await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pumpAndSettle();
    await t.pump(const Duration(minutes: 2));
    expect(s.actions, 1); expect(s.reads, 1); expect(find.byTooltip('Accept'), findsNothing);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  for (final status in ['answered', 'declined', 'missed', 'ended']) {
    testWidgets('reconciled $status does not join start or repeat a call', (t) async {
      final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = {'call': row(status)};
      await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pumpAndSettle();
      expect(s.actions, 1); expect(s.reads, 1); expect(s.tokens, 0); expect(find.byType(CallPage), findsNothing);
      expect(find.byTooltip('Accept'), findsNothing); expect(find.byTooltip('Decline'), findsNothing);
      expect(find.text('Join this call'), status == 'answered' ? findsOneWidget : findsNothing);
      await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
    });
  }
  testWidgets('terminal action receipt is not mistaken for a successful answer', (t) async {
    final s = CallsFixture()..writeResult = {'call': row('ended')}..readResult = {'call': row('ended')};
    await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pumpAndSettle();
    expect(s.tokens, 0); expect(find.byType(CallPage), findsNothing); expect(find.text('This call has ended.'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  testWidgets('lost decline reconciled as answered never offers join', (t) async {
    final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = {'call': row('answered')};
    await screen(t, s); await t.tap(find.byTooltip('Decline')); await t.pumpAndSettle();
    expect(s.actions, 1); expect(s.reads, 1); expect(s.tokens, 0);
    expect(find.text('Join this call'), findsNothing); expect(find.byType(CallPage), findsNothing);
    expect(find.text('This call was answered.'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  testWidgets('closing while a status check is pending ignores its late result', (t) async {
    final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readPending = Completer<Object?>();
    await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pump();
    await t.tap(find.text('Close')); await t.pumpAndSettle();
    s.readPending!.complete({'call': row('answered')}); await t.pumpAndSettle();
    expect(find.text('Join this call'), findsNothing); expect(s.actions, 1); expect(s.tokens, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  testWidgets('retirement suppresses a late answered state and any join', (t) async {
    final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readPending = Completer<Object?>();
    await screen(t, s); await t.tap(find.byTooltip('Accept')); await t.pump();
    s.user = {'public_id': 'another-fixture'}; s.notifyListeners(); await t.pump();
    s.readPending!.complete({'call': row('answered')}); await t.pumpAndSettle();
    expect(find.text('Join this call'), findsNothing); expect(s.tokens, 0); expect(s.actions, 1);
    await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
  });
  for (final lang in ['en', 'ne']) {
    testWidgets('unknown call large text is readable with no conflicting actions $lang', (t) async {
      final s = CallsFixture()..writeResult = ApiError('fixture lost', 503)..readResult = ApiError('fixture read', 503);
      await screen(t, s, lang: lang, large: true);
      await t.tap(find.byTooltip(lang == 'en' ? 'Accept' : 'स्वीकार गर्नुहोस्')); await t.pumpAndSettle();
      expect(find.byType(IconButton), findsNothing); expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final b = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('call-proof')));
        final im = await b.toImage(pixelRatio: 2); final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        Directory('test/renders').createSync(recursive: true);
        File('test/renders/call_unknown_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      if (lang == 'ne') {
        await t.drag(find.byType(SingleChildScrollView), const Offset(0, -1200));
        await t.pumpAndSettle();
        final text = find.byWidgetPredicate((w) => w is Text && (w.data?.contains('दोहोर्') ?? false));
        expect(text, findsOneWidget);
        final p = t.getRect(text);
        final button = t.getRect(find.byType(FilledButton));
        expect(p.bottom, lessThan(button.top));
        expect(p.top, greaterThanOrEqualTo(0));
        await t.runAsync(() async {
          final b = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('call-proof')));
          final im = await b.toImage(pixelRatio: 2); final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          File('test/renders/call_unknown_ne_scrolled.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
    });
  }
}

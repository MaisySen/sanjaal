import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart' show ApiError;
import 'package:sanjaal/active_call_host.dart';
import 'package:sanjaal/call_controller.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'call_continuity_fakes.dart';

class CallHarness {
  final session = CallFixtureSession();
  final navigator = GlobalKey<NavigatorState>();
  final host = GlobalKey<ActiveCallHostState>();
  final boundary = GlobalKey();
  final natives = <FakeCallConnection>[];
  FakeCallConnection Function()? next;
  late BuildContext source;
  int work = 0;
  Future<void> mount(
    WidgetTester t, {
    String lang = 'en',
    double scale = 1,
    Widget? screen,
  }) async {
    prefs.lang = lang;
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(
            Brightness.light,
            fontFamily: 'Roboto',
            fontFamilyFallback: ['NotoDev'],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: ActiveCallHost(
              key: host,
              session: session,
              navigatorKey: navigator,
              createCall:
                  ({
                    required session,
                    required conversationId,
                    required title,
                    required video,
                    callId,
                  }) {
                    final native = next?.call() ?? FakeCallConnection();
                    natives.add(native);
                    return CallController(
                      session: session,
                      conversationId: conversationId,
                      title: title,
                      video: video,
                      callId: callId,
                      connection: native,
                    );
                  },
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) {
              source = context;
              if (screen != null) return screen;
              return Scaffold(
                appBar: AppBar(title: const Text('Synthetic app')),
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () => unawaited(start()),
                        child: const Text('Open call'),
                      ),
                      TextButton(
                        onPressed: () => unawaited(start('other')),
                        child: const Text('Open another call'),
                      ),
                      TextButton(
                        onPressed: () => work++,
                        child: const Text('Keep using app'),
                      ),
                      TextButton(
                        onPressed: () => navigator.currentState!.push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(
                              body: Center(child: Text('Synthetic detail')),
                            ),
                          ),
                        ),
                        child: const Text('Open detail'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> start([String conversation = 'chat']) => openCall(
    source,
    session: session,
    conversationId: conversation,
    title: 'Synthetic member',
    video: true,
  );
  Future<void> minimize(WidgetTester t) async {
    await t.tap(find.byTooltip(t_('Minimize call')));
    await t.pumpAndSettle();
  }

  Future<void> end(WidgetTester t) async {
    final target = find.byType(ActiveCallBanner).evaluate().isNotEmpty
        ? find.widgetWithText(TextButton, t_('End call'))
        : find.byTooltip(t_('End call'));
    await t.ensureVisible(target);
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester t, String name) async {
    final folder =
        Platform.environment['SANJAAL_CALL_CONTINUITY_WIDGET_OUTPUT'];
    if (folder == null) return;
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(folder).createSync(recursive: true);
      File('$folder/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }
}

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  tearDown(() {
    prefs.lang = 'en';
  });
  testWidgets('minimise browse restore mute and end keeps one native call', (
    t,
  ) async {
    final h = CallHarness();
    await h.mount(t);
    unawaited(h.start());
    await t.pumpAndSettle();
    expect(find.byType(CallPage), findsOneWidget);
    await h.minimize(t);
    expect(find.byType(CallPage), findsNothing);
    expect(find.byType(ActiveCallBanner), findsOneWidget);
    expect(find.text('Microphone on'), findsOneWidget);
    await t.tap(find.text('Keep using app'));
    expect(h.work, 1);
    await t.tap(find.text('Open detail'));
    await t.pumpAndSettle();
    expect(find.text('Synthetic detail'), findsOneWidget);
    await t.tap(find.text('Return to call'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Mute microphone'));
    await t.pumpAndSettle();
    await h.minimize(t);
    expect(find.text('Microphone off'), findsOneWidget);
    await h.end(t);
    expect(find.byType(ActiveCallBanner), findsNothing);
    expect(find.text('Synthetic detail'), findsOneWidget);
    expect(h.natives.length, 1);
    expect(h.natives.single.events.where((e) => e == 'connect').length, 1);
    expect(h.natives.single.events.where((e) => e == 'dispose').length, 1);
    expect(
      h.session.requests.where((r) => r.path.contains('/call-token')).length,
      1,
    );
    expect(
      h.session.requests.where((r) => r.path.endsWith('/action')).length,
      1,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'system Back minimises instead of ending and another call is blocked',
    (t) async {
      final h = CallHarness();
      await h.mount(t);
      unawaited(h.start());
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(ActiveCallBanner), findsOneWidget);
      expect(
        h.session.requests.where((r) => r.path.endsWith('/action')),
        isEmpty,
      );
      await t.tap(find.text('Open another call'));
      await t.pumpAndSettle();
      expect(h.natives.length, 1);
      expect(
        find.text('End the current call before starting another.'),
        findsOneWidget,
      );
      await h.end(t);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('same conversation restores without a second token', (t) async {
    final h = CallHarness();
    await h.mount(t);
    unawaited(h.start());
    await t.pumpAndSettle();
    await h.minimize(t);
    unawaited(h.start());
    await t.pumpAndSettle();
    expect(find.byType(CallPage), findsOneWidget);
    expect(h.natives.length, 1);
    expect(
      h.session.requests.where((r) => r.path.contains('/call-token')).length,
      1,
    );
    await h.end(t);
    await t.pumpWidget(const SizedBox());
  });
  for (final owner in ['me', 'other']) {
    for (final minimized in [false, true]) {
      testWidgets(
        'replacement owner=$owner minimized=$minimized releases without replacement credentials',
        (t) async {
          final h = CallHarness();
          await h.mount(t);
          unawaited(h.start());
          await t.pumpAndSettle();
          if (minimized) await h.minimize(t);
          h.session.replace(owner: owner);
          await t.pumpAndSettle();
          expect(find.byType(CallPage), findsNothing);
          expect(find.byType(ActiveCallBanner), findsNothing);
          expect(find.text('Synthetic member'), findsNothing);
          expect(
            h.natives.single.events.where((e) => e == 'dispose').length,
            1,
          );
          expect(
            h.session.requests.where((r) => r.path.endsWith('/action')),
            isEmpty,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('retained actions cannot end or minimise a replacement call', (
    t,
  ) async {
    final h = CallHarness();
    await h.mount(t);
    unawaited(h.start());
    await t.pumpAndSettle();
    final oldEnd = t
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'End call',
          ),
        )
        .onPressed!;
    final oldMinimize = t
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Minimize call',
          ),
        )
        .onPressed!;
    await h.end(t);
    unawaited(h.start('new-chat'));
    await t.pumpAndSettle();
    oldEnd();
    oldMinimize();
    await t.pumpAndSettle();
    expect(find.byType(CallPage), findsOneWidget);
    expect(h.natives.length, 2);
    expect(h.natives.last.events.where((e) => e == 'dispose'), isEmpty);
    await h.end(t);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'native cleanup failure blocks new calls and does not claim capture stopped',
    (t) async {
      final h = CallHarness()
        ..next = () => FakeCallConnection()..failDispose = true;
      await h.mount(t);
      unawaited(h.start());
      await t.pumpAndSettle();
      await h.end(t);
      expect(
        find.textContaining('Call cleanup could not be confirmed.'),
        findsOneWidget,
      );
      unawaited(h.start());
      await t.pumpAndSettle();
      expect(h.natives.length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late connection timeout stays quarantined after the native future settles',
    (t) async {
      final pending = Completer<void>();
      final h = CallHarness()
        ..next = () => FakeCallConnection()..connectWait = pending.future;
      await h.mount(t);
      unawaited(h.start());
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('End call'));
      await t.pump();
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Call cleanup could not be confirmed.'),
        findsOneWidget,
      );
      unawaited(h.start());
      await t.pumpAndSettle();
      expect(h.natives.length, 1);
      pending.complete();
      await t.pumpAndSettle();
      expect(
        h.natives.single.events.where(
          (e) => e.startsWith('microphone:') || e.startsWith('camera:'),
        ),
        isEmpty,
      );
      unawaited(h.start());
      await t.pumpAndSettle();
      expect(h.natives.length, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'covered presentation actions cannot remove the covering route or end capture',
    (t) async {
      final h = CallHarness();
      await h.mount(t);
      unawaited(h.start());
      await t.pumpAndSettle();
      final oldEnd = t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'End call',
            ),
          )
          .onPressed!;
      final oldMinimize = t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Minimize call',
            ),
          )
          .onPressed!;
      h.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering fixture')),
        ),
      );
      await t.pumpAndSettle();
      oldEnd();
      oldMinimize();
      await t.pumpAndSettle();
      expect(find.text('Covering fixture'), findsOneWidget);
      expect(
        h.session.requests.where((r) => r.path.endsWith('/action')),
        isEmpty,
      );
      h.navigator.currentState!.pop();
      await t.pumpAndSettle();
      await h.end(t);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final language in ['en', 'ne']) {
    for (final landscape in [false, true]) {
      testWidgets(
        'long minimised failure keeps return and End reachable $language landscape=$landscape',
        (t) async {
          t.view.physicalSize = landscape
              ? const Size(640, 320)
              : const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final pending = Completer<dynamic>();
          final h = CallHarness();
          h.session.tokenReply = pending.future;
          await h.mount(t, lang: language, scale: 1.8);
          unawaited(h.start());
          await t.pumpAndSettle();
          final sentence = language == 'en'
              ? 'Synthetic call service is unavailable. '
              : 'नमुना कल सेवा उपलब्ध छैन। ';
          pending.completeError(
            ApiError(
              '${List.filled(60, sentence).join()}End of synthetic error.',
              503,
            ),
          );
          await t.pumpAndSettle();
          await h.minimize(t);
          expect(find.text(t_('Return to call')).hitTestable(), findsOneWidget);
          expect(find.text(t_('End call')).hitTestable(), findsOneWidget);
          final scroll = find.byKey(
            const ValueKey('active-call-status-scroll'),
          );
          await t.drag(scroll, const Offset(0, -10000));
          await t.pumpAndSettle();
          final state = t.state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          );
          expect(
            state.position.pixels,
            closeTo(state.position.maxScrollExtent, 1),
          );
          await h.screenshot(t, 'failure_${language}_$landscape');
          expect(t.takeException(), isNull);
          await h.end(t);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final language in ['en', 'ne']) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'minimised banner and underlying app stay reachable $language $scale',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final h = CallHarness();
          await h.mount(t, lang: language, scale: scale);
          unawaited(h.start());
          await t.pumpAndSettle();
          await h.minimize(t);
          expect(find.text(t_('Return to call')).hitTestable(), findsOneWidget);
          expect(find.text(t_('End call')).hitTestable(), findsOneWidget);
          await t.ensureVisible(find.text('Keep using app'));
          await t.tap(find.text('Keep using app'));
          expect(h.work, 1);
          await h.screenshot(t, 'minimised_${language}_$scale');
          expect(t.takeException(), isNull);
          await h.end(t);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

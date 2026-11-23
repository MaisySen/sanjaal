// Synthetic notification-open events. No provider, notification send or phone.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/message_open_host.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

class Source implements MessageOpenSource {
  final events = StreamController<void>.broadcast(sync: true);
  final initial = Completer<bool>();
  int initialReads = 0;
  @override
  bool supported = true;
  @override
  Stream<void> get opens => events.stream;
  @override
  Future<bool> initialOpen() {
    initialReads++;
    return initial.future;
  }
}

class OpenSession extends Session {
  OpenSession() {
    loading = false;
    user = {'public_id': 'me', 'username': 'me'};
  }
  int epoch = 1, reads = 0, writes = 0;
  @override
  int get generation => epoch;
  void replace({bool signedOut = false}) {
    epoch++;
    user = signedOut ? null : {'public_id': 'me', 'username': 'me'};
    notifyListeners();
  }

  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method != 'GET') {
      writes++;
      return {};
    }
    reads++;
    return {'data': <dynamic>[]};
  }
}

void main() {
  setUpAll(() async {
    for (final item in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(item.$1)..addFont(
            Future.value(ByteData.sublistView(File(item.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  Future<(Source, OpenSession)> mount(
    WidgetTester t, {
    String lang = 'en',
    bool supported = true,
  }) async {
    prefs.lang = lang;
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    final source = Source()..supported = supported;
    final session = OpenSession();
    final nav = GlobalKey<NavigatorState>();
    final editor = TextEditingController(text: 'Unsent current work');
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await source.events.close();
      editor.dispose();
      t.view.reset();
      prefs.lang = 'en';
    });
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(
          Brightness.light,
          fontFamily: 'Roboto',
          fontFamilyFallback: ['NotoDev'],
        ),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: RepaintBoundary(
            key: const ValueKey('open-shot'),
            child: MessageOpenHost(
              session: session,
              navigatorKey: nav,
              source: source,
              child: w!,
            ),
          ),
        ),
        home: Scaffold(body: TextField(controller: editor)),
      ),
    );
    await t.pump();
    return (source, session);
  }

  for (final lang in ['en', 'ne']) {
    testWidgets(
      'notification offers current inbox without replacing work $lang',
      (t) async {
        final (source, session) = await mount(t, lang: lang);
        source.initial.complete(false);
        await t.pump();
        source.events.add(null);
        await t.pumpAndSettle();
        expect(find.text(t_('Open chats')), findsOneWidget);
        expect(find.text('Unsent current work'), findsOneWidget);
        expect(session.reads, 0);
        expect(session.writes, 0);
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('open-shot')),
              )
              .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final path = File('test/renders/message_open_$lang.png');
          path.parent.createSync(recursive: true);
          path.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await t.tap(find.text(t_('Open chats')));
        await t.pumpAndSettle();
        expect(find.byType(ChatsPage), findsOneWidget);
        expect(session.reads, 1);
        expect(session.writes, 0);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Unsent current work'), findsOneWidget);
        expect(find.text(t_('Open chats')), findsNothing);
      },
    );
  }
  testWidgets('late initial open cannot cross same-member replacement', (
    t,
  ) async {
    final (source, session) = await mount(t);
    session.replace();
    await t.pump();
    source.initial.complete(true);
    await t.pumpAndSettle();
    expect(find.text('Open chats'), findsNothing);
    expect(session.reads, 0);
  });
  testWidgets('replacement retires banner and retained open callback', (
    t,
  ) async {
    final (source, session) = await mount(t);
    source.initial.complete(false);
    source.events.add(null);
    await t.pumpAndSettle();
    final callback = t
        .widget<TextButton>(find.widgetWithText(TextButton, 'Open chats'))
        .onPressed!;
    session.replace();
    await t.pump();
    callback();
    await t.pumpAndSettle();
    expect(find.text('Open chats'), findsNothing);
    expect(session.reads, 0);
    source.events.add(null);
    await t.pumpAndSettle();
    await t.tap(find.text('Dismiss'));
    await t.pumpAndSettle();
    expect(session.reads, 0);
    expect(find.text('Unsent current work'), findsOneWidget);
  });
  testWidgets(
    'cold-start tap offers once after restore without automatic navigation',
    (t) async {
      final (source, session) = await mount(t);
      source.initial.complete(true);
      await t.pumpAndSettle();
      expect(find.text('Open chats'), findsOneWidget);
      expect(session.reads, 0);
      source.events.add(null);
      source.events.add(null);
      await t.pumpAndSettle();
      await t.tap(find.text('Open chats'));
      await t.pumpAndSettle();
      expect(session.reads, 1);
      source.events.add(null);
      await t.pumpAndSettle();
      expect(find.text('Open chats'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(source.initialReads, 1);
      expect(session.writes, 0);
    },
  );
  testWidgets(
    'signed-out events and source errors never open another account',
    (t) async {
      final (source, session) = await mount(t);
      source.initial.complete(false);
      session.replace(signedOut: true);
      await t.pump();
      source.events.add(null);
      source.events.addError(StateError('synthetic source failure'));
      await t.pumpAndSettle();
      session.replace();
      await t.pumpAndSettle();
      expect(find.text('Open chats'), findsNothing);
      expect(session.reads, 0);
    },
  );
  testWidgets('old retained callback cannot consume new-generation offer', (
    t,
  ) async {
    final (source, session) = await mount(t);
    source.initial.complete(false);
    source.events.add(null);
    await t.pumpAndSettle();
    final callback = t
        .widget<TextButton>(find.widgetWithText(TextButton, 'Open chats'))
        .onPressed!;
    session.replace();
    await t.pump();
    source.events.add(null);
    await t.pumpAndSettle();
    callback();
    await t.pumpAndSettle();
    expect(find.text('Open chats'), findsOneWidget);
    expect(session.reads, 0);
  });
  testWidgets(
    'notification entry stays bounded with keyboard and preserves input',
    (t) async {
      final (source, session) = await mount(t, lang: 'ne');
      source.initial.complete(false);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      source.events.add(null);
      await t.pumpAndSettle();
      expect(find.text('Unsent current work'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text(t_('Open chats')));
      await t.pumpAndSettle();
      expect(find.text(t_('Open chats')).hitTestable(), findsOneWidget);
      expect(session.reads, 0);
    },
  );
  testWidgets(
    'unsupported platforms never subscribe or read initial notification',
    (t) async {
      final (source, session) = await mount(t, supported: false);
      source.events.add(null);
      await t.pumpAndSettle();
      expect(source.initialReads, 0);
      expect(find.text('Open chats'), findsNothing);
      expect(session.reads, 0);
    },
  );
}

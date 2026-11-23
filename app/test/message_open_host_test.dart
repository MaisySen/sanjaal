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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/message_open_host.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

class Source implements MessageOpenSource {
  final events = StreamController<MessageOpenIntent>.broadcast(sync: true);
  final initial = Completer<MessageOpenIntent?>();
  int initialReads = 0;
  @override
  bool supported = true;
  @override
  Stream<MessageOpenIntent> get opens => events.stream;
  @override
  Future<MessageOpenIntent?> initialOpen() {
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
  Future<dynamic> Function()? resolve;
  final paths = <String>[];
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
      if (path.endsWith('/messages')) writes++;
      return {};
    }
    reads++;
    paths.add(path);
    if (path == '/conversations/10000000-0000-4000-8000-000000000001' &&
        resolve != null) {
      return resolve!();
    }
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
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
      await t.pump(const Duration(seconds: 3));
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
        source.initial.complete(null);
        await t.pump();
        source.events.add(const MessageOpenIntent());
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
    source.initial.complete(const MessageOpenIntent());
    await t.pumpAndSettle();
    expect(find.text('Open chats'), findsNothing);
    expect(session.reads, 0);
  });
  testWidgets('replacement retires banner and retained open callback', (
    t,
  ) async {
    final (source, session) = await mount(t);
    source.initial.complete(null);
    source.events.add(const MessageOpenIntent());
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
    source.events.add(const MessageOpenIntent());
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
      source.initial.complete(const MessageOpenIntent());
      await t.pumpAndSettle();
      expect(find.text('Open chats'), findsOneWidget);
      expect(session.reads, 0);
      source.events.add(const MessageOpenIntent());
      source.events.add(const MessageOpenIntent());
      await t.pumpAndSettle();
      await t.tap(find.text('Open chats'));
      await t.pumpAndSettle();
      expect(session.reads, 1);
      source.events.add(const MessageOpenIntent());
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
      source.initial.complete(null);
      session.replace(signedOut: true);
      await t.pump();
      source.events.add(const MessageOpenIntent());
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
    source.initial.complete(null);
    source.events.add(const MessageOpenIntent());
    await t.pumpAndSettle();
    final callback = t
        .widget<TextButton>(find.widgetWithText(TextButton, 'Open chats'))
        .onPressed!;
    session.replace();
    await t.pump();
    source.events.add(const MessageOpenIntent());
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
      source.initial.complete(null);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      source.events.add(const MessageOpenIntent());
      await t.pumpAndSettle();
      expect(find.text('Unsent current work'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text(t_('Open chats')));
      await t.pumpAndSettle();
      expect(find.text(t_('Open chats')).hitTestable(), findsOneWidget);
      expect(session.reads, 0);
    },
  );
  test('payload parser rejects unrelated types and never trusts legacy destination', () {
    expect(MessageOpenIntent.fromData({'type': 'follow'}), isNull);
    for (final data in [
      <String, dynamic>{'type': 'message', 'conversation': 'arbitrary-path'},
      <String, dynamic>{
        'type': 'message',
        'open_version': '2',
        'recipient': '20000000-0000-4000-8000-000000000001',
        'conversation': '10000000-0000-4000-8000-000000000001',
      },
    ]) {
      expect(MessageOpenIntent.fromData(data)!.conversation, isNull);
    }
  });
  testWidgets(
    'bound recipient opens only server-resolved conversation after explicit action',
    (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (source, session) = await mount(t);
      session.user = {
        'public_id': '20000000-0000-4000-8000-000000000001',
        'username': 'me',
      };
      session.resolve = () async => {
        'conversation': {
          'public_id': '10000000-0000-4000-8000-000000000001',
          'type': 'direct',
          'title': 'Verified member',
        },
      };
      source.initial.complete(null);
      source.events.add(
        MessageOpenIntent.fromData({
          'type': 'message',
          'open_version': '1',
          'recipient': session.user!['public_id'],
          'conversation': '10000000-0000-4000-8000-000000000001',
        })!,
      );
      await t.pumpAndSettle();
      expect(find.text('Open conversation'), findsOneWidget);
      expect(session.reads, 0);
      await t.runAsync(() async {
        final image = await t
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('open-shot')),
            )
            .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/renders/message_open_bound_offer.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.tap(find.text('Open conversation'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.text('Verified member'), findsOneWidget);
      expect(
        session.paths.first,
        '/conversations/10000000-0000-4000-8000-000000000001',
      );
      expect(session.writes, 0);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Unsent current work'), findsOneWidget);
    },
  );
  testWidgets(
    'wrong recipient falls back to explicit inbox without resolving payload target',
    (t) async {
      final (source, session) = await mount(t);
      source.initial.complete(null);
      source.events.add(
        const MessageOpenIntent(
          recipient: 'other',
          conversation: '10000000-0000-4000-8000-000000000001',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Open conversation'), findsNothing);
      await t.tap(find.text('Open chats'));
      await t.pumpAndSettle();
      expect(session.paths, ['/conversations']);
      expect(session.writes, 0);
    },
  );
  for (final failure in ['gone', 'mismatch', 'retry', 'replaced']) {
    testWidgets('conversation resolution $failure is safe', (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      final (source, session) = await mount(t);
      session.user = {'public_id': 'owner', 'username': 'me'};
      final held = Completer<dynamic>();
      var attempt = 0;
      session.resolve = () async {
        attempt++;
        if (failure == 'replaced') return held.future;
        if (failure == 'gone') throw ApiError('Not found', 404);
        if (failure == 'retry' && attempt == 1) {
          throw ApiError('Unavailable', 503);
        }
        return {
          'conversation': {
            'public_id': failure == 'mismatch'
                ? 'another'
                : '10000000-0000-4000-8000-000000000001',
            'type': 'direct',
            'title': 'Verified member',
          },
        };
      };
      source.initial.complete(null);
      source.events.add(
        const MessageOpenIntent(
          recipient: 'owner',
          conversation: '10000000-0000-4000-8000-000000000001',
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open conversation'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      if (failure == 'replaced') {
        session.replace();
        await t.pump();
        held.complete({
          'conversation': {
            'public_id': '10000000-0000-4000-8000-000000000001',
            'type': 'direct',
            'title': 'Late private member',
          },
        });
        await t.pumpAndSettle();
        expect(find.text('Late private member'), findsNothing);
        expect(find.byType(ChatPage), findsNothing);
      } else if (failure == 'gone') {
        expect(find.text('This conversation is unavailable.'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
      } else {
        expect(
          find.text('The conversation could not be opened. Try again.'),
          findsOneWidget,
        );
        expect(find.byType(ChatPage), findsNothing);
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('open-shot')),
              )
              .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('test/renders/message_open_resolution_error.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        if (failure == 'retry') {
          await t.tap(find.text('Try again'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 500));
          expect(find.byType(ChatPage), findsOneWidget);
        }
      }
      expect(session.writes, 0);
    });
  }
  testWidgets('older same-account callback cannot open newer notification', (
    t,
  ) async {
    final (source, session) = await mount(t);
    source.initial.complete(null);
    source.events.add(const MessageOpenIntent());
    await t.pumpAndSettle();
    final callback = t
        .widget<TextButton>(find.widgetWithText(TextButton, 'Open chats'))
        .onPressed!;
    source.events.add(const MessageOpenIntent());
    await t.pumpAndSettle();
    callback();
    await t.pumpAndSettle();
    expect(session.reads, 0);
    expect(find.text('Open chats'), findsOneWidget);
  });
  testWidgets(
    'unsupported platforms never subscribe or read initial notification',
    (t) async {
      final (source, session) = await mount(t, supported: false);
      source.events.add(const MessageOpenIntent());
      await t.pumpAndSettle();
      expect(source.initialReads, 0);
      expect(find.text('Open chats'), findsNothing);
      expect(session.reads, 0);
    },
  );
}

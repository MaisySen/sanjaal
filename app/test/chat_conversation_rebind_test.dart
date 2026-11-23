// Conversation replacement must never relabel private composer or saved text.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/chat_text_draft_store.dart';
import 'package:sanjaal/ui.dart' show prefs;

class RebindSession extends Session {
  RebindSession() {
    user = {'public_id': 'me', 'username': 'me'};
  }
  final pending = Completer<dynamic>();
  int writes = 0;
  final reads = <String>[];
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'GET') {
      reads.add(path);
      if (query?.containsKey('after_seq') == true) return pending.future;
      return {'data': <dynamic>[]};
    }
    if (path.endsWith('/messages')) writes++;
    return {};
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await font.load();
  });
  for (final dialog in [false, true]) {
    testWidgets(
      'conversation identity change retires private text and callbacks dialog=$dialog',
      (t) async {
        prefs.lang = 'en';
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        FlutterSecureStorage.setMockInitialValues({});
        final saved = await const ChatTextDraftStore().save(
          'me',
          'old-chat',
          'Old saved private text',
        );
        final session = RebindSession();
        final conversation = ValueNotifier('old-chat');
        addTearDown(() async {
          if (!session.pending.isCompleted) {
            session.pending.complete({'data': []});
          }
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 3));
          conversation.dispose();
        });
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
            builder: (c, w) => RepaintBoundary(
              key: const ValueKey('rebind-capture'),
              child: MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(1.8)),
                child: w!,
              ),
            ),
            home: ValueListenableBuilder<String>(
              valueListenable: conversation,
              builder: (_, id, child) => ChatPage(
                key: const ValueKey('same-chat-state'),
                session: session,
                convo: {'public_id': id, 'title': id, 'type': 'direct'},
              ),
            ),
          ),
        );
        Future<void> settle() async {
          await t.pump();
          await t.pump(const Duration(milliseconds: 450));
          await t.pump();
        }

        await settle();
        await t.enterText(find.byType(TextField), 'Old unsent private text');
        await settle();
        VoidCallback? retained;
        if (dialog) {
          await t.tap(find.byTooltip('Saved text'));
          await settle();
          retained = t
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Remove saved copy'),
              )
              .onPressed;
        }
        conversation.value = 'new-chat';
        await settle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(
            'This conversation changed. Close it and open the chat again.',
          ),
          findsOneWidget,
        );
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('rebind-capture')),
              )
              .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'test/renders/chat_conversation_rebind_retired.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        retained?.call();
        await settle();
        expect(
          (await const ChatTextDraftStore().read('me', 'old-chat'))!.revision,
          saved.revision,
        );
        expect(await const ChatTextDraftStore().read('me', 'new-chat'), isNull);
        expect(session.writes, 0);
        conversation.value = 'old-chat';
        await settle();
        expect(find.byType(TextField), findsNothing);
        expect(session.reads.where((p) => p.contains('new-chat')), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}

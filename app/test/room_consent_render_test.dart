// Synthetic status fixture only. No FCM token, network or device delivery.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/ui.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final file = File(font.$2);
      if (file.existsSync())
        await (FontLoader(font.$1)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
    }
  });
  for (final language in ['en', 'ne']) {
    testWidgets('room invitation requires local unmute $language', (t) async {
      prefs.lang = language;
      addTearDown(() => prefs.lang = 'en');
      t.view.physicalSize = const Size(960, 1920);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final chat = TextEditingController();
      addTearDown(chat.dispose);
      var toggles = 0;
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(
              language == 'en' ? Brightness.dark : Brightness.light,
              fontFamily: 'Roboto',
              fontFamilyFallback: ['NotoDev'],
            ),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: Column(
                children: [
                  Expanded(child: w!),
                  const Text(
                    'SYNTHETIC ROOM - NO AUDIO/DEVICE PROOF',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 9,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            home: RoomView(
              title: 'Community room',
              status: 'Live',
              failed: false,
              isHost: false,
              speaker: true,
              muted: true,
              handUp: false,
              inRoom: 2,
              hands: const {},
              stage: const [
                (
                  id: 'listener',
                  name: 'You',
                  host: false,
                  you: true,
                  muted: true,
                  speaking: false,
                ),
              ],
              messages: const [],
              chat: chat,
              onEnd: () {},
              onToggleMic: () {
                toggles++;
              },
              onRaise: () {},
              onGift: () {},
              onAllow: (_, allow) {},
              onDismissHand: (_) {},
              onSend: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text(t_('You can speak. Tap Unmute when ready.')),
        findsOneWidget,
      );
      expect(toggles, 0);
      expect(find.byTooltip(t_('Unmute')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('test/renders').createSync(recursive: true);
        File('test/renders/room_consent_$language.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await t.tap(find.byTooltip(t_('Unmute')));
      expect(toggles,1);
      await t.pumpWidget(const SizedBox());
    });
  }
}

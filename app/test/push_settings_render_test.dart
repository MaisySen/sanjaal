// Synthetic status fixture only. No FCM token, network or device delivery.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/push.dart';
import 'package:sanjaal/settings_page.dart';
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
  for (final ios in [false, true]) {
  for (final language in ['en', 'ne']) {
    testWidgets('notification settings status readable $language ios=$ios', (t) async {
      prefs.lang = language;
      addTearDown(() => prefs.lang = 'en');
      t.view.physicalSize = const Size(960, 1920);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      Push.status.value = ios ? Push.iosUnavailable :
          'Signed out. Notification token cleanup could not be confirmed';
      addTearDown(() => Push.status.value = 'Not set up yet');
      final key = GlobalKey();
      final session = Session()..user = {'public_id': 'fixture-owner'};
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
                    'SYNTHETIC STATUS - NOT FCM/DEVICE PROOF',
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
            home: SettingsPage(session: session),
          ),
        ),
      );
      await t.enterText(
        find.byType(TextField),
        language == 'en' ? 'Notifications' : 'Notifications',
      );
      await t.pump();
      await t.tap(find.widgetWithText(ListTile, t_('Notifications')));
      await t.pumpAndSettle();
      expect(find.text(t_(Push.status.value)), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('test/renders').createSync(recursive: true);
        File('test/renders/push_status_${ios ? 'ios' : 'cleanup'}_$language.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await t.pumpWidget(const SizedBox());
    });
  }
  }
}

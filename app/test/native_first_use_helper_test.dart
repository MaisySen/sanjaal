// Native helper navigation under a simulated keyboard. Not iOS/device proof.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/ph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/native_first_use_journey.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    loader.addFont(
      File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
    await loader.load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
    await (FontLoader(
      'NotoDev',
    )..addFont(rootBundle.load('assets/fonts/NotoSansDevanagari.ttf'))).load();
  });
  testWidgets(
    'first-use helper presents errors before capture and reaches recovery without HTTP',
    (t) async {
      var requests = 0;
      await http.runWithClient(
        () async {
          SharedPreferences.setMockInitialValues({'theme': 'light'});
          FlutterSecureStorage.setMockInitialValues({});
          prefs.lang = 'en';
          t.view.physicalSize = const Size(402, 874);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: const SanjaalApp(fontFamily: 'Roboto'),
            ),
          );
          final captures = <String>[];
          Future<void> waitUntil(bool Function() ready) async {
            for (var i = 0; i < 100; i++) {
              await t.pump(const Duration(milliseconds: 100));
              final keyboard = t.testTextInput.isVisible ? 300.0 : 0.0;
              if (t.view.viewInsets.bottom != keyboard) {
                t.view.viewInsets = FakeViewPadding(bottom: keyboard);
                await t.pump();
              }
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              if (ready()) return;
            }
            throw TestFailure('First-use widget helper did not settle');
          }

          await nativeFirstUseJourney(
            t,
            waitUntil: waitUntil,
            stage: (_) async {},
            capture: (name) async {
              captures.add(name);
              if (name == 'ios_first_use_registration_validation') {
                for (final text in [
                  'Enter a valid email',
                  'Use 3 to 30 letters, numbers, dots or underscores',
                  'At least 8 characters',
                ]) {
                  final error = find.text(text);
                  expect(error, findsOneWidget);
                  final fades = find.ancestor(
                    of: error,
                    matching: find.byType(FadeTransition),
                  );
                  for (final fade in t.widgetList<FadeTransition>(fades)) {
                    expect(
                      fade.opacity.value,
                      1.0,
                      reason: 'OS capture must not see a zero-opacity validation message',
                    );
                  }
                }
              }
              await t.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 2);
                if (name == 'ios_first_use_intro') {
                  final artwork = find.byWidgetPredicate(
                    (w) => w is PhIcon && w.icon == 'newspaper',
                  );
                  expect(artwork, findsOneWidget);
                  final rect = t.getRect(artwork);
                  final raw = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!;
                  var whiteInk = 0;
                  for (
                    var y = (rect.top * 2).ceil();
                    y < (rect.bottom * 2).floor();
                    y++
                  ) {
                    for (
                      var x = (rect.left * 2).ceil();
                      x < (rect.right * 2).floor();
                      x++
                    ) {
                      final i = (y * image.width + x) * 4;
                      if (raw.getUint8(i) > 230 &&
                          raw.getUint8(i + 1) > 230 &&
                          raw.getUint8(i + 2) > 230 &&
                          raw.getUint8(i + 3) > 230)
                        whiteInk++;
                    }
                  }
                  expect(
                    whiteInk,
                    greaterThan(30),
                    reason: 'The red introduction circle must contain rendered white artwork',
                  );
                }
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final output =
                    Platform.environment['SANJAAL_FIRST_USE_WIDGET_OUTPUT'];
                if (output != null) {
                  await Directory(output).create(recursive: true);
                  await File('$output/widget-$name.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                }
                image.dispose();
              });
            },
          );
          expect(captures, [
            'ios_first_use_intro',
            'ios_first_use_native_keyboard',
            'ios_first_use_registration_validation',
            'ios_first_use_recovery_validation',
          ]);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        },
        () => MockClient((request) async {
          requests++;
          throw StateError('First-use validation must not make HTTP requests');
        }),
      );
      expect(requests, 0);
    },
  );
}

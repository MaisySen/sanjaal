import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/stories_page.dart';
import 'profile_journey_test.dart' as review;

void main() {
  setUpAll(() async {
    for (final entry in [('Roboto', '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'), ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf')]) {
      final bytes = File(entry.$2).readAsBytesSync();
      final loader = FontLoader(entry.$1)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  for (final language in ['en', 'ne']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('story read failure is visible and retryable $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(320, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        await review.fixture(tester, (session) => Scaffold(body: SafeArea(child: StoriesBar(session: session))), () async {
          expect(find.descendant(of: find.byType(StoriesBar), matching: find.byType(TextButton)), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          await review.shot(tester, 'story-recovery-$language-${brightness.name}');
          await tester.tap(find.descendant(of: find.byType(StoriesBar), matching: find.byType(TextButton)));
          await review.flush(tester);
          expect(requests, 2);
          expect(find.descendant(of: find.byType(StoriesBar), matching: find.byType(TextButton)), findsNothing);
          expect(tester.takeException(), isNull);
        }, language: language, brightness: brightness, scale: 1.5, respond: (request) async {
          if (request.url.path.endsWith('/stories')) {
            requests++;
            return requests == 1 ? review.json({'message': 'Synthetic read failure'}, 503) : review.json({'data': []});
          }
          return review.json({});
        });
      });
    }
  }
}

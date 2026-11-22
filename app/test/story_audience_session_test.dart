import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/story_audience_page.dart';

import 'story_audience_test.dart' as h;

void main() {
  setUpAll(() async {
    Directory('test/renders').createSync(recursive: true);
    for (final f in [
      (
        'Roboto',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(f.$1)..addFont(
            File(f.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  testWidgets(
    'same-member replacement login retires story roster and its retained lookup',
    (t) async {
      var reads = 0;
      await h.fixture(
        t,
        (r) async {
          reads++;
          return h.json({
            'data': [h.person(close: true)],
            'next_cursor': null,
          });
        },
        (s) async {
          final lookup = t
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Find person'),
              )
              .onPressed!;
          await t.enterText(find.byType(TextField), 'friend');
          await s.login('same', 'fixture');
          await h.flush(t);
          expect(find.text('@friend'), findsNothing);
          expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
          lookup();
          await h.flush(t);
          expect(reads, 1);
          expect(t.takeException(), isNull);
        },
      );
    },
  );
  testWidgets(
    'retained story save cannot mutate the replacement login of same member',
    (t) async {
      var writes = 0;
      await h.fixture(
        t,
        (r) async {
          if (r.method == 'PUT') writes++;
          return r.url.path.endsWith('/friend')
              ? h.json({'member': h.person()})
              : h.json({'data': [], 'next_cursor': null});
        },
        (s) async {
          await h.open(t);
          await t.tap(find.byType(SwitchListTile).first);
          await h.flush(t);
          final oldSave = h.save(t).onPressed!;
          await s.login('same', 'fixture');
          await h.flush(t);
          oldSave();
          await h.flush(t);
          expect(writes, 0);
          expect(find.byType(SwitchListTile), findsNothing);
          expect(h.save(t).onPressed, isNull);
          expect(t.takeException(), isNull);
        },
      );
    },
  );
  for (final editor in [false, true]) {
    testWidgets(
      'late audience ${editor ? 'save' : 'read'} cannot publish after same-member replacement',
      (t) async {
        final pending = Completer<http.Response>();
        await h.fixture(
          t,
          (r) async {
            if (!editor || r.method == 'PUT') return pending.future;
            return r.url.path.endsWith('/friend')
                ? h.json({'member': h.person()})
                : h.json({'data': [], 'next_cursor': null});
          },
          (s) async {
            if (editor) {
              await h.open(t);
              await t.tap(find.byType(SwitchListTile).first);
              await h.flush(t);
              await t.tap(find.text('Save'));
              await h.flush(t);
            }
            await s.login('same', 'fixture');
            await h.flush(t);
            pending.complete(
              h.json(
                editor
                    ? {'member': h.person(close: true, revision: 1)}
                    : {
                        'data': [h.person(close: true)],
                        'next_cursor': null,
                      },
              ),
            );
            await h.flush(t);
            expect(find.text('@friend'), findsNothing);
            expect(find.text('Story audience saved.'), findsNothing);
            expect(find.byType(SwitchListTile), findsNothing);
            expect(t.takeException(), isNull);
          },
        );
      },
    );
  }
  testWidgets('returning original owner map cannot revive retired roster', (
    t,
  ) async {
    await h.fixture(
      t,
      (_) async => h.json({
        'data': [h.person(close: true)],
        'next_cursor': null,
      }),
      (s) async {
        s.user = {'public_id': 'other', 'username': 'other'};
        s.notifyListeners();
        await h.flush(t);
        s.user = {'public_id': 'me', 'username': 'me'};
        s.notifyListeners();
        await h.flush(t);
        expect(find.text('@friend'), findsNothing);
        expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      },
    );
  });
  testWidgets(
    'replacement Session with same member and generation retires retained roster state',
    (t) async {
      await h.fixture(
        t,
        (_) async => h.json({
          'data': [h.person(close: true)],
          'next_cursor': null,
        }),
        (s) async {
          final oldState = t.state(find.byType(StoryAudiencePage));
          final replacement = Session();
          await replacement.login('same', 'fixture');
          expect(replacement.generation, s.generation);
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('story-shot'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: StoryAudiencePage(session: replacement),
              ),
            ),
          );
          await h.flush(t);
          expect(
            identical(oldState, t.state(find.byType(StoryAudiencePage))),
            isTrue,
          );
          expect(find.text('@friend'), findsNothing);
          expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        },
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'retired same-member editor warning readable large text $lang',
      (t) async {
        await h.fixture(
          t,
          (r) async => r.url.path.endsWith('/friend')
              ? h.json({'member': h.person()})
              : h.json({'data': [], 'next_cursor': null}),
          (s) async {
            await h.open(t);
            await t.tap(find.byType(SwitchListTile).first);
            await h.flush(t);
            await s.login('same', 'fixture');
            await h.flush(t);
            expect(find.text('@friend'), findsNothing);
            expect(find.byType(SwitchListTile), findsNothing);
            expect(h.save(t).onPressed, isNull);
            expect(t.takeException(), isNull);
            await h.shot(t, 'story_audience_retired_$lang');
          },
          lang: lang,
          mode: lang == 'en' ? Brightness.light : Brightness.dark,
          scale: 1.8,
        );
      },
    );
  }
}

// Synthetic HTTP and widget fixtures, not live-server or native-device evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/story_audience_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Uint8List fixturePhoto;
late Uint8List headerPhoto;
http.Response json(Object value, [int code = 200]) =>
    http.Response(jsonEncode(value), code);
Map<String, dynamic> person({
  int revision = 0,
  bool close = false,
  bool hide = false,
}) => {
  'user': {'public_id': 'friend', 'username': 'friend'},
  'revision': revision,
  'close_friend': close,
  'hide_story': hide,
};
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> fixture(
  WidgetTester t,
  Future<http.Response> Function(http.Request) respond,
  Future<void> Function(Session) run, {
  bool capability = true,
  bool settings = false,
  bool compose = false,
  String lang = 'en',
  Brightness mode = Brightness.light,
  double scale = 1,
  double keyboard = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  prefs.lang = lang;
  addTearDown(() => prefs.lang = 'en');
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await http.runWithClient(
    () async {
      final s = Session();
      await s.login('fixture', 'not-a-password');
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('story-shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(
              mode,
              fontFamily: 'Roboto',
              fontFamilyFallback: ['NotoDev'],
            ),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: keyboard)),
              child: w!,
            ),
            home: settings
                ? SettingsPage(session: s)
                : compose
                ? StoryComposePage(
                    session: s,
                    file: XFile.fromData(
                      fixturePhoto,
                      path: '/fixture.png',
                      name: 'fixture.png',
                    ),
                    isVideo: false,
                  )
                : StoryAudiencePage(session: s),
          ),
        ),
      );
      await flush(t);
      await run(s);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    },
    () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token'))
        return json({
          'access_token': 'fixture',
          'expires_in': 3600,
          'refresh_token': 'fixture-refresh',
        });
      if (r.url.path.endsWith('/auth/me'))
        return json({
          'user': {'public_id': 'me', 'username': 'me'},
          'features': {
            'upload_intents': true,
            if (capability) 'protected_stories': true,
          },
        });
      return respond(r);
    }),
  );
}

Future<void> open(WidgetTester t) async {
  await t.enterText(find.byType(TextField), 'friend');
  await t.tap(find.text(t_('Find person')));
  await flush(t);
}

TextButton save(WidgetTester t) =>
    t.widget<TextButton>(find.widgetWithText(TextButton, t_('Save')));
Future<void> shot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('story-shot')),
        )
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('test/renders/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
 for(final language in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){testWidgets('story account warning stays readable and locked $language ${mode.name}',(t)async{
  await fixture(t,(_)async=>json({'data':[person(close:true)],'next_cursor':null}),(s)async{
   s.user={'public_id':'different','username':'different'};s.notifyListeners();await flush(t);expect(t.widget<TextField>(find.byType(TextField)).enabled,isFalse);expect(t.takeException(),isNull);
   await t.drag(find.byType(ListView),const Offset(0,-500));await flush(t);await shot(t,'story_account_${language}_${mode.name}');
  },lang:language,mode:mode,scale:1.8);
 });}}

  testWidgets('malformed roster identity is retryable and never opens an unknown person',(t)async{
    var reads=0;await fixture(t,(_)async=>json({'data':++reads==1?[{'user':{},'revision':0,'close_friend':true,'hide_story':false}]:[person(close:true)],'next_cursor':null}),(s)async{
      expect(find.text('Story audience could not be loaded.'),findsOneWidget);expect(find.text('@null'),findsNothing);expect(t.takeException(),isNull);
      await t.ensureVisible(find.text('Try again'));await t.tap(find.text('Try again'));await flush(t);expect(find.text('@friend'),findsOneWidget);expect(reads,2);
    });
  });
  testWidgets('account replacement hides the story roster and locks lookup',(t)async{
    await fixture(t,(_)async=>json({'data':[person(close:true)],'next_cursor':null}),(s)async{
      expect(find.text('@friend'),findsOneWidget);s.user={'public_id':'different','username':'different'};s.notifyListeners();await flush(t);
      expect(find.text('@friend'),findsNothing);expect(t.widget<TextField>(find.byType(TextField)).enabled,isFalse);expect(find.text("Sign in again to view this account's settings."),findsOneWidget);expect(t.takeException(),isNull);
    });
  });
  testWidgets('account replacement prevents changes through the previous story person editor',(t)async{
    var writes=0;await fixture(t,(r)async{if(r.method=='PUT')writes++;return r.url.path.endsWith('/friend')?json({'member':person()}):json({'data':[],'next_cursor':null});},(s)async{
      await open(t);await t.tap(find.byType(SwitchListTile).first);await flush(t);expect(save(t).onPressed,isNotNull);
      s.user={'public_id':'different','username':'different'};s.notifyListeners();await flush(t);expect(find.byType(SwitchListTile),findsNothing);expect(save(t).onPressed,isNull);expect(writes,0);expect(t.takeException(),isNull);
    });
  });
  testWidgets('late story person confirmation after account replacement cannot claim success',(t)async{
    final pending=Completer<http.Response>();var writes=0;await fixture(t,(r)async{if(r.method=='PUT'){writes++;return pending.future;}return r.url.path.endsWith('/friend')?json({'member':person()}):json({'data':[],'next_cursor':null});},(s)async{
      await open(t);await t.tap(find.byType(SwitchListTile).first);await flush(t);await t.tap(find.text('Save'));await flush(t);expect(writes,1);
      s.user={'public_id':'different','username':'different'};s.notifyListeners();pending.complete(json({'member':person(revision:1,close:true)}));await flush(t);
      expect(find.text('Story audience saved.'),findsNothing);expect(find.byType(SwitchListTile),findsNothing);expect(save(t).onPressed,isNull);expect(writes,1);expect(t.takeException(),isNull);
    });
  });

  setUpAll(() async {
    Directory('test/renders').createSync(recursive: true);
    final headerRecorder = ui.PictureRecorder();
    Canvas(headerRecorder).drawRect(
      const Rect.fromLTWH(0, 0, 160, 400),
      Paint()..color = Colors.white,
    );
    final headerImage = await headerRecorder.endRecording().toImage(160, 400);
    headerPhoto = (await headerImage.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    headerImage.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 160, 240),
      Paint()..color = const Color(0xffe9ac90),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 240)
        ..lineTo(45, 75)
        ..lineTo(110, 240)
        ..close(),
      Paint()..color = const Color(0xff334155),
    );
    canvas.drawPath(
      Path()
        ..moveTo(50, 240)
        ..lineTo(118, 55)
        ..lineTo(160, 240)
        ..close(),
      Paint()..color = const Color(0xff1e293b),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 240);
    fixturePhoto = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();

    for (final f in [
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
      final file = File(f.$2);
      if (file.existsSync()) {
        final loader = FontLoader(f.$1)
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        await loader.load();
      }
    }
  });
  for (final supported in [false, true])
    testWidgets('settings capability $supported is read from signed-in API', (
      t,
    ) async {
      await fixture(
        t,
        (_) async => json({'data': [], 'next_cursor': null}),
        (s) async {
          expect(s.protectedStoriesEnabled, supported);
          await t.enterText(find.byType(TextField), 'Story');
          await t.pump();
          expect(
            find.text('Story audience'),
            supported ? findsOneWidget : findsNothing,
          );
        },
        settings: true,
        capability: supported,
      );
    });
  testWidgets(
    'lookup must load confirmed fields before editing; PUT saves exact revision and freezes until response',
    (t) async {
      final pending = Completer<http.Response>();
      Map? body;
      var writes = 0;
      await fixture(
        t,
        (r) async {
          if (r.method == 'PUT') {
            body = jsonDecode(r.body);
            writes++;
            return pending.future;
          }
          return r.url.path.endsWith('/friend')
              ? json({'member': person(revision: 4)})
              : json({'data': [], 'next_cursor': null});
        },
        (s) async {
          await open(t);
          expect(save(t).onPressed, isNull);
          await t.tap(find.text('Close friend'));
          await flush(t);
          await t.tap(find.text('Save'));
          await flush(t);
          expect(writes, 1);
          expect(body, {
            'revision': 4,
            'close_friend': true,
            'hide_story': false,
          });
          expect(save(t).onPressed, isNull);
          expect(find.text('Story audience saved.'), findsNothing);
          expect(
            t
                .widgetList<SwitchListTile>(find.byType(SwitchListTile))
                .every((w) => w.onChanged == null),
            isTrue,
          );
          pending.complete(json({'member': person(revision: 5, close: true)}));
          await flush(t);
          expect(find.text('Story audience saved.'), findsOneWidget);
          expect(save(t).onPressed, isNull);
        },
      );
    },
  );
  for (final code in [409, 503, 0])
    testWidgets('uncertain result $code locks and reloads without replay', (
      t,
    ) async {
      var reads = 0, writes = 0;
      await fixture(
        t,
        (r) async {
          if (r.method == 'PUT') {
            writes++;
            if (code == 0) throw const SocketException('fixture loss');
            return json({'message': 'Unconfirmed fixture'}, code);
          }
          if (r.url.path.endsWith('/friend'))
            return json({'member': person(revision: reads++, hide: reads > 1)});
          return json({'data': [], 'next_cursor': null});
        },
        (s) async {
          await open(t);
          await t.tap(find.text('Close friend'));
          await flush(t);
          await t.tap(find.text('Save'));
          await flush(t);
          expect(writes, 1);
          expect(save(t).onPressed, isNull);
          expect(find.text('Story audience saved.'), findsNothing);
          await t.tap(find.text('Reload current settings'));
          await flush(t);
          expect(writes, 1);
          expect(reads, 2);
          expect(save(t).onPressed, isNull);
          expect(
            t
                .widgetList<SwitchListTile>(find.byType(SwitchListTile))
                .last
                .value,
            isTrue,
          );
        },
      );
    });
  testWidgets('failed lookup does not guess relation settings', (t) async {
    await fixture(
      t,
      (r) async => r.url.path.endsWith('/friend')
          ? json({'message': 'Lookup failed'}, 503)
          : json({'data': [], 'next_cursor': null}),
      (s) async {
        await open(t);
        expect(find.byType(SwitchListTile), findsNothing);
        expect(save(t).onPressed, isNull);
        expect(find.text('Lookup failed'), findsOneWidget);
      },
    );
  });
  testWidgets('roster pagination forwards cursor and never drops prior page', (
    t,
  ) async {
    var reads = 0;
    await fixture(
      t,
      (r) async {
        reads++;
        if (reads == 1)
          return json({
            'data': [person(close: true)],
            'next_cursor': 'page + /2',
          });
        expect(r.url.queryParameters['cursor'], 'page + /2');
        return json({
          'data': [
            {
              'user': {'username': 'second'},
              'close_friend': false,
              'hide_story': true,
              'revision': 1,
            },
          ],
          'next_cursor': null,
        });
      },
      (s) async {
        expect(find.text('@friend'), findsOneWidget);
        await t.ensureVisible(find.text('Load more'));
        await t.tap(find.text('Load more'));
        await flush(t);
        expect(find.text('@friend'), findsOneWidget);
        expect(find.text('@second'), findsOneWidget);
        expect(reads, 2);
      },
    );
  });
  testWidgets('unsupported server cannot publish a falsely protected story', (
    t,
  ) async {
    var writes = 0;
    await fixture(
      t,
      (r) async {
        writes++;
        return json({});
      },
      (s) async {
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Share story'),
              )
              .onPressed,
          isNull,
        );
        expect(writes, 0);
        expect(
          find.text(
            'Story sharing needs the protected-story server update. Your draft is still here.',
          ),
          findsOneWidget,
        );
      },
      compose: true,
      capability: false,
    );
  });
  testWidgets(
    'story audience is visible beside Share, chosen before upload and frozen across safe retry',
    (t) async {
      final payloads = <String>[];
      await fixture(
        t,
        (r) async {
          payloads.add(latin1.decode(r.bodyBytes));
          return payloads.length == 1
              ? json({'message': 'Fixture unavailable'}, 503)
              : json({
                  'story': {'public_id': 'saved'},
                }, 201);
        },
        (s) async {
          expect(find.text('Followers').hitTestable(), findsOneWidget);
          expect(payloads, isEmpty);
          await t.tap(find.byTooltip('Who can see this story'));
          await flush(t);
          await t.tap(find.text('Close friends'));
          await flush(t);
          expect(find.text('Close friends').hitTestable(), findsOneWidget);
          await t.tap(find.text('Share story'));
          await flush(t);
          expect(payloads.length, 1);
          expect(find.text('Fixture unavailable'), findsOneWidget);
          expect(
            t
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Close friends'),
                )
                .onPressed,
            isNull,
          );
          await t.tap(find.text('Try again'));
          await flush(t);
          expect(payloads.length, 2);
          for (final body in payloads) {
            expect(body, contains('name="audience"\r\n\r\nclose_friends'));
            expect(body, contains('name="protected_media"\r\n\r\n1'));
          }
        },
        compose: true,
      );
    },
  );
  testWidgets(
    'protected bytes reject foreign hosts and redirects, and refresh a 401 once',
    (t) async {
      var reads = 0;
      await fixture(
        t,
        (r) async {
          if (!r.url.path.endsWith('/media'))
            return json({'data': [], 'next_cursor': null});
          expect(r.headers['authorization'], 'Bearer fixture');
          reads++;
          return reads == 1
              ? json({'message': 'Expired'}, 401)
              : reads == 2
              ? http.Response('image bytes', 200)
              : http.Response(
                  '',
                  302,
                  headers: {'location': 'https://unrelated.invalid/private'},
                );
        },
        (s) async {
          await expectLater(
            s.privateMediaHeaders('https://unrelated.invalid/private'),
            throwsA(isA<ApiError>()),
          );
          expect(reads, 0);
          expect(
            utf8.decode(
              await s.fetchProtectedBytes('$apiBase/stories/id/media'),
            ),
            'image bytes',
          );
          expect(reads, 2);
          await expectLater(
            s.fetchProtectedBytes('$apiBase/stories/id/media'),
            throwsA(isA<ApiError>()),
          );
          expect(reads, 3);
        },
      );
    },
  );
  testWidgets(
    'protected story denial is explicit, does not auto-advance and retries only on tap',
    (t) async {
      var reads = 0;
      await fixture(
        t,
        (r) async {
          if (r.url.path.endsWith('/media')) {
            reads++;
            return json({'message': 'Not found'}, 404);
          }
          return json({});
        },
        (s) async {
          await t.pumpWidget(
            MaterialApp(
              home: StoryViewer(
                session: s,
                group: {
                  'author': {'username': 'friend'},
                  'items': [
                    {
                      'public_id': 'story',
                      'url': '$apiBase/stories/story/media',
                      'protected_media': true,
                      'type': 'image',
                      'created_at': '2026-11-17T00:00:00Z',
                    },
                  ],
                },
              ),
            ),
          );
          await flush(t);
          expect(
            find.text(
              'This story is unavailable. It may have expired or its audience changed.',
            ),
            findsOneWidget,
          );
          expect(reads, 1);
          await t.pump(const Duration(seconds: 10));
          expect(reads, 1);
          expect(find.byType(StoryViewer), findsOneWidget);
          await t.tap(find.text('Try again'));
          await flush(t);
          expect(reads, 2);
          expect(t.takeException(), isNull);
        },
      );
    },
  );
  for (final lang in ['en', 'ne'])
    testWidgets(
      'large-text composer keeps audience visible and sheet usable $lang',
      (t) async {
        await fixture(
          t,
          (_) async => json({}),
          (s) async {
            expect(find.text(t_('Followers')).hitTestable(), findsOneWidget);
            expect(t.takeException(), isNull);
            final caption=find.byType(TextField);
            await t.scrollUntilVisible(caption,100,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();await t.tap(caption);await t.pumpAndSettle();
            await t.ensureVisible(caption);await t.pumpAndSettle();
            await t.enterText(caption,'Synthetic caption');
            expect(caption.hitTestable(),findsOneWidget);
            expect(t.getRect(caption).bottom,lessThanOrEqualTo(400));
            final share=find.widgetWithText(FilledButton,t_('Share story'));
            expect(share.hitTestable(),findsOneWidget);
            expect(t.getRect(share).bottom,lessThanOrEqualTo(400));
            await shot(t, 'story_composer_keyboard_$lang');
            await shot(t, 'story_composer_large_$lang');
            await t.tap(find.byTooltip(t_('Who can see this story')));
            await flush(t);
            expect(t.takeException(), isNull);
            await shot(t, 'story_choices_large_$lang');
            await t.ensureVisible(find.text(t_('Only me')));
            await t.tap(find.text(t_('Only me')));
            await flush(t);
            expect(find.text(t_('Only me')).hitTestable(), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          compose: true,
          lang: lang,
          scale: 1.8,
          keyboard: 240,
        );
      },
    );
  for (final owner in [false, true]) {
    for (final language in ['en', 'ne']) {
      testWidgets(
        'long story header keeps identity time and controls separate $language owner $owner',
        (t) async {
          await fixture(
            t,
            (r) async => r.url.path.endsWith('/media')
                ? http.Response.bytes(
                    headerPhoto,
                    200,
                    headers: {'content-type': 'image/png'},
                  )
                : json({}),
            (session) async {
              if (owner)
                session.user!['username'] = 'a_very_long_synthetic_username';
              await t.pumpWidget(
                RepaintBoundary(
                  key: const ValueKey('story-shot'),
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildTheme(
                      Brightness.dark,
                      fontFamily: 'Roboto',
                      fontFamilyFallback: ['NotoDev'],
                    ),
                    builder: (c, w) => MediaQuery(
                      data: MediaQuery.of(c)
                          .copyWith(textScaler: TextScaler.linear(1.8)),
                      child: w!,
                    ),
                    home: StoryViewer(
                      session: session,
                      group: {
                        'author': {
                          'public_id': 'me',
                          'username': 'a_very_long_synthetic_username',
                        },
                        'items': [
                          {
                            'public_id': 'header-fixture',
                            'url': '$apiBase/stories/header/media',
                            'protected_media': true,
                            'type': 'image',
                            'created_at': '2026-11-17T00:00:00Z',
                          },
                        ],
                      },
                    ),
                  ),
                ),
              );
              await flush(t);
              expect(t.takeException(), isNull);
              await flush(t);
              expect(
                t
                    .widgetList<RawImage>(find.byType(RawImage))
                    .any(
                      (image) =>
                          image.image?.width == 160 &&
                          image.image?.height == 400,
                    ),
                isTrue,
              );
              final text = t.widget<Text>(
                find.text('a_very_long_synthetic_username'),
              );
              expect(
                t.getSize(
                  find.byWidgetPredicate(
                    (w) =>
                        w is RawImage &&
                        w.image?.width == 160 &&
                        w.image?.height == 400,
                  ),
                ),
                const Size(320, 640),
              );
              expect(text.maxLines, 1);
              expect(text.overflow, TextOverflow.ellipsis);
              expect(
                find.byType(IconButton).hitTestable(),
                findsNWidgets(owner ? 3 : 1),
              );
              expect(find.byTooltip(t_('Close')).hitTestable(), findsOneWidget);
              if (owner) {
                expect(
                  find.byTooltip(t_('Story viewers')).hitTestable(),
                  findsOneWidget,
                );
                expect(
                  find.byTooltip(t_('Delete story')).hitTestable(),
                  findsOneWidget,
                );
              }
              await shot(t, 'story_header_long_${language}_$owner');
            },
            lang: language,
          );
        },
      );
    }
  }
  for (final mode in [Brightness.light, Brightness.dark])
    for (final lang in ['en', 'ne'])
      testWidgets(
        'small large-text audience list and person ${mode.name} $lang',
        (t) async {
          await fixture(
            t,
            (r) async => r.url.path.endsWith('/friend')
                ? json({'member': person(close: true, hide: true)})
                : json({
                    'data': [person(close: true, hide: true)],
                    'next_cursor': null,
                  }),
            (s) async {
              expect(t.takeException(), isNull);
              await shot(t, 'story_audience_${mode.name}_$lang');
              await t.ensureVisible(find.text(t_('Find person')));
              await open(t);
              expect(t.takeException(), isNull);
              await shot(t, 'story_person_${mode.name}_$lang');
              await t.drag(find.byType(ListView).last, const Offset(0, -500));
              await flush(t);
              expect(t.takeException(), isNull);
              await shot(t, 'story_person_${mode.name}_${lang}_bottom');
            },
            mode: mode,
            lang: lang,
            scale: 1.8,
          );
        },
      );
}

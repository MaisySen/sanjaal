import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/discovery_consent_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

class ConsentSession extends Session {
  int epoch = 0, writes = 0, reads = 0;
  bool consent = false;
  int revision = 0;
  Completer<dynamic>? pending;
  bool malformed = false, failRead = false;
  ConsentSession() {
    user = {'public_id': 'owner'};
    loading = false;
  }
  @override
  int get generation => epoch;
  void relogin() {
    epoch++;
    notifyListeners();
  }

  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path != '/posts/fixture/discovery') {
      throw StateError('Unexpected fixture route');
    }
    if (method == 'GET') {
      reads++;
      if (failRead) throw ApiError('fixture unavailable', 503);
      return {
        'discovery': {
          'author_opted_in': consent,
          'revision': revision,
          'public_post': false,
          'moderation': 'pending',
        },
      };
    }
    if (method != 'PUT') throw StateError('Unexpected mutation');
    writes++;
    if (pending != null) return pending!.future;
    if (malformed) {
      return {
        'discovery': {'author_opted_in': true},
      };
    }
    expect(body!.keys.toSet(), {'author_opted_in', 'revision'});
    expect(body['revision'], revision);
    consent = body['author_opted_in'];
    revision++;
    return {
      'discovery': {
        'author_opted_in': consent,
        'revision': revision,
        'public_post': false,
        'moderation': 'pending',
      },
    };
  }
}

Future<void> mount(
  WidgetTester t,
  ConsentSession session, {
  double scale = 1,
  Brightness mode = Brightness.light,
  GlobalKey? key,
  double width = 320,
  String lang = 'en',
}) async {
  t.view.physicalSize = Size(width, 844);
  prefs.lang = lang;
  addTearDown(() => prefs.lang = 'en');
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
          mode,
          fontFamily: lang == 'ne' ? 'NotoDev' : 'Roboto',
        ),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: DiscoveryConsentPage(session: session, postId: 'fixture'),
      ),
    ),
  );
  await t.pumpAndSettle();
}

class RealResponseConsentSession extends ConsentSession {
  RealResponseConsentSession(this.responses);
  final Map<String, dynamic> responses;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'GET') {
      reads++;
      return responses['initial'];
    }
    expect(method, 'PUT');
    writes++;
    expect(body!['revision'], writes - 1);
    return responses[writes == 1 ? 'save' : 'optout'];
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(
        File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await font.load();
    final nepali = FontLoader('NotoDev')
      ..addFont(
        File('assets/fonts/NotoSansDevanagari.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await nepali.load();
  });
  testWidgets('consent save never represents pending review as approved', (
    t,
  ) async {
    final s = ConsentSession();
    await mount(t, s);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('Public visibility not confirmed'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.writes, 1);
    expect(find.text('Your choice is saved.'), findsOneWidget);
    expect(s.consent, isTrue);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('Review approved'), findsNothing);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  for (final outcome in ['failure', 'malformed']) {
    testWidgets('$outcome save locks further edits until explicit reload', (
      t,
    ) async {
      final s = ConsentSession();
      if (outcome == 'failure') {
        s.pending = Completer();
      } else {
        s.malformed = true;
      }
      await mount(t, s);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pump();
      if (outcome == 'failure') {
        s.pending!.completeError(ApiError('stale', 409));
      }
      await t.pumpAndSettle();
      expect(s.writes, 1);
      expect(
        find.text('Reload these settings before making another change.'),
        findsOneWidget,
      );
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await t.tap(find.text('Reload'));
      await t.pumpAndSettle();
      expect(s.reads, 2);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(s.writes, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'pending save cannot repeat and late result clears on same-member login',
    (t) async {
      final s = ConsentSession()..pending = Completer();
      await mount(t, s);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pump();
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(s.writes, 1);
      s.relogin();
      await t.pump();
      expect(find.byType(Switch), findsNothing);
      s.pending!.complete({
        'discovery': {
          'author_opted_in': true,
          'revision': 1,
          'public_post': false,
          'moderation': 'pending',
        },
      });
      await t.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual Laravel consent HTTP bodies survive two explicit screen saves',
    (t) async {
      final capture = Platform.environment['DISCOVERY_CONSENT_CAPTURE'];
      final s = RealResponseConsentSession(
        jsonDecode(File(capture!).readAsStringSync()) as Map<String, dynamic>,
      );
      await mount(t, s);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(s.writes, 1);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Your choice is saved.'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('Your choice is saved.'), findsNothing);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(s.writes, 2);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Public visibility not confirmed'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
    skip: Platform.environment['DISCOVERY_CONSENT_CAPTURE'] == null,
  );
  testWidgets('dirty exit is explicit and pending save cannot be dismissed', (
    t,
  ) async {
    final s = ConsentSession()..pending = Completer();
    await mount(t, s);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Discard these changes?'), findsOneWidget);
    expect(
      find.text('Your unsaved Discovery choice will be lost.'),
      findsOneWidget,
    );
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(s.writes, 0);
    await t.tap(find.text('Save'));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Your settings are still updating.'), findsOneWidget);
    expect(find.text('Discard these changes?'), findsNothing);
    expect(s.writes, 1);
    s.pending!.completeError(ApiError('fixture failed', 503));
    await t.pumpAndSettle();
    expect(find.text('Your choice is saved.'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('failed initial GET never invents a consent value', (t) async {
    final s = ConsentSession()..failRead = true;
    await mount(t, s);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(
      find.text('Discovery settings could not be loaded.'),
      findsOneWidget,
    );
    s.failRead = false;
    await t.tap(find.text('Reload'));
    await t.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(s.writes, 0);
    await t.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final mode in [Brightness.light, Brightness.dark]) {
        testWidgets('consent layout $width $scale ${mode.name}', (t) async {
          final s = ConsentSession(), key = GlobalKey();
          await mount(
            t,
            s,
            scale: scale,
            mode: mode,
            key: key,
            width: width,
            lang: width == 320 ? 'ne' : 'en',
          );
          expect(t.takeException(), isNull);
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory('/downloads/sanjaal-discovery-review')
                .createSync(recursive: true);
            File(
              '/downloads/sanjaal-discovery-review/consent-$width-$scale-${mode.name}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
          await t.drag(find.byType(ListView), const Offset(0, -500));
          await t.pumpAndSettle();
          expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}

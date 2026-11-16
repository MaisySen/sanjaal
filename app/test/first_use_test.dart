// First-use journey and direct empty-state actions. Synthetic data, no live writes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/onboarding_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final roboto = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final file = File('$root/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf');
      if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await roboto.load();
    final loader = FontLoader('NotoDev');
    loader.addFont(rootBundle.load('assets/fonts/NotoSansDevanagari.ttf'));
    await loader.load();
  });

  for (final lang in ['en', 'ne']) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('welcome 320x640 $lang $scale scrolls to account action', (tester) async {
        SharedPreferences.setMockInitialValues({});
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        bool? selected;
        await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
          home: OnboardingPage(onContinue: (create) => selected = create),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final create = find.widgetWithText(FilledButton, t_('Create an account'));
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        final rect = tester.getRect(create);
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.bottom, lessThanOrEqualTo(640));
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('test/renders/welcome_small_${lang}_$scale.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        await tester.tap(create);
        expect(selected, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('actual app welcome opens registration directly without a request', (tester) async {
    SharedPreferences.setMockInitialValues({});
    prefs.lang = 'en';
    await tester.pumpWidget(const SanjaalApp());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create an account'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Make yourself at home'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    await tester.ensureVisible(find.text('I already have an account'));
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty feed action appears only after successful empty load, not an error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session();
    var fail = false;
    var actions = 0;
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-real-password');
      Future<void> show() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeedList(
          key: UniqueKey(), session: session, query: const {}, emptyTitle: 'Fixture empty',
          emptyAction: FilledButton(onPressed: () => actions++, child: const Text('Create fixture')),
        ))));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pumpAndSettle();
      }
      await show();
      expect(find.text('Fixture empty'), findsOneWidget);
      await tester.tap(find.text('Create fixture'));
      expect(actions, 1);
      fail = true;
      await show();
      expect(find.text('Create fixture'), findsNothing);
      expect(find.text('Fixture empty'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return http.Response(jsonEncode({'access_token': 'fixture', 'expires_in': 3600}), 200);
      if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user': {'public_id': 'fixture'}}), 200);
      return http.Response(jsonEncode(fail ? {'message': 'Fixture load failed'} : {'data': [], 'next_cursor': null}), fail ? 500 : 200);
    }));
  });
  testWidgets('refresh requested during an in-flight load is not dropped', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session();
    final first = Completer<http.Response>();
    var reads = 0;
    final key = GlobalKey<FeedListState>();
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-real-password');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeedList(key: key, session: session, query: const {}))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      expect(reads, 1);
      await key.currentState!.load(refresh: true);
      first.complete(http.Response(jsonEncode({'data': [], 'next_cursor': null}), 200));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(reads, 2, reason: 'a publish/refresh arriving during a load must get a fresh response');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return http.Response(jsonEncode({'access_token': 'fixture', 'expires_in': 3600}), 200);
      if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user': {'public_id': 'fixture'}}), 200);
      reads++;
      if (reads == 1) return first.future;
      return http.Response(jsonEncode({'data': [], 'next_cursor': null}), 200);
    }));
  });

  testWidgets('publishing revision refreshes own profile posts and counts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session();
    var posts = 0;
    var profiles = 0;
    await http.runWithClient(() async {
      await session.login('fixture', 'not-a-real-password');
      Future<void> show(int revision) async {
        await tester.pumpWidget(MaterialApp(home: MePage(session: session, contentRevision: revision)));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pumpAndSettle();
      }
      await show(0);
      expect(posts, 1);
      expect(profiles, 1);
      await show(1);
      expect(posts, 2);
      expect(profiles, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) return http.Response(jsonEncode({'access_token': 'fixture', 'expires_in': 3600}), 200);
      if (r.url.path.endsWith('/auth/me')) return http.Response(jsonEncode({'user': {'public_id': 'fixture', 'username': 'fixture'}}), 200);
      if (r.url.path.contains('/users/')) {
        profiles++;
        return http.Response(jsonEncode({'user': {'public_id': 'fixture', 'username': 'fixture', 'posts_count': profiles}}), 200);
      }
      posts++;
      return http.Response(jsonEncode({'data': [], 'next_cursor': null}), 200);
    }));
  });

}

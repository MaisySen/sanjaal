// Capability and routing fixtures only. No deployed service or account access.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/discovery_entry.dart';
import 'package:sanjaal/discovery_route.dart';
import 'package:sanjaal/discovery_consent_page.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/main.dart' show buildTheme, HomeShell;

class EntrySession extends Session {
  final calls = <String>[];
  EntrySession(bool enabled) {
    user = {'public_id': 'owner', 'username': 'owner'};
    loading = false;
    discoveryEnabled = enabled;
  }
  void withdraw() {
    discoveryEnabled = false;
    notifyListeners();
  }

  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add('$method $path${query?.isEmpty ?? true ? '' : query}');
    if (method != 'GET') throw StateError('No writes in entry fixtures');
    if (path == '/discovery') {
      return {
        'contract': 'discovery_v1',
        'version': 'fixture',
        'data': [],
        'next_cursor': null,
      };
    }
    if (path == '/posts/fixture/discovery') {
      return {
        'discovery': {
          'author_opted_in': false,
          'revision': 0,
          'moderation': 'pending',
          'public_post': false,
        },
      };
    }
    return {'data': [], 'next_cursor': null, 'unread_messages': 0};
  }
}

Map<String, dynamic> fixturePost(String owner) => {
  'public_id': 'fixture',
  'kind': 'post',
  'body': 'Local fixture post',
  'media': [],
  'hashtags': [],
  'created_at': '2026-11-21T00:00:00Z',
  'author': {'public_id': owner, 'username': owner, 'name': 'Fixture member'},
  'likes_count': 0,
  'comments_count': 0,
};
Future<void> captureEntry(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/downloads/sanjaal-discovery-review/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final capability in [null, false, 'true', 1, true]) {
    test(
      'only explicit v1 boolean capability enables entry: $capability (${capability.runtimeType})',
      () async {
        await http.runWithClient(
          () async {
            final s = Session(unregisterPush: (_) async {});
            await s.login('fixture', 'not-a-password');
            expect(s.discoveryEnabled, capability == true);
            expect(
              discoveryEntry(s),
              capability == true ? isA<DiscoveryRoute>() : isA<SearchPage>(),
            );
            await s.logout();
            expect(s.discoveryEnabled, isFalse);
            s.dispose();
          },
          () => MockClient(
            (r) async => http.Response(
              jsonEncode(
                r.url.path.endsWith('/oauth/token')
                    ? {'access_token': 'fixture', 'expires_in': 3600}
                    : {
                        'features': {'discovery_v1': ?capability},
                        'user': {'public_id': 'owner', 'username': 'owner'},
                      },
              ),
              200,
            ),
          ),
        );
      },
    );
  }
  for (final enabled in [false, true]) {
    testWidgets(
      'Home search routes with service capability $enabled without startup Discovery fetch',
      (t) async {
        final s = EntrySession(enabled);
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
            home: HomeShell(session: s),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(s.calls.where((x) => x.contains('/discovery')), isEmpty);
        await t.tap(find.byTooltip('Search').first);
        await t.pumpAndSettle();
        expect(
          find.byType(enabled ? DiscoveryRoute : SearchPage),
          findsOneWidget,
        );
        expect(
          s.calls.where((x) => x.contains('/discovery')).length,
          enabled ? 1 : 0,
        );
        if (enabled) {
          await t.tap(find.text('Reels'));
          await t.pumpAndSettle();
          expect(s.calls.last, contains('kind: reel'));
          await t.tap(find.byTooltip('Search'));
          await t.pumpAndSettle();
          expect(find.byType(SearchPage), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        s.dispose();
      },
    );
  }
  testWidgets(
    'service withdrawal retires an already opened grid without another read',
    (t) async {
      final s = EntrySession(true);
      await t.pumpWidget(
        MaterialApp(debugShowCheckedModeBanner: false, home: discoveryEntry(s)),
      );
      await t.pumpAndSettle();
      expect(s.calls.length, 1);
      s.withdraw();
      await t.pumpAndSettle();
      expect(
        find.text(
          'Discovery is unavailable. Close this view and open Search again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reels'), findsNothing);
      expect(s.calls.length, 1);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  for (final enabled in [false, true]) {
    for (final mine in [false, true]) {
      testWidgets(
        'post settings require capability $enabled and current author $mine',
        (t) async {
          t.view.physicalSize = const Size(390, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final s = EntrySession(enabled), key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
                home: Scaffold(
                  body: PostCard(
                    session: s,
                    post: fixturePost(mine ? 'owner' : 'other'),
                    onRemoved: () {},
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byType(PopupMenuButton<String>));
          await t.pumpAndSettle();
          expect(
            find.text('Discovery settings'),
            enabled && mine ? findsOneWidget : findsNothing,
          );
          if (enabled && mine) {
            await captureEntry(t, key, 'entry-owner-menu');
            await t.tap(find.text('Discovery settings'));
            await t.pumpAndSettle();
            expect(find.byType(DiscoveryConsentPage), findsOneWidget);
            expect(find.byType(Switch), findsOneWidget);
            await captureEntry(t, key, 'entry-consent-pending');
            expect(s.calls, ['GET /posts/fixture/discovery']);
            s.withdraw();
            await t.pumpAndSettle();
            expect(find.byType(Switch), findsNothing);
            expect(s.calls.length, 1);
          }
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          s.dispose();
        },
      );
    }
  }
}

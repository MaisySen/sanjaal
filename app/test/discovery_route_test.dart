// Real existing route classes with local HTTP-shaped data, never live accounts.
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:sanjaal/media_visibility.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/discovery_route.dart';
import 'package:sanjaal/discovery_page.dart';
import 'package:sanjaal/discovery_contract.dart';
import 'package:sanjaal/discovery_paging.dart';
import 'package:sanjaal/discovery_preview.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;

class RouteSession extends Session {
  final reads = <String>[];
  bool allowBlock = false;
  int blocks = 0;
  RouteSession() {
    user = {'public_id': 'owner', 'username': 'owner'};
    loading = false;
  }
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'POST' && allowBlock && path == '/users/other/block') {
      blocks++;
      return <String, dynamic>{};
    }
    if (method != 'GET') throw StateError('No writes in route review');
    reads.add(path);
    if (path == '/posts/fixture-post') {
      return {
        'post': {
          'public_id': 'fixture-post',
          'kind': 'post',
          'body': 'Opened actual detail',
          'author': {
            'public_id': 'other',
            'username': 'other',
            'name': 'Other',
          },
          'media': [],
          'hashtags': [],
          'likes_count': 0,
          'comments_count': 0,
          'created_at': '2026-11-21T00:00:00Z',
        },
      };
    }
    return {'data': [], 'next_cursor': null};
  }
}

Future<void> captureFreshness(
  WidgetTester t,
  GlobalKey key,
  String suffix,
) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/downloads/sanjaal-discovery-review/freshness-$suffix.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
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
  });
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  testWidgets(
    'host preserves fresh grid on normal Search/Post return without refetch',
    (t) async {
      var reads = 0;
      final s = RouteSession(),
          bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
              .readAsBytesSync();
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DiscoveryRoute(
            session: s,
            read: (q, c) async {
              reads++;
              return DiscoveryPageData(
                items: [
                  DiscoveryTile(
                    id: 'fixture-post',
                    caption: 'Fixture tile',
                    preview: DiscoveryPreview(
                      url: Uri.parse(
                        'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                      ),
                      video: false,
                    ),
                  ),
                ],
                nextCursor: null,
                version: 'fixture',
              );
            },
            imageProvider: (_) => MemoryImage(bytes),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Fixture tile'));
      await t.pumpAndSettle();
      expect(find.byType(PostPage), findsOneWidget);
      expect(find.text('Opened actual detail'), findsOneWidget);
      expect(s.reads, contains('/posts/fixture-post'));
      await t.pageBack();
      await t.pumpAndSettle();
      expect(reads, 1);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(DiscoveryRoute), findsOneWidget);
      expect(reads, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  testWidgets(
    'detail visibility invalidation clears cached tiles even if revalidation fails',
    (t) async {
      var reads = 0;
      final s = RouteSession();
      final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
          .readAsBytesSync();
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DiscoveryRoute(
            session: s,
            imageProvider: (_) => MemoryImage(bytes),
            read: (q, c) async {
              reads++;
              if (reads > 1) throw ApiError('fixture unavailable', 503);
              return DiscoveryPageData(
                items: [
                  DiscoveryTile(
                    id: 'fixture-post',
                    caption: 'Before visibility change',
                    preview: DiscoveryPreview(
                      url: Uri.parse(
                        'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                      ),
                      video: false,
                    ),
                  ),
                ],
                nextCursor: null,
                version: 'fixture',
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Before visibility change'));
      await t.pumpAndSettle();
      final detail = t.widget<PostPage>(find.byType(PostPage));
      expect(detail.onVisibilityChanged, isNotNull);
      detail.onVisibilityChanged!();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(reads, 2);
      expect(find.bySemanticsLabel('Before visibility change'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual detail Block removes the grid preview before a failed reload',
    (t) async {
      var reads = 0;
      final s = RouteSession()..allowBlock = true;
      final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
          .readAsBytesSync();
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DiscoveryRoute(
            session: s,
            imageProvider: (_) => MemoryImage(bytes),
            read: (q, c) async {
              reads++;
              if (reads > 1) throw ApiError('fixture unavailable', 503);
              return DiscoveryPageData(
                items: [
                  DiscoveryTile(
                    id: 'fixture-post',
                    caption: 'Block this fixture',
                    preview: DiscoveryPreview(
                      url: Uri.parse(
                        'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                      ),
                      video: false,
                    ),
                  ),
                ],
                nextCursor: null,
                version: 'fixture',
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Block this fixture'));
      await t.pumpAndSettle();
      await t.tap(find.byType(PopupMenuButton<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Block'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Block'));
      await t.pumpAndSettle();
      expect(s.blocks, 1);
      expect(reads, 1);
      expect(find.text('Post unavailable'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(reads, 2);
      expect(find.bySemanticsLabel('Block this fixture'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final outcome in ['removed', 'failure', 'late']) {
    testWidgets(
      'freshness expiry clears remote $outcome without retaining stale pixels',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        var reads = 0;
        final pending = Completer<DiscoveryPageData<DiscoveryTile>>(),
            s = RouteSession();
        final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
            .readAsBytesSync();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
              home: DiscoveryRoute(
                session: s,
                freshness: const Duration(seconds: 10),
                imageProvider: (_) => MemoryImage(bytes),
                read: (q, c) async {
                  reads++;
                  if (reads == 1) {
                    return DiscoveryPageData(
                      items: [
                        DiscoveryTile(
                          id: 'fixture-post',
                          caption: 'Remote stale tile',
                          preview: DiscoveryPreview(
                            url: Uri.parse(
                              'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                            ),
                            video: false,
                          ),
                        ),
                      ],
                      nextCursor: null,
                      version: 'fixture',
                    );
                  }
                  if (outcome == 'failure') {
                    throw ApiError('fixture unavailable', 503);
                  }
                  if (outcome == 'late') return pending.future;
                  return DiscoveryPageData(
                    items: [],
                    nextCursor: null,
                    version: 'fixture',
                  );
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel('Remote stale tile'), findsOneWidget);
        if (outcome == 'failure') {
          for (var i = 0; i < 3; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await t.pump();
          }
          expect(
            t
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image != null),
            isTrue,
          );
          await captureFreshness(t, key, 'before');
        }
        await t.pump(const Duration(seconds: 11));
        await t.pump();
        expect(reads, 2);
        expect(find.bySemanticsLabel('Remote stale tile'), findsNothing);
        if (outcome == 'failure') {
          await t.pumpAndSettle();
          await captureFreshness(t, key, 'expired-offline');
        }
        if (outcome == 'late') {
          pending.complete(
            DiscoveryPageData(items: [], nextCursor: null, version: 'fixture'),
          );
          await t.pumpAndSettle();
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 30));
        expect(reads, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('background clears cached previews and does no IO until resume', (
    t,
  ) async {
    var reads = 0;
    final s = RouteSession(),
        bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
            .readAsBytesSync();
    addTearDown(
      () => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    await t.pumpWidget(
      MaterialApp(
        navigatorObservers: [mediaRoutes],
        home: DiscoveryRoute(
          session: s,
          freshness: const Duration(seconds: 10),
          imageProvider: (_) => MemoryImage(bytes),
          read: (q, c) async {
            reads++;
            return DiscoveryPageData(
              items: reads == 1
                  ? [
                      DiscoveryTile(
                        id: 'fixture-post',
                        caption: 'Before background',
                        preview: DiscoveryPreview(
                          url: Uri.parse(
                            'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                          ),
                          video: false,
                        ),
                      ),
                    ]
                  : [],
              nextCursor: null,
              version: 'fixture',
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(reads, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    await t.pump();
    expect(
      t.widget<DiscoveryPage>(find.byType(DiscoveryPage)).pager.items,
      isEmpty,
    );
    await t.pump(const Duration(minutes: 5));
    expect(reads, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(reads, 2);
    expect(find.bySemanticsLabel('Before background'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed retained refresh cannot cancel an older freshness deadline',
    (t) async {
      var reads = 0;
      final pending = Completer<DiscoveryPageData<DiscoveryTile>>(),
          s = RouteSession(),
          bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
              .readAsBytesSync();
      await t.pumpWidget(
        MaterialApp(
          home: DiscoveryRoute(
            session: s,
            freshness: const Duration(seconds: 10),
            imageProvider: (_) => MemoryImage(bytes),
            read: (q, c) async {
              reads++;
              if (reads == 1) {
                return DiscoveryPageData(
                  items: [
                    DiscoveryTile(
                      id: 'fixture-post',
                      caption: 'Must expire',
                      preview: DiscoveryPreview(
                        url: Uri.parse(
                          'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                        ),
                        video: false,
                      ),
                    ),
                  ],
                  nextCursor: null,
                  version: 'fixture',
                );
              }
              if (reads == 2) return pending.future;
              throw ApiError('fixture unavailable', 503);
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final p = t.widget<DiscoveryPage>(find.byType(DiscoveryPage)).pager;
      final refresh = p.reset(p.query, retain: true);
      await t.pump();
      expect(reads, 2);
      expect(p.items.length, 1);
      await t.pump(const Duration(seconds: 11));
      expect(p.items, isEmpty);
      expect(reads, 2);
      pending.completeError(ApiError('fixture failed', 503));
      await refresh;
      await t.pumpAndSettle();
      expect(reads, 3);
      expect(p.items, isEmpty);
      expect(p.error, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final invalidation in ['expiry', 'background']) {
    testWidgets(
      'covered route makes no $invalidation requests and revalidates on return',
      (t) async {
        var reads = 0;
        final s = RouteSession();
        final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
            .readAsBytesSync();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [mediaRoutes],
            home: DiscoveryRoute(
              session: s,
              freshness: const Duration(seconds: 10),
              imageProvider: (_) => MemoryImage(bytes),
              read: (q, c) async {
                reads++;
                return DiscoveryPageData(
                  items: reads == 1
                      ? [
                          DiscoveryTile(
                            id: 'fixture-post',
                            caption: 'Covered fresh tile',
                            preview: DiscoveryPreview(
                              url: Uri.parse(
                                'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                              ),
                              video: false,
                            ),
                          ),
                        ]
                      : [],
                  nextCursor: null,
                  version: 'fixture',
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        final pager = t.widget<DiscoveryPage>(find.byType(DiscoveryPage)).pager;
        expect(pager.items.length, 1);
        await t.tap(find.byTooltip('Search'));
        await t.pumpAndSettle();
        final before = s.reads.length;
        if (invalidation == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
          await t.pump();
          expect(
            pager.items,
            isEmpty,
            reason: 'already covered route must clear on background, not wait for expiry',
          );
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpAndSettle();
        } else {
          await t.pump(const Duration(minutes: 3));
        }
        expect(pager.items, isEmpty);
        expect(reads, 1);
        expect(s.reads.length, before);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(reads, 2);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'first response older than its freshness budget is never displayed',
    (t) async {
      final pending = Completer<DiscoveryPageData<DiscoveryTile>>();
      var reads = 0;
      await t.pumpWidget(
        MaterialApp(
          home: DiscoveryRoute(
            session: RouteSession(),
            freshness: const Duration(seconds: 5),
            read: (q, c) {
              reads++;
              return pending.future;
            },
          ),
        ),
      );
      await t.pump();
      expect(reads, 1);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5100)),
      );
      pending.complete(
        DiscoveryPageData(
          items: [
            DiscoveryTile(
              id: 'expired-first',
              caption: 'Must never display',
              preview: DiscoveryPreview(
                url: Uri.parse(
                  'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
                ),
                video: false,
              ),
            ),
          ],
          nextCursor: null,
          version: 'fixture',
        ),
      );
      await t.pumpAndSettle();
      final pager = t.widget<DiscoveryPage>(find.byType(DiscoveryPage)).pager;
      expect(pager.items, isEmpty);
      expect(pager.error, isA<StateError>());
      expect(find.bySemanticsLabel('Must never display'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      await t.pump(const Duration(minutes: 2));
      expect(reads, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}

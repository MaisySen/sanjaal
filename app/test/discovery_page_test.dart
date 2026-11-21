// Proposed Discovery UI over a strict local fixture contract. No real inventory.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/discovery_page.dart';
import 'package:sanjaal/discovery_paging.dart';
import 'package:sanjaal/discovery_contract.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

DiscoveryPageData<DiscoveryTile> fixture(
  String? kind, {
  int start = 0,
  String? cursor,
}) => parseDiscoveryPage(
  {
    'contract': 'discovery_v1',
    'version': 'fixture-v1',
    'next_cursor': cursor,
    'data': [
      for (var i = start; i < start + 12; i++)
        {
          'public_id': 'fixture-$i',
          'kind': kind ?? (i.isEven ? 'post' : 'reel'),
          'body': 'Review moment ${i + 1}',
          'media': [
            {
              'type': kind == 'reel' || (kind == null && i.isOdd)
                  ? 'video'
                  : 'image',
              'url':
                  'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'thumbnail_url':
                  'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            },
          ],
          'discovery': {
            'author_opted_in': true,
            'moderation': 'approved',
            'public_post': true,
            'private_bytes': false,
            'blocked_either_way': false,
            'deleted': false,
          },
        },
    ],
  },
  apiBase: Uri.parse('https://fixture.invalid/api/v1'),
  maxPageSize: 15,
);
Future<void> shot(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/downloads/sanjaal-discovery-review')
        .createSync(recursive: true);
    File('/downloads/sanjaal-discovery-review/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    for (final entry in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final font = FontLoader(entry.$1)
        ..addFont(
          File(entry.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
    }
  });
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('proposed grid interactions $width $scale dark=$dark', (
          t,
        ) async {
          t.view.physicalSize = Size(width, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          prefs.lang = width == 320 ? 'ne' : 'en';
          addTearDown(() => prefs.lang = 'en');
          final images = [
            for (final name in ['mountain', 'patan-bell', 'cat'])
              File('/downloads/sanjaal-highfidelity/$name.jpg')
                  .readAsBytesSync(),
          ];
          final queries = <Map<String, String>>[], opened = <String>[];
          var searches = 0, active = true;
          final pager = DiscoveryPaging<DiscoveryTile>(
            read: (q, c) async {
              queries.add(q);
              return fixture(q['kind']);
            },
            keyOf: (x) => x.id,
            ownerActive: () => active,
            maxItems: 60,
            maxPageSize: 15,
          );
          addTearDown(pager.dispose);
          final key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(
                  dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'Roboto',
                  fontFamilyFallback: ['NotoDev'],
                ),
                builder: (c, w) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: w!,
                ),
                home: DiscoveryPage(
                  pager: pager,
                  onOpen: (item) => opened.add(item.id),
                  onSearch: () => searches++,
                  allowReelsFilter: true,
                  imageProvider: (url) => MemoryImage(
                    images[int.parse(url.path.split('-').last) % 3],
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 3; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)),
            );
            await t.pumpAndSettle();
          }
          expect(pager.items.length, 12);
          expect(find.byType(Image), findsWidgets);
          for (final chip in find.byType(ChoiceChip).evaluate()) {
            final size = t.getSize(find.byWidget(chip.widget));
            expect(size.height, greaterThanOrEqualTo(44));
          }
          expect(
            t
                .widget<ChoiceChip>(find.byType(ChoiceChip).first)
                .labelStyle!
                .color,
            Theme.of(t.element(find.byType(ChoiceChip).first))
                .colorScheme
                .onSurface,
          );
          expect(t.takeException(), isNull);
          await shot(
            t,
            key,
            'explore-${width.toInt()}-$scale-${dark ? 'dark' : 'light'}',
          );
          await t.tap(find.bySemanticsLabel('Review moment 1').first);
          expect(opened, ['fixture-0']);
          await t.tap(find.byType(IconButton).first);
          expect(searches, 1);
          await t.tap(find.byType(ChoiceChip).last);
          await t.pumpAndSettle();
          expect(queries.last, {'kind': 'reel'});
          expect(pager.items.every((x) => x.preview.video), isTrue);
          expect(t.takeException(), isNull);
          active = false;
          pager.checkOwner();
          await t.pumpAndSettle();
          expect(find.byType(Image), findsNothing);
          expect(pager.items, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump();
        });
      }
    }
  }
  testWidgets('empty eligible page can explicitly load a later eligible page', (
    t,
  ) async {
    var reads = 0;
    final images = File('/downloads/sanjaal-highfidelity/mountain.jpg')
        .readAsBytesSync();
    final p = DiscoveryPaging<DiscoveryTile>(
      read: (q, c) async {
        reads++;
        return c == null
            ? DiscoveryPageData(
                items: [],
                nextCursor: 'next',
                version: 'fixture-v1',
              )
            : fixture(null);
      },
      keyOf: (x) => x.id,
      ownerActive: () => true,
      maxItems: 60,
      maxPageSize: 15,
    );
    addTearDown(p.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: DiscoveryPage(
          pager: p,
          onOpen: (_) {},
          onSearch: () {},
          imageProvider: (_) => MemoryImage(images),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(p.items, isEmpty);
    expect(p.exhausted, isFalse);
    expect(find.text('Load more'), findsOneWidget);
    await t.tap(find.text('Load more'));
    await t.pumpAndSettle();
    expect(reads, 2);
    expect(p.items.length, 12);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'detail route return retains loaded grid and scroll without refetch',
    (t) async {
      var reads = 0;
      final images = File('/downloads/sanjaal-highfidelity/mountain.jpg')
          .readAsBytesSync();
      final p = DiscoveryPaging<DiscoveryTile>(
        read: (q, c) async {
          reads++;
          return fixture(null);
        },
        keyOf: (x) => x.id,
        ownerActive: () => true,
        maxItems: 60,
        maxPageSize: 15,
      );
      addTearDown(p.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => DiscoveryPage(
              pager: p,
              onOpen: (item) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      Scaffold(appBar: AppBar(title: Text(item.id))),
                ),
              ),
              onSearch: () {},
              imageProvider: (_) => MemoryImage(images),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await t.pumpAndSettle();
      final position = t
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels;
      expect(position, greaterThan(0));
      await t.tap(find.byType(Image).hitTestable().first);
      await t.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsOneWidget);
      expect(reads, 1);
      expect(
        t.state<ScrollableState>(find.byType(Scrollable).last).position.pixels,
        position,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('initial error retries; failed refresh keeps grid', (t) async {
    var reads = 0;
    final images = File('/downloads/sanjaal-highfidelity/mountain.jpg')
        .readAsBytesSync();
    final p = DiscoveryPaging<DiscoveryTile>(
      read: (q, c) async {
        if (++reads == 1 || reads == 3) throw StateError('fixture offline');
        return fixture(null);
      },
      keyOf: (x) => x.id,
      ownerActive: () => true,
      maxItems: 60,
      maxPageSize: 15,
    );
    addTearDown(p.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: DiscoveryPage(
          pager: p,
          onOpen: (_) {},
          onSearch: () {},
          imageProvider: (_) => MemoryImage(images),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(p.error, isNotNull);
    expect(p.items, isEmpty);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(p.items.length, 12);
    await p.reset({}, retain: true);
    await t.pumpAndSettle();
    expect(p.items.length, 12);
    expect(p.error, isNotNull);
    expect(find.byType(Image), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}

// Offline photo navigation/layout. Not evidence about device codecs or production downloads.
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/photo_gallery.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/main.dart' show buildTheme;

late Uint8List pixels;
ImageProvider photo(String _) => MemoryImage(pixels);
Widget gallery({int initial = 0, bool fullscreen = false}) => MaterialApp(home: Scaffold(body: SizedBox(height: 450, child: PhotoGallery(urls: const ['one', 'two', 'three'], provider: photo, initialIndex: initial, fullscreen: fullscreen))));
void main() {
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    c.drawRect(const Rect.fromLTWH(0, 0, 400, 600), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0,600), const [Color(0xFF16254F), Color(0xFFD9708A), Color(0xFFF2B77A)], const [0.0,0.6,1.0]));
    c.drawPath(Path()..moveTo(0,500)..lineTo(120,240)..lineTo(220,380)..lineTo(310,200)..lineTo(400,500)..lineTo(400,600)..lineTo(0,600)..close(), Paint()..color = const Color(0xFF1B1F2A));
    final image = await recorder.endRecording().toImage(400, 600);
    pixels = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  testWidgets('swipe changes the actual photo position, not a fixed first-photo label', (t) async {
    await t.pumpWidget(gallery()); await t.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-650, 0)); await t.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-650, 0)); await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });
  testWidgets('tap opens current photo, full-screen swipe/zoom exists and back preserves inline position', (t) async {
    await t.pumpWidget(gallery(initial: 1)); await t.pumpAndSettle();
    await t.tap(find.byType(Image).first); await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    await t.drag(find.byType(PageView).last, const Offset(-650, 0)); await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await t.tap(find.byTooltip('Close')); await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
    expect(find.text('2 / 3'), findsOneWidget);
  });
  testWidgets('invalid initial position is bounded and empty/single galleries do not invent a counter', (t) async {
    await t.pumpWidget(gallery(initial: 99)); await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: PhotoViewer(urls: const ['one'], provider: photo)));
    await t.pumpAndSettle(); expect(find.text('1 / 1'), findsNothing);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: PhotoGallery(urls: []))));
    await t.pumpAndSettle(); expect(t.takeException(), isNull);
  });
  testWidgets('private image authorization remains on full-screen provider', (t) async {
    await t.pumpWidget(const MaterialApp(home: PhotoViewer(urls: ['https://fixture.invalid/private'], headers: {'Authorization': 'Bearer test-only'})));
    await t.pumpAndSettle();
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).headers, {'Authorization': 'Bearer test-only'});
    expect(find.text('Photo could not load'), findsOneWidget);
    await t.tap(find.text('Try again')); await t.pumpAndSettle();
    expect((t.widget<Image>(find.byType(Image)).image as NetworkImage).headers, {'Authorization': 'Bearer test-only'});
    expect(t.takeException(), isNull);
  });
  testWidgets('a failed image can reload successfully without leaving the post', (t) async {
    var attempts = 0;
    ImageProvider recover(String _) => ++attempts < 2 ? const NetworkImage('https://fixture.invalid/offline') : MemoryImage(pixels);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 450, child: PhotoGallery(urls: const ['one'], provider: recover)))));
    await t.pumpAndSettle(); expect(find.text('Photo could not load'), findsOneWidget);
    await t.tap(find.text('Try again')); await t.pumpAndSettle();
    expect(find.text('Photo could not load'), findsNothing);
    expect(t.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
  });
  for (final immersive in [true, false]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('real post $immersive ${brightness.name} exposes every photo and correct count', (t) async {
        final font = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/tools/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf').readAsBytesSync())));
        await t.runAsync(() => font.load());
        t.view.physicalSize = const Size(960, 1920); t.view.devicePixelRatio = 3; addTearDown(t.view.reset);
        feedImageProvider = photo; addTearDown(() => feedImageProvider = null);
        final key = GlobalKey();
        await t.pumpWidget(MaterialApp(theme: buildTheme(brightness, fontFamily: 'Roboto'), builder: (c,w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.8)), child: w!), home: RepaintBoundary(key: key, child: Scaffold(body: SingleChildScrollView(child: PostCard(session: Session(), immersive: immersive, onRemoved: () {}, post: {
          'public_id': 'fixture', 'body': 'A whole photo story', 'author': {'public_id': 'a', 'name': 'Fixture', 'username': 'fixture'},
          'media': [for (final n in ['one', 'two', 'three']) {'type': 'image', 'url': n}],
        }))))));
        await t.pumpAndSettle(); expect(find.text('1 / 3'), findsOneWidget);
        await t.drag(find.byType(PageView), const Offset(-300, 0)); await t.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget); expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('test/renders/gallery_post_${immersive ? 'home' : 'detail'}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
  for (final b in [Brightness.light, Brightness.dark]) {
    for (final failure in [false, true]) {
      testWidgets('gallery render ${b.name} error=$failure at small large-text size', (t) async {
        final font = FontLoader('Roboto');
        final file = File('/home/sandbox/tools/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
        if (file.existsSync()) { font.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))); await t.runAsync(() => font.load()); }
        t.view.physicalSize = const Size(960, 1920); t.view.devicePixelRatio = 3; addTearDown(t.view.reset);
        final key = GlobalKey();
        final real = File('/tmp/photos/photo_portrait.jpg');
        final PhotoProvider provider = failure ? (String _) => const NetworkImage('https://fixture.invalid/offline') : (String _) => MemoryImage(real.existsSync() ? real.readAsBytesSync() : pixels);
        await t.pumpWidget(MaterialApp(theme: buildTheme(b, fontFamily: 'Roboto'), builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.8)), child: w!), home: RepaintBoundary(key: key, child: PhotoViewer(urls: const ['one','two','three'], initialIndex: 1, provider: provider))));
        await t.pumpAndSettle(); expect(t.takeException(), isNull);
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('test/renders').createSync(recursive: true);
          File('test/renders/gallery_${b.name}_${failure ? 'error' : 'photo'}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });

      });
    }
  }

}

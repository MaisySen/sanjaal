// Renders a theme preview in light and dark and writes PNGs to test/renders.
// CI runs this with --update-goldens and publishes the images. Text uses the test font, so
// letters show as blocks; colours, shapes, spacing and layout are real.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart';

Widget _preview() => Scaffold(
      appBar: AppBar(title: const Text('Sanjaal'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('A post from a member'),
              const SizedBox(height: 8),
              const Text('Namaste from Pokhara'),
              const SizedBox(height: 12),
              Row(children: [
                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.favorite_border), label: const Text('12')),
                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.mode_comment_outlined), label: const Text('3')),
                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.card_giftcard), label: const Text('Gift')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const TextField(decoration: InputDecoration(labelText: 'Message')),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: const [Chip(label: Text('Kathmandu')), Chip(label: Text('Music')), Chip(label: Text('Momo'))]),
        const SizedBox(height: 16),
        FilledButton(onPressed: () {}, child: const Text('Continue')),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
        const SizedBox(height: 12),
        const EmptyState(icon: Icons.mode_comment_outlined, title: 'No comments yet', hint: 'Say something kind.'),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: 0, destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Reels'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
      ]),
    );

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('theme preview ${b.name}', (tester) async {
      final key = GlobalKey();
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: buildTheme(b), debugShowCheckedModeBanner: false, home: _preview())));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('test/renders')..createSync(recursive: true);
        File('${dir.path}/theme_${b.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}

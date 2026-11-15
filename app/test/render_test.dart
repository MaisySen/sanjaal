// Renders real app widgets with realistic content in light and dark and writes PNGs to
// test/renders. CI publishes them to the renders branch. Fonts and icons come from the Flutter
// SDK so text and icons are readable. Network images are not fetched in tests, so avatars and
// photos show their fallback.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart' show PostCard;
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/profile_pages.dart' show ProfileHeader;
import 'package:sanjaal/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
  }
  await loader.load();
}

Map<String, dynamic> _author(String name, String user) => {'public_id': user, 'name': name, 'username': user, 'bio': null, 'avatar_url': null};

Map<String, dynamic> _post(String id, String name, String user, String body, int likes, int comments) => {
      'public_id': id,
      'kind': 'post',
      'body': body,
      'author': _author(name, user),
      'media': <dynamic>[],
      'hashtags': ['pokhara', 'himal'],
      'likes_count': likes,
      'comments_count': comments,
      'liked': false,
      'my_reaction': null,
      'reactions': {'like': likes},
      'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    };

Widget _screen(Session s, int tab) {
  final posts = [
    _post('p1', 'Asha Gurung', 'asha', 'Sunrise over Phewa lake this morning. Dal bhat after the boat ride. #pokhara', 128, 14),
    _post('p2', 'Bikash Thapa', 'bikash', 'New song from the studio in Kathmandu. Tell me what you think of the chorus.', 54, 9),
  ];
  final profile = {'public_id': 'asha', 'name': 'Asha Gurung', 'username': 'asha', 'bio': 'Pokhara. Music, momo and mountains.', 'avatar_url': null, 'posts_count': 42, 'followers_count': 1280, 'following_count': 310};
  return Scaffold(
    appBar: AppBar(title: Text(tab == 0 ? 'Sanjaal' : 'Profile'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search)), IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none))]),
    body: tab == 0
        ? ListView(padding: const EdgeInsets.all(12), children: [for (final p in posts) Padding(padding: const EdgeInsets.only(bottom: 12), child: PostCard(session: s, post: p, onRemoved: () {}))])
        : ListView(children: [
            ProfileHeader(user: profile, actions: Row(mainAxisAlignment: MainAxisAlignment.center, children: [FilledButton(onPressed: () {}, child: const Text('Follow')), const SizedBox(width: 12), OutlinedButton(onPressed: () {}, child: const Text('Message'))])),
            const EmptyState(icon: Icons.photo_library_outlined, title: 'No posts yet', hint: 'Posts will show here.'),
          ]),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Reels'),
      NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
    ]),
  );
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final dir = '$root/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', ['$dir/Roboto-Regular.ttf', '$dir/Roboto-Medium.ttf', '$dir/Roboto-Bold.ttf']);
    await _loadFont('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    for (final tab in [0, 3]) {
      testWidgets('screen $tab ${b.name}', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final key = GlobalKey();
        tester.view.physicalSize = const Size(1080, 2160);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final theme = buildTheme(b, fontFamily: 'Roboto');
        await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: theme, debugShowCheckedModeBanner: false, home: _screen(Session(), tab))));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory('test/renders')..createSync(recursive: true);
          File('${out.path}/${tab == 0 ? 'feed' : 'profile'}_${b.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
}

// Renders real app widgets with realistic content in light and dark and writes PNGs to
// test/renders. CI publishes them to the renders branch. Fonts and icons come from the Flutter
// SDK so text and icons are readable. Network images are not fetched in tests, so avatars and
// photos show their fallback.
import 'dart:async';
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

class _Resp extends Stream<List<int>> implements HttpClientResponse {
  _Resp(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([bytes]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Req implements HttpClientRequest {
  _Req(this.bytes);
  final List<int> bytes;
  @override
  HttpHeaders get headers => _H();
  @override
  Future<HttpClientResponse> close() async => _Resp(bytes);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _H implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Client implements HttpClient {
  _Client(this.bytes);
  final List<int> bytes;
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Req(File('test/fixtures/${url.pathSegments.last}').readAsBytesSync());
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Overrides extends HttpOverrides {
  _Overrides(this.bytes);
  final List<int> bytes;
  @override
  HttpClient createHttpClient(SecurityContext? c) => _Client(bytes);
}

Widget _screen(Session s, int tab) {
  final posts = [
    _post('p1', 'Asha Gurung', 'asha', 'Sunrise over Phewa lake this morning. Dal bhat after the boat ride. #pokhara', 128, 14),
    {..._post('p3', 'Maya Rai', 'maya', 'Evening light from the ridge above Nagarkot.', 212, 31), 'media': [{'type': 'image', 'url': 'http://fixture.invalid/ridge_portrait.png'}], 'hashtags': <String>[]},
    {..._post('p4', 'Dipesh Karki', 'dipesh', 'Wide frame, same evening.', 40, 2), 'media': [{'type': 'image', 'url': 'http://fixture.invalid/ridge_wide.png'}], 'hashtags': <String>[]},
    _post('p2', 'Bikash Thapa', 'bikash', 'New song from the studio in Kathmandu. Tell me what you think of the chorus.', 54, 9),
  ];
  final profile = {'public_id': 'asha', 'name': 'Asha Gurung', 'username': 'asha', 'bio': 'Pokhara. Music, momo and mountains.', 'avatar_url': null, 'posts_count': 0, 'followers_count': 0, 'following_count': 0};
  return Scaffold(
    appBar: AppBar(title: Text(tab == 0 ? 'Sanjaal' : 'Profile'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search)), IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none))]),
    body: tab == 0
        ? ListView(children: [for (final p in posts) PostCard(session: s, post: p, onRemoved: () {})])
        : ListView(children: [
            ProfileHeader(user: profile, actions: Row(mainAxisAlignment: MainAxisAlignment.center, children: [FilledButton(onPressed: () {}, child: const Text('Follow')), const SizedBox(width: 12), OutlinedButton(onPressed: () {}, child: const Text('Message'))])),
            const EmptyState(icon: Icons.photo_library_outlined, title: 'No posts yet', hint: 'Posts will show here.'),
          ]),
    bottomNavigationBar: NavigationBar(selectedIndex: tab == 0 ? 0 : 4, destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Reels'),
      NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
      NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
    ]),
  );
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _Overrides(File('test/fixtures/ridge.png').readAsBytesSync());
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
        tester.view.physicalSize = tab == 0 ? const Size(1080, 4000) : const Size(1080, 2160);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final theme = buildTheme(b, fontFamily: 'Roboto');
        await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: theme, builder: (c, child) => Column(children: [Expanded(child: child!), Container(width: double.infinity, color: const Color(0xFF444444), padding: const EdgeInsets.symmetric(vertical: 2), child: const Text('DEMO DATA: test fixture, not live', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 10, decoration: TextDecoration.none, fontWeight: FontWeight.w400)))]), debugShowCheckedModeBanner: false, home: _screen(Session(), tab))));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
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

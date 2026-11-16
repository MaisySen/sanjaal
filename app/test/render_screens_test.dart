// Renders the wallet, gift sheet and chat screens from the real widgets with canned API replies
// (package:http MockClient). Nothing here talks to the network. PNGs go to test/renders and CI
// publishes them. This checks layout with realistic data, not behaviour on a device.
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
import 'package:sanjaal/ph.dart' show PhIcon, PhData;
import 'package:sanjaal/call_page.dart' show CallView, CallTile;
import 'package:sanjaal/chat_pages.dart' show ChatPage, ChatsPage, GroupInfoPage;
import 'package:sanjaal/notifications_page.dart' show NotificationsPage;
import 'package:sanjaal/settings_page.dart' show SettingsPage;
import 'package:sanjaal/auth_page.dart' show AuthPage;
import 'package:sanjaal/onboarding_page.dart' show OnboardingPage;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/about_page.dart' show AboutPage;
import 'package:sanjaal/share_post.dart' show SharedPostCard;
import 'package:sanjaal/feed_page.dart' show SavedPage, FeedPage, FeedList, FeedListState;
import 'package:sanjaal/profile_pages.dart' show MePage, EditProfilePage;
import 'package:sanjaal/stories_page.dart' show StoryViewer;
import 'package:sanjaal/reels_page.dart' show ReelItem;
import 'package:sanjaal/chat_pages.dart' show NewChatPage;
import 'package:sanjaal/settings_page.dart' show BlockedPage;
import 'package:sanjaal/search_page.dart' show SearchPage;
import 'package:sanjaal/profile_pages.dart' show UserProfilePage;
import 'package:sanjaal/gifts.dart' show showGiftSheet;
import 'package:sanjaal/rooms_page.dart' show RoomView, RoomsPage;
import 'package:sanjaal/main.dart' show buildTheme, HomeShell;
import 'package:sanjaal/feed_page.dart' show ComposePage, CreateSheet, feedImageProvider;
import 'package:sanjaal/wallet_page.dart' show WalletPage;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
  }
  await loader.load();
}

String _ago(int mins) => DateTime.now().toUtc().subtract(Duration(minutes: mins)).toIso8601String();

http.Response _json(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

bool _voiceMsgs = false;
bool _sharedMsgs = false;
String _following = '';
bool _failSend = false;

Future<http.Response> _reply(http.Request r) async {
  if (_failSend && r.method == 'POST' && r.url.path.endsWith('/messages')) return http.Response(jsonEncode({'message': 'No connection'}), 503, headers: {'content-type': 'application/json'});
  final p = r.url.path;
  if (p == '/oauth/token') return _json({'access_token': 'x', 'expires_in': 3600, 'refresh_token': 'r'});
  if (p.endsWith('/auth/me')) return _json({'user': {'public_id': 'me', 'name': 'Bidur', 'username': 'bidur'}});
  if (p.endsWith('/gifts')) {
    return _json({
      'data': [
        {'key': 'rose', 'name': 'Rose', 'coins': 5},
        {'key': 'heart', 'name': 'Heart', 'coins': 10},
        {'key': 'momo', 'name': 'Momo', 'coins': 20},
        {'key': 'crown', 'name': 'Crown', 'coins': 50},
        {'key': 'himal', 'name': 'Himal', 'coins': 100},
        {'key': 'rocket', 'name': 'Rocket', 'coins': 500},
      ]
    });
  }
  if (p.endsWith('/conversations') && r.method == 'GET') {
    Map<String, dynamic> msg(String b, int mins) => {'kind': 'text', 'body': b, 'created_at': _ago(mins)};
    return _json({
      'data': [
        {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung', 'unread': 2, 'pinned': true, 'last_message': msg('Perfect. Dal bhat after the music.', 45)},
        {'public_id': 'c2', 'type': 'group', 'title': 'Sydney Nepali meetup', 'unread': 0, 'last_message': msg('Venue is booked for Saturday', 190)},
        {'public_id': 'c3', 'type': 'direct', 'title': 'Bikash Thapa', 'unread': 5, 'muted': true, 'last_message': {'kind': 'voice', 'body': '', 'created_at': _ago(600)}},
        {'public_id': 'c4', 'type': 'direct', 'title': 'सुनिता राई', 'unread': 0, 'last_message': msg('धन्यवाद, भोलि भेटौँला', 1500)},
      ]
    });
  }
  if (p.endsWith('/stories')) {
    return http.Response(jsonEncode({'data': [
      {'author': {'username': 'asha', 'name': 'Asha Gurung'}, 'all_viewed': false, 'items': []},
      {'author': {'username': 'bikash', 'name': 'Bikash Thapa'}, 'all_viewed': true, 'items': []},
      {'author': {'username': 'sunita', 'name': 'Sunita Rai'}, 'all_viewed': false, 'items': []},
    ]}), 200, headers: {'content-type': 'application/json'});
  }
  if (p.endsWith('/users/blocked')) {
    return http.Response(jsonEncode({'data': [
      {'username': 'raju_k', 'name': 'Raju K'},
      {'username': 'spam_account', 'name': 'Promo Offers'},
    ]}), 200, headers: {'content-type': 'application/json'});
  }
  if (p.endsWith('/users/search') && r.url.queryParameters['q'] == 'zzz') {
    return _json({'users': [], 'hashtags': []});
  }
  if (p.endsWith('/users/search') && r.url.queryParameters['q'] == 'boom') {
    return http.Response(jsonEncode({'message': 'Search is not available right now. Try again in a moment.'}), 503, headers: {'content-type': 'application/json'});
  }
  if (p.endsWith('/users/search')) {
    return http.Response(jsonEncode({
      'users': [
        {'username': 'asha', 'name': 'Asha Gurung', 'following': true},
        {'username': 'ashok_t', 'name': 'Ashok Thapa'},
      ],
      'hashtags': ['ashadh', 'ashwin'],
    }), 200, headers: {'content-type': 'application/json'});
  }
  if (p.endsWith('/notifications')) {
    return _json({
      'data': [
        {'type': 'like', 'actor': 'asha', 'text': 'Sunrise over Phewa lake', 'created_at': _ago(20)},
        {'type': 'comment', 'actor': 'bikash', 'text': 'Which chord is that?', 'created_at': _ago(95)},
        {'type': 'follow', 'actor': 'sunita', 'created_at': _ago(600)},
      ]
    });
  }
  if (p.endsWith('/rooms')) {
    return _json({
      'data': [
        {'public_id': 'r1', 'title': 'Dashain bhajan night', 'host_name': 'Asha Gurung'},
        {'public_id': 'r2', 'title': 'Learn Nepali with Bikash', 'host_username': 'bikash'},
        {'public_id': 'r3', 'title': 'Sydney Nepali meetup planning', 'host_name': 'Sunita Rai'},
      ]
    });
  }
  if (p == '/api/v1/users/asha') {
    return _json({'user': {'public_id': 'asha', 'name': 'Asha Gurung', 'username': 'asha', 'bio': 'Pokhara. Music, momo and mountains.', 'avatar_url': null, 'posts_count': 2, 'followers_count': 1240, 'following_count': 87, 'following': false, 'is_me': false}});
  }
  if (p.endsWith('/posts') && r.url.queryParameters['scope'] == 'following' && _following == 'error') return http.Response(jsonEncode({'message': 'No connection'}), 503, headers: {'content-type': 'application/json'});
  if (p.endsWith('/posts') && r.url.queryParameters['scope'] == 'following' && _following == 'empty') return _json({'data': <dynamic>[], 'next_cursor': null});
  if (p.endsWith('/posts') && r.url.queryParameters['username'] == null && r.method == 'GET') {
    Map<String, dynamic> fp(String id, String body, int likes, List<dynamic> media) => {
          'public_id': id, 'kind': 'post', 'body': body, 'media': media, 'hashtags': <dynamic>[],
          'author': {'public_id': 'asha', 'name': 'Asha Gurung', 'username': 'asha', 'avatar_url': null},
          'likes_count': likes, 'comments_count': 31, 'liked': false, 'my_reaction': null, 'reactions': {'like': likes}, 'created_at': _ago(300),
        };
    return _json({'data': [
      fp('f1', 'Evening light on the ridge. Tea after the walk.', 342, [{'type': 'image', 'url': 'http://fixture.invalid/a.jpg'}]),
      fp('f2', 'Rehearsal tonight, come early.', 54, <dynamic>[]),
    ], 'next_cursor': null});
  }
  if (p.endsWith('/posts') && r.url.queryParameters['username'] == 'asha') {
    Map<String, dynamic> post(String id, String body, int likes) => {
          'public_id': id, 'kind': 'post', 'body': body, 'media': <dynamic>[], 'hashtags': ['pokhara'],
          'author': {'public_id': 'asha', 'name': 'Asha Gurung', 'username': 'asha', 'avatar_url': null},
          'likes_count': likes, 'comments_count': 3, 'liked': false, 'my_reaction': null, 'reactions': {'like': likes}, 'created_at': _ago(180),
        };
    return _json({'data': [post('p1', 'Sunrise over Phewa lake this morning. Dal bhat after the boat ride.', 128), post('p2', 'Rehearsal for the Dashain concert tonight.', 54)], 'next_cursor': null});
  }
  if (p.endsWith('/wallet')) {
    return _json({
      'balance': 135,
      'entries': [
        {'kind': 'gift_out', 'amount': -20, 'created_at': _ago(90), 'counterparty': 'asha', 'note': 'Khada'},
        {'kind': 'gift_in', 'amount': 55, 'created_at': _ago(30), 'counterparty': 'bikash', 'note': null},
      ],
      'topup': {'esewa': false, 'esewa_mode': 'off'},
    });
  }
  if (p.endsWith('/messages')) {
    Map<String, dynamic> m(int seq, String who, String body, int mins) => {
          'public_id': 'm$seq', 'seq': seq, 'kind': 'text', 'body': body,
          'sender': {'public_id': who, 'username': who == 'me' ? 'bidur' : 'asha'}, 'created_at': _ago(mins),
        };
    return _json({
      'typing': ['asha'],
      'data': [
        m(1, 'asha', 'Namaste! Are you coming to the Dashain meetup on Saturday?', 50),
        m(2, 'me', 'Yes, I will bring sel roti.', 48),
        m(3, 'asha', 'Perfect. Dal bhat after the music.', 45),
        if (_sharedMsgs) {...m(4, 'asha', '', 40), 'kind': 'post', 'shared_post': {'public_id': 'p1', 'author': {'name': 'Bikash Thapa', 'username': 'bikash'}, 'excerpt': 'Sunrise from Poon Hill this morning. Worth the early start.', 'image_url': 'http://fixture.invalid/p1.jpg'}},
        if (_sharedMsgs) {...m(5, 'me', '', 38), 'kind': 'post', 'shared_post': null},
        if (_voiceMsgs) {...m(4, 'asha', '', 40), 'kind': 'voice', 'media_url': 'https://example.invalid/v.m4a'},
        if (_voiceMsgs) {...m(5, 'me', '', 38), 'kind': 'voice', 'media_url': 'https://example.invalid/w.m4a'},
      ],
    });
  }
  return _json({'data': []});
}

Widget _room({bool noChat = false, bool isHost = false, bool speaker = false, bool handUp = false, bool failed = false, String status = 'Live', Map<String, String> hands = const {}, List<({String id, String name, bool host, bool you, bool muted, bool speaking})> stage = const []}) {
  return RoomView(
    title: 'Dashain bhajan night',
    status: status,
    failed: failed,
    isHost: isHost,
    speaker: speaker,
    muted: false,
    handUp: handUp,
    inRoom: 14,
    hands: hands,
    stage: stage,
    onDismissHand: (id) {},
    messages: noChat ? [] : [
      {'from': 'Asha', 'text': 'Namaste everyone'},
      {'from': 'Bikash', 'text': 'Beautiful song, please play another'},
      {'from': 'Sunita', 'text': 'Joining from Sydney'},
    ],
    chat: TextEditingController(),
    onEnd: () {},
    onToggleMic: () {},
    onRaise: () {},
    onGift: () {},
    onAllow: (id, allow) {},
    onSend: () {},
  );
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final dir = '$root/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', ['$dir/Roboto-Regular.ttf', '$dir/Roboto-Medium.ttf', '$dir/Roboto-Bold.ttf']);
    if (File('/tmp/ndev.ttf').existsSync()) await _loadFont('NotoDev', ['/tmp/ndev.ttf']);
    // Generated fixture photo (plain gradient and shapes drawn in code) so feed renders show a photo underlay offline.
    final rec = ui.PictureRecorder();
    final cv = ui.Canvas(rec);
    const w = 800.0, h = 1000.0;
    cv.drawRect(const ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..shader = ui.Gradient.linear(const ui.Offset(0, 0), const ui.Offset(0, h), const [Color(0xFF16254F), Color(0xFFD9708A), Color(0xFFF2B77A)], const [0.0, 0.6, 1.0]));
    cv.drawPath(ui.Path()..moveTo(0, 760)..lineTo(260, 430)..lineTo(420, 620)..lineTo(580, 380)..lineTo(800, 700)..lineTo(800, h)..lineTo(0, h)..close(), ui.Paint()..color = const Color(0xFF1B1F2A));
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    // A real CC0 photograph (Wikimedia Commons, Billjones94, licence checked live) is used when it has been downloaded
    // to /tmp/photos by the reviewer. It is never committed. Otherwise the generated picture above is used.
    final real = File(Platform.environment['SANJAAL_TEST_PHOTO'] ?? '/tmp/photos/photo_portrait.jpg');
    final photoBytes = real.existsSync() ? real.readAsBytesSync() : bytes;
    feedImageProvider = (url) => MemoryImage(photoBytes);
    await _loadFont('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    for (final name in ['shell_offline', 'following_empty', 'following_error', 'following_empty_big', 'chat_shared', 'chat_shared_big', 'me', 'me_big', 'edit_profile', 'edit_profile_big', 'shell_big', 'shell_big_scrolled', 'create_big', 'group_info_big', 'wallet_big', 'chat_unsent', 'call_video', 'call_voice', 'group_info', 'create', 'search_none', 'search_error', 'story', 'reel', 'room_quiet', 'new_chat', 'blocked', 'search_results', 'about', 'about_big', 'search', 'chats_big', 'room_host_big', 'room_host_big_scrolled', 'settings_big', 'wallet_big', 'auth_big', 'compose', 'shell', 'chats', 'notifications', 'settings', 'auth', 'onboarding', 'chats_ne', 'wallet', 'gift', 'chat', 'rooms', 'room_host', 'room_listener', 'room_failed', 'gift_short', 'profile_full', 'chat_voice']) {
      testWidgets('$name ${b.name}', (tester) async {
        await http.runWithClient(() async {
          SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
          final s = Session();
          await tester.runAsync(() => s.restore());
          _voiceMsgs = name == 'chat_voice';
          _following = name.startsWith('following_error') ? 'error' : name.startsWith('following_empty') ? 'empty' : '';
          _sharedMsgs = name.startsWith('chat_shared');
          _failSend = name == 'chat_unsent';
          await tester.runAsync(() => prefs.setLang(name.endsWith('_ne') ? 'ne' : 'en'));
          final key = GlobalKey();
          tester.view.physicalSize = name == 'gift_short' ? const Size(1080, 1260) : const Size(1080, 2160);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final theme = buildTheme(b, fontFamily: 'Roboto', fontFamilyFallback: ['NotoDev']);
          final base = name.replaceAll('chat_shared', 'chat').replaceAll('_offline', '').replaceAll('_scrolled', '').replaceAll('_big', '');
          final Widget home = switch (base) {
            'wallet' => WalletPage(session: s),
            'profile_full' => UserProfilePage(session: s, username: 'asha'),
            'rooms' => RoomsPage(session: s),
            'shell' => HomeShell(session: s),
            'following_empty' || 'following_error' => FeedPage(session: s, onCompose: () async {}),
            'compose' => ComposePage(session: s),
            'create' => const Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: Material(color: Color(0xFF1A1D24), borderRadius: BorderRadius.vertical(top: Radius.circular(28)), child: CreateSheet()))),
            'about' || 'about_big' => const AboutPage(),
            'search' || 'search_results' || 'search_none' || 'search_error' => SearchPage(session: s),
            'story' => StoryViewer(session: s, group: {'author': {'username': 'asha', 'name': 'Asha Gurung'}, 'items': [
              {'public_id': 's1', 'type': 'image', 'created_at': _ago(90), 'url': 'http://fixture.invalid/s1.jpg', 'caption': 'Morning at Phewa lake'},
              {'public_id': 's2', 'type': 'image', 'created_at': _ago(30), 'url': 'http://fixture.invalid/s2.jpg', 'caption': ''},
            ]}),
            'reel' => Scaffold(backgroundColor: Colors.black, body: ReelItem(session: s, playing: true, muted: false, onToggleMute: () {}, reel: {'public_id': 'r1', 'body': 'Dal bhat after the boat ride #pokhara', 'comments_count': 14, 'likes_count': 212, 'author': {'username': 'asha', 'name': 'Asha Gurung', 'public_id': 'u1', 'following': false}, 'media': [{'type': 'video', 'url': 'http://fixture.invalid/r1.mp4'}]})),
            'blocked' => BlockedPage(session: s),
            'new_chat' => NewChatPage(session: s),
            'chats' || 'chats_ne' => ChatsPage(session: s),
            'notifications' => NotificationsPage(session: s),
            'settings' => SettingsPage(session: s),
            'shared_card' => Scaffold(appBar: AppBar(title: const Text('Shared post')), body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SharedPostCard(post: const {'public_id': 'p1', 'author': {'name': 'Asha Gurung', 'username': 'asha'}, 'excerpt': 'Evening light on the ridge. Tea after the walk.', 'image_url': null}), SharedPostCard(post: null)]))),
            'me' => MePage(session: s),
            'edit_profile' => EditProfilePage(session: s),
            'auth' => AuthPage(session: s),
            'onboarding' => const OnboardingPage(),
            'room_host' => _room(isHost: true, speaker: true, hands: {'u1': 'Bikash Thapa', 'u2': ''}, stage: [(id: 'me', name: 'Bidur Khatri', host: true, you: true, muted: false, speaking: true), (id: 'u3', name: 'Sunita Rai', host: false, you: false, muted: true, speaking: false), (id: 'u4', name: 'Asha Gurung', host: false, you: false, muted: false, speaking: false)]),
            'room_listener' => _room(isHost: false, speaker: false, handUp: true, stage: [(id: 'h', name: 'Asha Gurung', host: true, you: false, muted: false, speaking: true), (id: 'u3', name: 'Sunita Rai', host: false, you: false, muted: true, speaking: false)]),
            'room_quiet' => _room(noChat: true, isHost: false, speaker: false, stage: [(id: 'h', name: 'Asha Gurung', host: true, you: false, muted: false, speaking: true)]),
            'room_failed' => _room(failed: true, status: 'Could not join the room. Check your connection and try again.'),
            'chat_voice' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            'group_info' => GroupInfoPage(session: s, convo: {'public_id': 'g1', 'type': 'group', 'my_role': 'owner', 'title': 'Sydney Nepali meetup', 'members': [for (final n in [('bidur', 'Bidur Khatri'), ('asha', 'Asha Gurung'), ('bikash', 'Bikash Thapa'), ('sunita', 'Sunita Rai')]) {'public_id': n.$1 == 'bidur' ? 'me' : n.$1, 'username': n.$1, 'name': n.$2, 'avatar_url': null}]}),
            'call_video' => CallView(title: 'Asha Gurung', status: 'Connected', failed: false, video: true, muted: false, camOn: true, tiles: [CallTile(name: 'Asha Gurung', video: Image(image: feedImageProvider!('x'), fit: BoxFit.cover)), const CallTile(name: 'Bikash Thapa')], selfPreview: Image(image: feedImageProvider!('y'), fit: BoxFit.cover), onMute: () {}, onCamera: () {}, onEnd: () {}),
            'call_voice' => CallView(title: 'Asha Gurung', status: 'Connected', failed: false, video: false, muted: true, camOn: false, tiles: const [CallTile(name: 'Asha Gurung')], onMute: () {}, onCamera: () {}, onEnd: () {}),
            'chat_unsent' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            'chat' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            _ => Builder(builder: (c) => Scaffold(appBar: AppBar(title: const Text('Post')), body: Center(child: FilledButton(onPressed: () => showGiftSheet(c, s, 'p1', 'asha'), child: const Text('Send a gift'))))),
          };
          final nav = GlobalKey<NavigatorState>();
          final pushed = base != 'create' && base != 'gift' && base != 'gift_short' && base != 'onboarding' && base != 'auth' && base != 'shell';
          await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(navigatorKey: nav, theme: theme, builder: (c, child0) { final child = name.contains('_big') ? MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.8)), child: child0!) : child0; return Column(children: [Expanded(child: child!), Container(width: double.infinity, color: const Color(0xFF444444), padding: const EdgeInsets.symmetric(vertical: 2), child: const Text('DEMO DATA: test fixture, not live', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 10, decoration: TextDecoration.none, fontWeight: FontWeight.w400)))]); }, debugShowCheckedModeBanner: false, home: pushed ? const Scaffold(body: SizedBox()) : home)));
          // The real app opens these screens with Navigator.push, so the app bar shows a back button.
          if (pushed) nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => home));
          if (name.endsWith('_offline')) {
            s.setOffline(true);
            await tester.pump(const Duration(milliseconds: 300));
          }
          if (name.endsWith('_scrolled')) {
            for (var i = 0; i < 4; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
              await tester.pump(const Duration(milliseconds: 150));
            }
            await tester.drag(find.byType(Scrollable).first, Offset(0, name.startsWith('room') ? -300 : -700));
            await tester.pump(const Duration(milliseconds: 600));
          }
          if (base.startsWith('following_')) {
            await tester.pump(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
            await tester.tap(find.text('Following'));
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (base == 'gift' || base == 'gift_short') {
            await tester.tap(find.text('Send a gift'));
          }
          if (base == 'chat_unsent') {
            for (var i = 0; i < 4; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
              await tester.pump(const Duration(milliseconds: 100));
            }
            await tester.enterText(find.byType(EditableText), 'See you at 6');
            await tester.pump();
            await tester.tap(find.byTooltip('Send message'));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text('Not sent. Tap to retry.'), findsOneWidget);
            ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).hideCurrentSnackBar();
            await tester.pump(const Duration(seconds: 6));
            await tester.pump(const Duration(seconds: 1));
          }
          if (base.startsWith('search_')) {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
            await tester.enterText(find.byType(EditableText), base == 'search_none' ? 'zzz' : base == 'search_error' ? 'boom' : 'ash');
            await tester.pump(const Duration(milliseconds: 400));
          }
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = Directory('test/renders')..createSync(recursive: true);
            File('${out.path}/${name}_${b.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
          });
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 3));
        }, () => MockClient(_reply));
      });
    }
  }

  testWidgets('offline flag: a failed request sets it, the next response clears it', (tester) async {
    var down = true;
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      expect(s.offline, isFalse);
      await tester.runAsync(() async {
        await expectLater(s.call('GET', '/notifications/summary'), throwsA(isA<ApiError>()));
      });
      expect(s.offline, isTrue);
      down = false;
      await tester.runAsync(() async {
        try { await s.call('GET', '/notifications/summary'); } catch (_) {}
      });
      expect(s.offline, isFalse);
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      if (down) throw const SocketException('no route');
      return http.Response(jsonEncode({'unread': 0}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('offline flag: server and auth errors are not offline', (tester) async {
    var status = 500;
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      for (final code in [500, 403, 422]) {
        status = code;
        await tester.runAsync(() async {
          try { await s.call('GET', '/notifications/summary'); } catch (_) {}
        });
        expect(s.offline, isFalse, reason: 'HTTP $code is a response, not a lost connection');
      }
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      return http.Response(jsonEncode({'message': 'x'}), status, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('group info: Add people posts the usernames and shows the new member; Leave posts once', (tester) async {
    final calls = <String>[];
    Map<String, dynamic> user(String n) => {'public_id': 'u_$n', 'name': n, 'username': n};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final convo = {'public_id': 'g1', 'type': 'group', 'title': 'Trek', 'members': [user('asha'), user('bina')]};
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => FilledButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => GroupInfoPage(session: s, convo: convo))), child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('@bina'), findsOneWidget);
      expect(find.text('@chandra'), findsNothing);
      await tester.tap(find.text('Add people'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '@chandra');
      await tester.tap(find.text('Add'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(calls.where((c) => c == 'POST /conversations/g1/members {"usernames":["chandra"]}').length, 1);
      expect(find.text('@chandra'), findsOneWidget);
      await tester.tap(find.text('Leave group'));
      await tester.pumpAndSettle();
      expect(calls.any((c) => c.contains('/leave')), isFalse, reason: 'asks first');
      await tester.tap(find.text('Leave'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('POST /conversations/g1/leave')).length, 1);
      expect(find.text('open'), findsOneWidget, reason: 'back at the first screen');
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}${r.body.isEmpty ? '' : ' ${r.body}'}');
      if (r.url.path.endsWith('/members')) {
        return http.Response(jsonEncode({'conversation': {'public_id': 'g1', 'members': [user('asha'), user('bina'), user('chandra')]}}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'left': true}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('group info: only the owner sees Rename; it patches once, updates the title, and a refusal keeps it', (tester) async {
    final calls = <String>[];
    var refuse = false;
    Map<String, dynamic> user(String n) => {'public_id': 'u_$n', 'name': n, 'username': n};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Future<void> pump(Map<String, dynamic> convo) async {
        await tester.pumpWidget(MaterialApp(home: GroupInfoPage(key: UniqueKey(), session: s, convo: convo)));
        await tester.pumpAndSettle();
      }
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }
      final base = {'public_id': 'g1', 'type': 'group', 'title': 'Trek', 'members': [user('asha'), user('bina')]};
      await pump({...base, 'my_role': 'member'});
      expect(find.text('Rename group'), findsNothing);
      await pump({...base, 'my_role': 'owner'});
      expect(find.text('Rename group'), findsOneWidget);
      // Cancel sends nothing.
      await tester.tap(find.text('Rename group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      // Refusal keeps the old title and shows the server's words.
      refuse = true;
      await tester.tap(find.text('Rename group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Everest');
      await tester.tap(find.text('Save'));
      await settle();
      expect(find.text('Only the group owner can rename it.'), findsOneWidget);
      expect(find.text('Trek'), findsOneWidget);
      refuse = false;
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.tap(find.text('Rename group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Everest');
      await tester.tap(find.text('Save'));
      await settle();
      expect(find.text('Everest'), findsOneWidget);
      expect(calls.where((c) => c == 'PATCH /conversations/g1 {"title":"Everest"}').length, 2, reason: 'one refused, one accepted');
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}${r.body.isEmpty ? '' : ' ${r.body}'}');
      if (refuse) return http.Response(jsonEncode({'message': 'Only the group owner can rename it.'}), 403, headers: {'content-type': 'application/json'});
      return http.Response(jsonEncode({'conversation': {'public_id': 'g1', 'title': 'Everest', 'members': []}}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('wallet: Cash out is off unless the server says so; a retry after a server error reuses the request id', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    var available = false;
    var failNext = true;
    var balance = 2000;
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(home: WalletPage(session: s, key: UniqueKey())));
      await settle();
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cash out')).onPressed, isNull);
      available = true;
      await tester.pumpWidget(MaterialApp(home: WalletPage(session: s, key: UniqueKey())));
      await settle();
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cash out')).onPressed, isNotNull);
      Future<void> cash() async {
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cash out'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '600');
        await tester.tap(find.widgetWithText(FilledButton, 'Cash out'));
        await settle();
      }
      await cash();
      expect(bodies.length, 1);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await cash();
      expect(bodies.length, 2);
      expect(bodies[1]['client_id'], bodies[0]['client_id'], reason: 'same request, so a lost reply cannot hold coins twice');
      expect(bodies[1]['coins'], 600);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await cash();
      expect(bodies.length, 3);
      expect(bodies[2]['client_id'], isNot(bodies[1]['client_id']), reason: 'a finished request starts a new id');
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      if (r.method == 'POST' && r.url.path.endsWith('/wallet/withdrawals')) {
        bodies.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
        if (failNext) {
          failNext = false;
          return http.Response(jsonEncode({'message': 'Server error'}), 500, headers: {'content-type': 'application/json'});
        }
        balance -= 600;
        return http.Response(jsonEncode({'withdrawal': {'public_id': 'w1', 'status': 'requested'}, 'balance': balance}), 201, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'balance': balance, 'topup': {'esewa': true, 'esewa_mode': 'test'}, 'cashout': {'available': available, 'min': 500, 'max': 100000}, 'entries': []}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('wallet: cash-out list shows states; only a requested one can be canceled, once', (tester) async {
    final calls = <String>[];
    var canceled = false;
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(home: WalletPage(session: s)));
      await settle();
      expect(find.text('Cash outs'), findsOneWidget);
      expect(find.text('Paid', findRichText: true, skipOffstage: false).evaluate().isNotEmpty || find.textContaining('Paid').evaluate().isNotEmpty, isTrue);
      expect(find.textContaining('Failed, coins returned'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget, reason: 'only the requested one');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle();
      expect(calls.where((c) => c == 'POST /wallet/withdrawals/w1/cancel').length, 1);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
      expect(find.textContaining('Canceled, coins returned'), findsOneWidget);
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}');
      if (r.url.path.endsWith('/cancel')) {
        canceled = true;
        return http.Response(jsonEncode({'canceled': true, 'balance': 1000}), 200, headers: {'content-type': 'application/json'});
      }
      if (r.url.path.endsWith('/wallet/withdrawals')) {
        return http.Response(jsonEncode({'data': [
          {'public_id': 'w1', 'coins': 600, 'status': canceled ? 'canceled' : 'requested', 'created_at': '2026-11-16T10:00:00Z'},
          {'public_id': 'w2', 'coins': 500, 'status': 'paid', 'created_at': '2026-11-15T10:00:00Z'},
          {'public_id': 'w3', 'coins': 700, 'status': 'failed', 'created_at': '2026-11-14T10:00:00Z'},
        ]}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'balance': 1000, 'topup': {'esewa': true}, 'cashout': {'available': true, 'min': 500, 'max': 100000}, 'entries': []}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('saved posts: menu toggles save with one request, failure reverts', (tester) async {
    final calls = <String>[];
    var fail = false;
    final post = {'public_id': 'p1', 'kind': 'post', 'body': 'Saved text', 'author': {'public_id': 'u_a', 'name': 'Asha', 'username': 'asha'}, 'media': [], 'hashtags': [], 'likes_count': 0, 'comments_count': 0, 'liked': false, 'saved': true, 'created_at': '2026-11-16T00:00:00Z'};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SavedPage(session: s)));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Saved text'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Remove from saved'), findsOneWidget);
      await tester.tap(find.text('Remove from saved'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls.where((c) => c == 'DELETE /posts/p1/save').length, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('Save'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget, reason: 'a failed save goes back to unsaved');
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}');
      if (r.url.path.endsWith('/saved')) return http.Response(jsonEncode({'data': [post], 'next_cursor': null}), 200, headers: {'content-type': 'application/json'});
      if (fail) return http.Response(jsonEncode({'message': 'Could not save.'}), 500, headers: {'content-type': 'application/json'});
      return http.Response(jsonEncode({'saved': true}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('chat media: files are fetched with sign-in, and a refusal is an error', (tester) async {
    final seen = <String, String?>{};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      expect(s.mediaHeaders['Authorization'], startsWith('Bearer '));
      await tester.runAsync(() async {
        final bytes = await s.fetchBytes('https://api.test/api/v1/conversations/c1/messages/m1/media');
        expect(bytes, [1, 2, 3]);
        await expectLater(s.fetchBytes('https://api.test/api/v1/conversations/c1/messages/gone/media'), throwsA(isA<ApiError>()));
      });
      expect(seen['m1'], startsWith('Bearer '), reason: 'the media request carries the access token');
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      if (r.url.path.endsWith('/m1/media')) {
        seen['m1'] = r.headers['Authorization'];
        return http.Response.bytes([1, 2, 3], 200);
      }
      return http.Response('', 404);
    }));
  });

  for (final mode in ['offline', 'server500', 'garbled']) {
    testWidgets('feed load failure copy and icon: $mode', (tester) async {
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
        final s = Session();
        await tester.runAsync(() => s.restore());
        await tester.pumpWidget(MaterialApp(home: SavedPage(session: s)));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        bool icon(String n) => find.byWidgetPredicate((w) => w is PhIcon && (w.icon == n || (w.icon is PhData && (w.icon as PhData).name == n))).evaluate().isNotEmpty;
        final msg = {'offline': 'No connection. Check your internet and try again.', 'server500': 'Server trouble', 'garbled': 'Could not load posts. Try again.'}[mode]!;
        expect(find.text(msg), findsOneWidget);
        expect(find.text('Nothing saved yet'), findsNothing, reason: 'a failure must not read as an empty list');
        expect(icon('cloud-slash'), mode == 'offline');
        expect(icon('warning-circle'), mode != 'offline');
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((r) async {
        if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
        if (mode == 'offline') throw http.ClientException('down');
        if (mode == 'server500') return http.Response(jsonEncode({'message': 'Server trouble'}), 500, headers: {'content-type': 'application/json'});
        return http.Response('<html>oops</html>', 200, headers: {'content-type': 'application/json'});
      }));
    });
  }

  Future<void> pagerTest(WidgetTester tester, List<Map<String, dynamic>> data, Future<void> Function(double Function() page, Future<void> Function() settle, List<String> reqs) body, {String? cursor, double scale = 1.0, Brightness b = Brightness.dark}) async {
    final reqs = <String>[];
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(b, fontFamily: 'Roboto'), builder: (c, ch) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: ch!), home: FeedPage(session: s, onCompose: () async {})));
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pump(const Duration(seconds: 1));
      }
      await settle();
      await body(() => tester.stateList<FeedListState>(find.byType(FeedList)).first.pager.page!, settle, reqs);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      if (r.url.path.endsWith('/stories')) return http.Response(jsonEncode({'data': <dynamic>[]}), 200, headers: {'content-type': 'application/json'});
      reqs.add(r.url.toString());
      return http.Response(jsonEncode({'data': r.url.queryParameters['cursor'] == null ? data : <dynamic>[], 'next_cursor': r.url.queryParameters['cursor'] == null ? cursor : null}), 200, headers: {'content-type': 'application/json'});
    }));
  }
  Map<String, dynamic> textPost(int i, String body) => {'public_id': 't$i', 'kind': 'post', 'body': body, 'author': {'public_id': 'u_a', 'name': 'Asha', 'username': 'asha'}, 'media': [], 'hashtags': [], 'likes_count': 0, 'comments_count': 0, 'liked': false, 'saved': false, 'created_at': '2026-11-16T00:00:00Z'};
  final vertical = find.byWidgetPredicate((w) => w is PageView && w.scrollDirection == Axis.vertical);

  testWidgets('pager: a tall text post scrolls first, then the same drag carries into the next post', (tester) async {
    final tall = List.generate(60, (i) => 'Line $i of a long update about the festival plans.').join(' ');
    await pagerTest(tester, [textPost(1, tall), textPost(2, 'Second')], (page, settle, reqs) async {
      await tester.drag(vertical, const Offset(0, -120));
      await settle();
      expect(page(), 0.0, reason: 'a short drag scrolls the post, it does not change page');
      for (var i = 0; i < 12 && page() < 1.0; i++) {
        await tester.fling(vertical, const Offset(0, -300), 1500);
        await settle();
      }
      expect(page(), 1.0, reason: 'at the end of the post the swipe moves on');
      await tester.fling(vertical, const Offset(0, 300), 1500);
      await settle();
      expect(page(), 0.0, reason: 'swiping back returns to the post');
    });
  });

  testWidgets('pager: one post, nothing more to load: stays put and asks for nothing extra', (tester) async {
    await pagerTest(tester, [textPost(1, 'Only post')], (page, settle, reqs) async {
      final before = reqs.length;
      await tester.fling(vertical, const Offset(0, -300), 2000);
      await settle();
      expect(page(), 0.0);
      expect(reqs.length, before, reason: 'swiping up on a short feed asks for nothing');
      expect(find.text('Only post'), findsOneWidget);
      expect(reqs.length, before, reason: 'no extra requests on a short feed');
    });
  });

  testWidgets('pager: pull down on the first post refreshes once', (tester) async {
    await pagerTest(tester, [textPost(1, 'First'), textPost(2, 'Second')], (page, settle, reqs) async {
      final before = reqs.length;
      await tester.fling(vertical, const Offset(0, 400), 1000);
      await settle();
      expect(page(), 0.0);
      expect(reqs.length, before + 1, reason: 'exactly one refresh request');
    });
  });

  testWidgets('pager: last post at the end of the feed does not load again or error', (tester) async {
    await pagerTest(tester, [textPost(1, 'Post A'), textPost(2, 'Post B end')], (page, settle, reqs) async {
      final before = reqs.length;
      await tester.fling(vertical, const Offset(0, -300), 2000);
      await settle();
      expect(page(), 1.0);
      await tester.fling(vertical, const Offset(0, -300), 2000);
      await settle();
      expect(page(), 1.0, reason: 'cannot swipe past the last post');
      expect(find.text('Post B end'), findsOneWidget);
      expect(reqs.length, before, reason: 'the feed said it was finished');
    });
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('pager render with a text post at 1.8x text: ${b.name}', (tester) async {
      final key = GlobalKey();
      await pagerTest(tester, [textPost(1, 'Rehearsal tonight, come early. Bring the madal.'), textPost(2, 'Second')], b: b, scale: 1.8, (page, settle, reqs) async {
        expect(find.textContaining('Rehearsal tonight'), findsOneWidget);
      });
    });
  }

  testWidgets('home pager: swipe moves one post at a time and loads the next page once near the end', (tester) async {
    final reqs = <String>[];
    Map<String, dynamic> post(int i) => {'public_id': 'p$i', 'kind': 'post', 'body': 'Post number $i', 'author': {'public_id': 'u_a', 'name': 'Asha', 'username': 'asha'}, 'media': [{'type': 'image', 'url': 'http://fixture.invalid/$i.jpg'}], 'hashtags': [], 'likes_count': 0, 'comments_count': 0, 'liked': false, 'saved': false, 'created_at': '2026-11-16T00:00:00Z'};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: FeedPage(session: s, onCompose: () async {})));
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
      }
      await settle();
      double page() => tester.stateList<FeedListState>(find.byType(FeedList)).first.pager.page!;
      expect(page(), 0.0);
      expect(find.text('Post number 1'), findsOneWidget);
      expect(reqs.where((r) => r.contains('cursor')).length, 0);
      await tester.fling(find.byWidgetPredicate((w) => w is PageView && w.scrollDirection == Axis.vertical), const Offset(0, -150), 2000);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      expect(page(), 1.0, reason: 'one swipe moves exactly one post');
      await tester.fling(find.byWidgetPredicate((w) => w is PageView && w.scrollDirection == Axis.vertical), const Offset(0, -150), 2000);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      expect(page(), 2.0);
      await tester.fling(find.byWidgetPredicate((w) => w is PageView && w.scrollDirection == Axis.vertical), const Offset(0, -150), 2000);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      expect(page(), 3.0);
      expect(reqs.where((r) => r.contains('cursor=c1')).length, 1, reason: 'next page requested once');
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      if (r.url.path.endsWith('/stories')) return http.Response(jsonEncode({'data': <dynamic>[]}), 200, headers: {'content-type': 'application/json'});
      reqs.add(r.url.toString());
      final more = r.url.queryParameters['cursor'] == 'c1';
      return http.Response(jsonEncode({'data': more ? [post(5)] : [post(1), post(2), post(3), post(4)], 'next_cursor': more ? null : 'c1'}), 200, headers: {'content-type': 'application/json'});
    }));
  });

  testWidgets('share to chat: tapping a chat sends the post once; nothing is sent before', (tester) async {
    final calls = <String>[];
    final post = {'public_id': 'p1', 'kind': 'post', 'body': 'Shareable', 'author': {'public_id': 'u_a', 'name': 'Asha', 'username': 'asha'}, 'media': [], 'hashtags': [], 'likes_count': 0, 'comments_count': 0, 'liked': false, 'saved': false, 'created_at': '2026-11-16T00:00:00Z'};
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SavedPage(session: s)));
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await settle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share to chat'));
      await settle();
      await tester.pumpAndSettle();
      expect(find.text('Bina Rai'), findsOneWidget);
      expect(calls.where((c) => c.startsWith('POST')).length, 0);
      await tester.tap(find.text('Bina Rai'));
      await settle();
      await tester.pump(const Duration(seconds: 5));
      expect(calls.where((c) => c.startsWith('POST /conversations/c1/messages') && c.contains('"shared_post":"p1"')).length, 1);
      expect(find.text('Bina Rai'), findsNothing, reason: 'sheet closes after sending');
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
      if (r.url.path.contains('token') || r.url.path.endsWith('/me')) return _reply(r);
      calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}${r.body.isEmpty ? '' : ' ${r.body}'}');
      final h = {'content-type': 'application/json'};
      if (r.url.path.endsWith('/saved')) return http.Response(jsonEncode({'data': [post], 'next_cursor': null}), 200, headers: h);
      if (r.url.path.endsWith('/conversations')) return http.Response(jsonEncode({'data': [{'public_id': 'c1', 'type': 'direct', 'title': 'Bina Rai'}]}), 200, headers: h);
      return http.Response(jsonEncode({'message': {}}), 201, headers: h);
    }));
  });

  testWidgets('gift sheet: unaffordable gift sends nothing and explains', (tester) async {
    var posts = 0;
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: FilledButton(onPressed: () => showGiftSheet(c, s, 'p1', 'asha'), child: const Text('Send a gift'))))));
      await tester.tap(find.text('Send a gift'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Rocket'));
      await tester.pump();
      expect(find.textContaining('Not enough coins. You need 365 more'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/gifts')) posts++;
      return _reply(r);
    }));
    expect(posts, 0);
  });

  testWidgets('gift sheet: affordable gift posts exactly one gift', (tester) async {
    final posts = <String>[];
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: FilledButton(onPressed: () => showGiftSheet(c, s, 'p1', 'asha'), child: const Text('Send a gift'))))));
      await tester.tap(find.text('Send a gift'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Rose'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/gifts')) posts.add(r.url.path);
      return _reply(r);
    }));
    expect(posts.length, 1);
  });

  testWidgets('blocked people: Unblock sends one DELETE for that person', (tester) async {
    final calls = <String>[];
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      await tester.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Unblock').first);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((r) async {
      if (r.method == 'DELETE') calls.add(r.url.path);
      return _reply(r);
    }));
    expect(calls, ['/api/v1/users/raju_k/block']);
  });

  testWidgets('search: tapping a person opens that profile request', (tester) async {
    final gets = <String>[];
    await http.runWithClient(() async {
      SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
      final s = Session();
      await tester.runAsync(() => s.restore());
      await tester.pumpWidget(MaterialApp(home: SearchPage(session: s)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(EditableText), 'ash');
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Asha Gurung'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((r) async {
      gets.add('${r.method} ${r.url.path}');
      return _reply(r);
    }));
    expect(gets.any((g) => g.startsWith('GET /api/v1/users/asha')), isTrue, reason: gets.join(', '));
  });

  testWidgets('create sheet: Continue stays off until a type is picked, then returns that type', (tester) async {
    String? result;
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, fontFamily: 'Roboto', fontFamilyFallback: []),
      home: Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () async => result = await showModalBottomSheet<String>(context: c, builder: (_) => const CreateSheet()), child: const Text('open'))))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
    await tester.tap(find.text('Reel'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNotNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, 'reel');
  });

  testWidgets('room: host buttons call the right callbacks', (tester) async {
    final log = <String>[];
    final chat = TextEditingController();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: RoomView(
      title: 'Test room', status: 'Live', failed: false, isHost: true, speaker: true, muted: false, handUp: false, inRoom: 3,
      hands: const {'u1': 'Bikash Thapa'},
      stage: const [(id: 'me', name: 'Bidur', host: true, you: true, muted: false, speaking: false), (id: 'u3', name: 'Sunita Rai', host: false, you: false, muted: false, speaking: false)],
      messages: const [], chat: chat,
      onEnd: () => log.add('end'), onToggleMic: () => log.add('mic'), onRaise: () => log.add('raise'), onGift: () => log.add('gift'),
      onAllow: (id, allow) => log.add('allow $id $allow'), onDismissHand: (id) => log.add('dismiss $id'), onSend: () => log.add('send'),
    )));
    await tester.pump();
    await tester.tap(find.text('Let speak'));
    await tester.tap(find.text('Dismiss'));
    await tester.tap(find.text('Move to listeners'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(log, ['allow u1 true', 'dismiss u1', 'allow u3 false', 'mic', 'send']);
  });
}

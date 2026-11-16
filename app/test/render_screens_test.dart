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
import 'package:sanjaal/chat_pages.dart' show ChatPage, ChatsPage;
import 'package:sanjaal/notifications_page.dart' show NotificationsPage;
import 'package:sanjaal/settings_page.dart' show SettingsPage;
import 'package:sanjaal/auth_page.dart' show AuthPage;
import 'package:sanjaal/onboarding_page.dart' show OnboardingPage;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/profile_pages.dart' show UserProfilePage;
import 'package:sanjaal/gifts.dart' show showGiftSheet;
import 'package:sanjaal/rooms_page.dart' show RoomView, RoomsPage;
import 'package:sanjaal/main.dart' show buildTheme;
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

Future<http.Response> _reply(http.Request r) async {
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
        {'kind': 'topup', 'amount': 100, 'created_at': _ago(240), 'counterparty': null, 'note': null},
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
        if (_voiceMsgs) {...m(4, 'asha', '', 40), 'kind': 'voice', 'media_url': 'https://example.invalid/v.m4a'},
        if (_voiceMsgs) {...m(5, 'me', '', 38), 'kind': 'voice', 'media_url': 'https://example.invalid/w.m4a'},
      ],
    });
  }
  return _json({'data': []});
}

Widget _room({bool isHost = false, bool speaker = false, bool handUp = false, bool failed = false, String status = 'Live', Map<String, String> hands = const {}, List<({String id, String name, bool host, bool you, bool muted, bool speaking})> stage = const []}) {
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
    messages: [
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
    await _loadFont('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    for (final name in ['chats', 'notifications', 'settings', 'auth', 'onboarding', 'chats_ne', 'wallet', 'gift', 'chat', 'rooms', 'room_host', 'room_listener', 'room_failed', 'gift_short', 'profile_full', 'chat_voice']) {
      testWidgets('$name ${b.name}', (tester) async {
        await http.runWithClient(() async {
          SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
          final s = Session();
          await tester.runAsync(() => s.restore());
          _voiceMsgs = name == 'chat_voice';
          await tester.runAsync(() => prefs.setLang(name.endsWith('_ne') ? 'ne' : 'en'));
          final key = GlobalKey();
          tester.view.physicalSize = name == 'gift_short' ? const Size(1080, 1260) : const Size(1080, 2160);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final theme = buildTheme(b, fontFamily: 'Roboto').copyWith(textTheme: buildTheme(b, fontFamily: 'Roboto').textTheme.apply(fontFamilyFallback: ['NotoDev']));
          final Widget home = switch (name) {
            'wallet' => WalletPage(session: s),
            'profile_full' => UserProfilePage(session: s, username: 'asha'),
            'rooms' => RoomsPage(session: s),
            'chats' || 'chats_ne' => ChatsPage(session: s),
            'notifications' => NotificationsPage(session: s),
            'settings' => SettingsPage(session: s),
            'auth' => AuthPage(session: s),
            'onboarding' => const OnboardingPage(),
            'room_host' => _room(isHost: true, speaker: true, hands: {'u1': 'Bikash Thapa', 'u2': ''}, stage: [(id: 'me', name: 'Bidur Khatri', host: true, you: true, muted: false, speaking: true), (id: 'u3', name: 'Sunita Rai', host: false, you: false, muted: true, speaking: false), (id: 'u4', name: 'Asha Gurung', host: false, you: false, muted: false, speaking: false)]),
            'room_listener' => _room(isHost: false, speaker: false, handUp: true, stage: [(id: 'h', name: 'Asha Gurung', host: true, you: false, muted: false, speaking: true), (id: 'u3', name: 'Sunita Rai', host: false, you: false, muted: true, speaking: false)]),
            'room_failed' => _room(failed: true, status: 'Could not join the room. Check your connection and try again.'),
            'chat_voice' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            'chat' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            _ => Builder(builder: (c) => Scaffold(appBar: AppBar(title: const Text('Post')), body: Center(child: FilledButton(onPressed: () => showGiftSheet(c, s, 'p1', 'asha'), child: const Text('Send a gift'))))),
          };
          final nav = GlobalKey<NavigatorState>();
          final pushed = name != 'gift' && name != 'gift_short' && name != 'onboarding' && name != 'auth';
          await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(navigatorKey: nav, theme: theme, builder: (c, child) => Column(children: [Expanded(child: child!), Container(width: double.infinity, color: const Color(0xFF444444), padding: const EdgeInsets.symmetric(vertical: 2), child: const Text('DEMO DATA: test fixture, not live', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 10, decoration: TextDecoration.none, fontWeight: FontWeight.w400)))]), debugShowCheckedModeBanner: false, home: pushed ? const Scaffold(body: SizedBox()) : home)));
          // The real app opens these screens with Navigator.push, so the app bar shows a back button.
          if (pushed) nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => home));
          if (name == 'gift' || name == 'gift_short') {
            await tester.tap(find.text('Send a gift'));
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
}

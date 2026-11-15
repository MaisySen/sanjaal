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
import 'package:sanjaal/chat_pages.dart' show ChatPage;
import 'package:sanjaal/gifts.dart' show showGiftSheet;
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

Future<http.Response> _reply(http.Request r) async {
  final p = r.url.path;
  if (p == '/oauth/token') return _json({'access_token': 'x', 'expires_in': 3600, 'refresh_token': 'r'});
  if (p.endsWith('/auth/me')) return _json({'user': {'public_id': 'me', 'name': 'Bidur', 'username': 'bidur'}});
  if (p.endsWith('/gifts')) {
    return _json({
      'data': [
        {'key': 'rose', 'name': 'Rose', 'coins': 5},
        {'key': 'momo', 'name': 'Momo', 'coins': 10},
        {'key': 'khada', 'name': 'Khada', 'coins': 20},
        {'key': 'mountain', 'name': 'Himal', 'coins': 50},
      ]
    });
  }
  if (p.endsWith('/wallet')) {
    return _json({
      'balance': 135,
      'entries': [
        {'kind': 'topup', 'amount': 100, 'created_at': _ago(240), 'counterparty': null, 'note': null},
        {'kind': 'gift_sent', 'amount': -20, 'created_at': _ago(90), 'counterparty': 'asha', 'note': 'Khada'},
        {'kind': 'gift_received', 'amount': 55, 'created_at': _ago(30), 'counterparty': 'bikash', 'note': null},
      ],
      'topup': {'esewa': true, 'esewa_mode': 'test'},
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
      ],
    });
  }
  return _json({'data': []});
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final dir = '$root/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', ['$dir/Roboto-Regular.ttf', '$dir/Roboto-Medium.ttf', '$dir/Roboto-Bold.ttf']);
    await _loadFont('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    for (final name in ['wallet', 'gift', 'chat']) {
      testWidgets('$name ${b.name}', (tester) async {
        await http.runWithClient(() async {
          SharedPreferences.setMockInitialValues({'refresh_token': 'r'});
          final s = Session();
          await tester.runAsync(() => s.restore());
          final key = GlobalKey();
          tester.view.physicalSize = const Size(1080, 2160);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final theme = buildTheme(b, fontFamily: 'Roboto');
          final Widget home = switch (name) {
            'wallet' => WalletPage(session: s),
            'chat' => ChatPage(session: s, convo: {'public_id': 'c1', 'type': 'direct', 'title': 'Asha Gurung'}),
            _ => Builder(builder: (c) => Scaffold(appBar: AppBar(title: const Text('Post')), body: Center(child: FilledButton(onPressed: () => showGiftSheet(c, s, 'p1', 'asha'), child: const Text('Send a gift'))))),
          };
          await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: theme, debugShowCheckedModeBanner: false, home: home)));
          if (name == 'gift') {
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
          await tester.pump(const Duration(seconds: 1));
        }, () => MockClient(_reply));
      });
    }
  }
}

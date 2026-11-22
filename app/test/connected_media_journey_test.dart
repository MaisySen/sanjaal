// Actual root, creator and tab routes with fake permission/picker/HTTP only.
// This is not a native library, camera, real upload or deployed replay claim.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/media_library_page.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/upload_pending_store.dart';

import 'connected_first_use_test.dart' as connected;

class SelectedPhoto extends ImagePickerPlatform {
  SelectedPhoto(this.bytes);
  final Uint8List bytes;
  int selections = 0;
  @override
  Future<List<XFile>?> getMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    selections++;
    return [
      XFile.fromData(
        bytes,
        path: 'synthetic-photo.png',
        name: 'synthetic-photo.png',
        mimeType: 'image/png',
      ),
    ];
  }
}

http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(font.$1)
            ..addFont(File(font.$2).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  for (final replaySafe in [false, true]) {
    testWidgets(
      'connected photo selection lost response ${replaySafe ? 'explicit original retry' : 'legacy check before a separate upload'}',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'onboarded': true,
          'theme': 'light',
        });
        FlutterSecureStorage.setMockInitialValues({});
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final bytes = File('test/fixtures/ridge.png').readAsBytesSync();
        final oldPicker = ImagePickerPlatform.instance,
            picker = SelectedPhoto(bytes);
        ImagePickerPlatform.instance = picker;
        addTearDown(() => ImagePickerPlatform.instance = oldPicker);
        final channel = const MethodChannel('com.fluttercandies/photo_manager');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'requestPermissionExtend');
              return 0; // synthetic denied
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        feedImageProvider = (_) => MemoryImage(bytes);
        addTearDown(() => feedImageProvider = null);
        final key = GlobalKey();
        final requests = <String>[];
        final sent = <String>[];
        var writes = 0;
        final confirmed = <Map<String, dynamic>>[];
        final member = {
          'public_id': 'member',
          'username': 'member',
          'name': 'Community Member',
          'posts_count': 1,
          'followers_count': 0,
          'following_count': 0,
        };
        final post = {
          'public_id': 'original-photo',
          'kind': 'post',
          'body': 'A moment worth keeping',
          'media': [
            {
              'type': 'image',
              'url': 'https://fixture.invalid/selected.png',
              'mime': 'image/png',
            },
          ],
          'author': member,
          'created_at': '2026-11-21T15:00:00Z',
          'likes_count': 0,
          'comments_count': 0,
        };
        await http.runWithClient(
          () async {
            await t.pumpWidget(
              RepaintBoundary(
                key: key,
                child: const SanjaalApp(fontFamily: 'Roboto'),
              ),
            );
            await connected.flush(t);
            await t.enterText(find.byType(TextFormField).first, 'member');
            await t.enterText(
              find.byType(TextFormField).last,
              'synthetic-password',
            );
            await connected.tapText(t, 'Sign in');
            await t.tap(find.byTooltip('Post').first);
            await connected.flush(t);
            await connected.tapText(t, 'Post');
            await connected.tapText(t, 'Continue');
            await connected.tapText(t, 'Photos');
            expect(find.byType(MediaLibraryPage), findsOneWidget);
            expect(writes, 0);
            await t.tap(find.text('Device picker').last);
            await connected.flush(t);
            expect(picker.selections, 1);
            expect(find.byType(MediaLibraryPage), findsNothing);
            expect(find.byType(ComposePage), findsOneWidget);
            expect(writes, 0);
            await t.enterText(find.byType(TextField), 'A moment worth keeping');
            await t.pump();
            await connected.flush(t);
            await connected.flush(t);
            await connected.capture(
              t,
              key,
              'photo-review-${replaySafe ? 'replay' : 'legacy'}',
            );
            await t.tap(find.widgetWithText(FilledButton, 'Post'));
            await connected.flush(t);
            expect(find.byType(ComposePage), findsNothing);
            expect(writes, 1);
            final session = t.widget<HomeShell>(find.byType(HomeShell)).session,
                center = UploadCenter.of(
                  t.widget<HomeShell>(find.byType(HomeShell)).session,
                );
            expect(center.canRetry, replaySafe);
            expect(center.confirmedPosts, isEmpty);
            expect(await const UploadPendingStore().read('member'), isNotNull);
            await t.tap(
              find.descendant(
                of: find.byType(GlassNavBar),
                matching: find.byTooltip('Wallet'),
              ),
            );
            await connected.flush(t);
            await t.tap(
              find.descendant(
                of: find.byType(GlassNavBar),
                matching: find.byTooltip('Home'),
              ),
            );
            await connected.flush(t);
            expect(
              writes,
              1,
              reason: 'tab return never automatically replays an upload',
            );
            await connected.capture(
              t,
              key,
              'photo-recovery-${replaySafe ? 'replay' : 'legacy'}',
            );
            if (replaySafe) {
              await t.tap(
                find.descendant(
                  of: find.byType(UploadStrip),
                  matching: find.text('Try again'),
                ),
              );
              await connected.flush(t);
              expect(writes, 2);
              expect(sent[1], sent[0]);
              expect(picker.selections, 1);
              expect(center.error, isNull);
              expect(
                center.confirmedPosts.single['public_id'],
                'original-photo',
              );
              expect(await const UploadPendingStore().read('member'), isNull);
              expect(find.text('A moment worth keeping'), findsOneWidget);
              expect(find.text('Your post is up.'), findsOneWidget);
              await connected.capture(t, key, 'photo-confirmed');
              await t.tap(
                find.descendant(
                  of: find.byType(GlassNavBar),
                  matching: find.byTooltip('Me'),
                ),
              );
              await connected.flush(t);
              expect(find.text('Open original'), findsNothing);
              expect(find.byType(Image), findsWidgets);
              await t.tap(
                find.descendant(
                  of: find.byType(GlassNavBar),
                  matching: find.byTooltip('Home'),
                ),
              );
              await connected.flush(t);
              expect(find.text('A moment worth keeping'), findsOneWidget);
            } else {
              center.retry();
              await connected.flush(t);
              expect(writes, 1);
              expect(center.occupied, isTrue);
              await t.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.byTooltip('Me')));await connected.flush(t);
              expect(find.byType(Image),findsWidgets);
              expect(center.occupied,isTrue,reason:'viewing the original does not silently clear uncertainty');
              expect(confirmed,hasLength(1));expect(writes,1);
              await connected.capture(t,key,'photo-legacy-profile-check');

              await t.tap(find.byTooltip('Dismiss'));
              await t.pumpAndSettle();
              expect(find.text('Discard this draft?'), findsOneWidget);
              await connected.tapText(t, 'Cancel');
              expect(center.occupied, isTrue);
              expect(session.user?['public_id'], 'member');
              expect(writes, 1);
            }
            expect(
              requests.where(
                (r) => !{
                  'POST /oauth/token',
                  'GET /auth/me',
                  'GET /notifications/summary',
                  'GET /posts',
                  'GET /stories',
                  'GET /calls/incoming',
                  'POST /posts',
                  'GET /wallet',
                  'GET /wallet/withdrawals',
                  'GET /users/member',
                }.contains(r),
              ),
              isEmpty,
            );
            expect(session.offline, isFalse);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          },
          () => MockClient((r) async {
            final path = r.url.path.replaceFirst('/api/v1', '');
            requests.add('${r.method} $path');
            if (path.endsWith('/oauth/token')) {
              return response({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (path == '/auth/me') {
              return response({
                'user': member,
                'features': {'upload_intents': replaySafe},
              });
            }
            if (path == '/posts' && r.method == 'POST') {
              writes++;
              final body = latin1.decode(r.bodyBytes);
              sent.add(
                body.replaceAll(
                  RegExp(r'--dart-http-boundary-[^\r\n]+'),
                  '--BOUNDARY',
                ),
              );
              expect(body, contains('A moment worth keeping'));
              expect(body, contains('filename="synthetic-photo.png"'));
              expect(body, contains('image/png'));
              expect(body, contains(latin1.decode(bytes)));
              expect(body.contains('name="upload_intent"'), replaySafe);
              if (writes == 1) {
                confirmed.add(post);
                throw const SocketException(
                  'Synthetic reply lost after server commit',
                );
              }
              return response({'post': post, 'replayed': true});
            }
            expect(r.method, 'GET');
            if (path == '/posts') {
              return response({'data': confirmed, 'next_cursor': null});
            }
            if (path == '/users/member') return response({'user': member});
            if (path == '/wallet/withdrawals') return response({'data': []});
            if (path == '/wallet') {
              return response({
                'balance': 0,
                'entries': [],
                'topup': {},
                'transfer_available': false,
                'cash_out_available': false,
              });
            }
            expect([
              '/notifications/summary',
              '/stories',
              '/calls/incoming',
            ], contains(path));
            return response({'data': [], 'unread_messages': 0});
          }),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
}

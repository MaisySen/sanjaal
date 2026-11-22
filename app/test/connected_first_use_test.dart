// Connected first-use auth with actual root/widgets and synthetic HTTP only.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/profile_setup_page.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/onboarding_page.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:sanjaal/password_recovery_page.dart';

http.Response reply(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 25)),
  );
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final finder = find.text(text);
  await t.ensureVisible(finder);
  await t.tap(finder);
  await flush(t);
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/downloads/sanjaal-discovery-review/connected-$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final f in [
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
      await (FontLoader(f.$1)..addFont(
            File(f.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs.lang = 'en';
  });
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'welcome signup success then failed automatic login continues at sign in without repeating signup $lang',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'theme': 'light',
          'lang': lang,
        });
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        var signups = 0, grants = 0;
        final key = GlobalKey();
        await http.runWithClient(
          () async {
            await t.pumpWidget(
              RepaintBoundary(
                key: key,
                child: const SanjaalApp(fontFamily: 'Roboto'),
              ),
            );
            await flush(t);
            expect(find.byType(OnboardingPage), findsOneWidget);
            await tapText(t, t_('Create an account'));
            expect(find.byType(TextFormField), findsNWidgets(3));
            await t.enterText(
              find.byType(TextFormField).at(0),
              'fixture@invalid.example',
            );
            await t.enterText(
              find.byType(TextFormField).at(1),
              'fixture_member',
            );
            await t.enterText(
              find.byType(TextFormField).at(2),
              'synthetic-password',
            );
            await tapText(t, t_('Create account'));
            expect(signups, 1);
            expect(grants, 1);
            expect(
              find.text(t_('Your account was created. Sign in to continue.')),
              findsOneWidget,
            );
            expect(
              find.byType(TextFormField),
              findsNWidgets(2),
              reason: 'confirmed account creation must lead to sign-in, not repeat signup',
            );
            expect(
              t
                  .widget<TextFormField>(find.byType(TextFormField).first)
                  .controller!
                  .text,
              'fixture@invalid.example',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await t.ensureVisible(
              find.widgetWithText(FilledButton, t_('Sign in')),
            );
            await flush(t);
            await capture(t, key, 'signup-signin-$lang-large');
            await tapText(t, t_('Sign in'));
            expect(signups, 1);
            expect(grants, 2);
            expect(find.byType(HomeShell), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/dbconnections/signup')) {
              signups++;
              return reply({'email': 'fixture@invalid.example'});
            }
            if (r.url.path.endsWith('/oauth/token')) {
              grants++;
              return grants == 1
                  ? reply({'error': 'temporarily_unavailable'}, 503)
                  : reply({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (r.url.path.endsWith('/auth/me')) {
              return reply({
                'user': {'public_id': 'fixture', 'username': 'fixture_member'},
              });
            }
            return reply({
              'data': [],
              'next_cursor': null,
              'unread_messages': 0,
              'balance': 0,
              'entries': [],
            });
          }),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'existing member recovery returns to the same sign in form $lang',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'theme': 'light',
          'lang': lang,
        });
        var resets = 0, grants = 0;
        await http.runWithClient(
          () async {
            await t.pumpWidget(const SanjaalApp(fontFamily: 'Roboto'));
            await flush(t);
            await tapText(t, t_('Sign in'));
            expect(find.byType(TextFormField), findsNWidgets(2));
            await t.enterText(
              find.byType(TextFormField).first,
              'returning@invalid.example',
            );
            await t.enterText(
              find.byType(TextFormField).last,
              'synthetic-password',
            );
            await tapText(t, t_('Forgot password?'));
            expect(find.byType(PasswordRecoveryPage), findsOneWidget);
            expect(
              t
                  .widget<TextFormField>(find.byType(TextFormField))
                  .controller!
                  .text,
              'returning@invalid.example',
            );
            await tapText(t, t_('Send reset link'));
            expect(resets, 1);
            expect(grants, 0);
            await t.pageBack();
            await flush(t);
            expect(find.byType(AuthPage), findsOneWidget);
            expect(
              t
                  .widget<TextFormField>(find.byType(TextFormField).first)
                  .controller!
                  .text,
              'returning@invalid.example',
            );
            expect(
              t
                  .widget<TextFormField>(find.byType(TextFormField).last)
                  .controller!
                  .text,
              'synthetic-password',
            );
            await tapText(t, t_('Sign in'));
            expect(grants, 1);
            expect(find.byType(HomeShell), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/dbconnections/change_password')) {
              resets++;
              return http.Response('', 200);
            }
            if (r.url.path.endsWith('/oauth/token')) {
              grants++;
              return reply({'access_token': 'fixture', 'expires_in': 3600});
            }
            if (r.url.path.endsWith('/auth/me')) {
              return reply({
                'user': {'public_id': 'fixture', 'username': 'fixture_member'},
              });
            }
            return reply({
              'data': [],
              'next_cursor': null,
              'unread_messages': 0,
              'balance': 0,
              'entries': [],
            });
          }),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  testWidgets(
    'new member joins creates finds a person follows chats edits profile and returns home',
    (t) async {
      SharedPreferences.setMockInitialValues({'theme': 'light'});
      final writes = <String>[];
      final reads = <String>{};
      var followed = false;
      String displayName = 'New Member';
      final me = <String, dynamic>{
        'public_id': 'me',
        'username': 'new_member',
        'name': displayName,
        'bio': '',
        'posts_count': 0,
        'followers_count': 0,
        'following_count': 0,
      };
      final posts = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[];
      final messageAttempts = <Map>[];
      await http.runWithClient(
        () async {
          t.view.physicalSize = const Size(390, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: const SanjaalApp(fontFamily: 'Roboto'),
            ),
          );
          await flush(t);
          await capture(t, key, 'welcome');
          await tapText(t, 'Create an account');
          await capture(t, key, 'register');
          await t.enterText(
            find.byType(TextFormField).at(0),
            'new@invalid.example',
          );
          await t.enterText(find.byType(TextFormField).at(1), 'new_member');
          await t.enterText(
            find.byType(TextFormField).at(2),
            'synthetic-password',
          );
          await tapText(t, 'Create account');
          expect(find.byType(ProfileSetupPage), findsOneWidget);
          expect(find.byType(HomeShell), findsNothing);
          await capture(t, key, 'optional_profile');
          await tapText(t, 'Continue to Sanjaal');
          expect(find.byType(HomeShell), findsOneWidget);
          expect(find.text('Nothing here yet'), findsOneWidget);
          await t.tap(find.byTooltip('Post').first);
          await flush(t);
          await tapText(t, 'Post');
          await tapText(t, 'Continue');
          expect(find.byType(ComposePage), findsOneWidget);
          await t.enterText(
            find.byType(TextField),
            'My first community update',
          );
          await t.pump();
          await t.tap(find.widgetWithText(FilledButton, 'Post'));
          await flush(t);
          expect(find.byType(ComposePage), findsNothing);
          expect(find.text('My first community update'), findsWidgets);
          expect(find.text('Your post is up.'), findsOneWidget);
          await capture(t, key, 'first-post');
          await t.tap(find.byTooltip('Search').first);
          await flush(t);
          expect(find.byType(SearchPage), findsOneWidget);
          expect(find.text('Your post is up.'), findsNothing);
          expect(find.text('Open original'), findsNothing);
          await t.enterText(find.byType(TextField), 'asha');
          await t.pump(const Duration(milliseconds: 400));
          await flush(t);
          await tapText(t, 'Asha Gurung');
          expect(find.byType(UserProfilePage), findsOneWidget);
          await tapText(t, 'Follow');
          expect(followed, isTrue);
          expect(find.text('Unfollow'), findsOneWidget);
          await tapText(t, 'Message');
          expect(find.byType(ChatPage), findsOneWidget);
          await t.enterText(find.byType(TextField), 'Hello from the community');
          await t.tap(find.byTooltip('Send message'));
          await flush(t);
          expect(messages, isEmpty);
          expect(
            find.text('Delivery unconfirmed. Tap to retry.'),
            findsOneWidget,
          );
          await t.enterText(find.byType(TextField), 'A newer unsent thought');
          await t.tap(find.text('Delivery unconfirmed. Tap to retry.'));
          await flush(t);
          expect(messageAttempts, hasLength(2));
          expect(messageAttempts[1], messageAttempts[0]);
          expect(find.text('A newer unsent thought'), findsOneWidget);
          expect(messages.length, 1);
          expect(find.text('Hello from the community'), findsOneWidget);
          await t.pump(const Duration(seconds:5));await flush(t);
          await capture(t, key, 'first-chat');
          await t.pageBack();
          await flush(t);
          expect(find.text('Leave chat?'), findsOneWidget);
          await tapText(t, 'Stay here');
          expect(find.text('A newer unsent thought'), findsOneWidget);
          await t.enterText(find.byType(TextField), '');
          await t.pump();
          await t.pageBack();
          await flush(t);
          await t.pageBack();
          await flush(t);
          await t.pageBack();
          await flush(t);
          expect(find.byType(HomeShell), findsOneWidget);
          await t.tap(
            find.descendant(
              of: find.byType(GlassNavBar),
              matching: find.byTooltip('Me'),
            ),
          );
          await flush(t);
          await tapText(t, 'Edit profile');
          await t.enterText(
            find.byType(TextFormField).first,
            'Community Member',
          );
          await tapText(t, 'Save');
          expect(find.byType(EditProfilePage), findsNothing);
          expect(find.text('Community Member'), findsOneWidget);
          expect(find.text('Your post is up.'), findsNothing);
          expect(find.text('Open original'), findsNothing);
          await capture(t, key, 'profile');
          await t.tap(find.byTooltip('Settings'));
          await flush(t);
          expect(find.byType(SettingsPage), findsOneWidget);
          await t.pageBack();
          await flush(t);
          await t.tap(
            find.descendant(
              of: find.byType(GlassNavBar),
              matching: find.byTooltip('Home'),
            ),
          );
          await flush(t);
          expect(find.text('My first community update'), findsWidgets);
          expect(
            writes,
            containsAllInOrder([
              'POST /dbconnections/signup',
              'POST /oauth/token',
              'POST /posts',
              'POST /users/asha/follow',
              'POST /conversations',
              'POST /conversations/chat/messages',
              'POST /conversations/chat/messages',
              'PATCH /auth/me',
            ]),
          );
          expect(
            reads,
            containsAll([
              '/auth/me',
              '/posts',
              '/stories',
              '/users/search',
              '/users/asha',
              '/conversations/chat/messages',
              '/users/new_member',
            ]),
          );
          expect(
            reads.difference({
              '/auth/me',
              '/notifications/summary',
              '/posts',
              '/stories',
              '/users/search',
              '/calls/incoming',
              '/users/asha',
              '/conversations/chat/messages',
              '/users/new_member',
            }),
            isEmpty,
          );
          expect(
            writes.where(
              (w) => !{
                'POST /dbconnections/signup',
                'POST /oauth/token',
                'POST /posts',
                'POST /users/asha/follow',
                'POST /conversations',
                'POST /conversations/chat/messages',
                'PATCH /auth/me',
                'POST /conversations/chat/typing',
                'POST /conversations/chat/read',
              }.contains(w),
            ),
            isEmpty,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 5));
        },
        () => MockClient((r) async {
          final path = r.url.path.replaceFirst('/api/v1', '');
          if (r.method != 'GET') {
            writes.add('${r.method} $path');
          } else {
            reads.add(path);
          }
          if (path.endsWith('/dbconnections/signup')) {
            return reply({'email': 'new@invalid.example'});
          }
          if (path.endsWith('/oauth/token')) {
            return reply({'access_token': 'fixture', 'expires_in': 3600});
          }
          if (path == '/auth/me' && r.method == 'PATCH') {
            final body = jsonDecode(r.body) as Map;
            me.addAll(body.cast<String, dynamic>());
            return reply({'user': me});
          }
          if (path == '/auth/me') return reply({'user': me});
          if (path == '/posts' && r.method == 'POST') {
            final post = <String, dynamic>{
              'public_id': 'first-post',
              'kind': 'post',
              'body': 'My first community update',
              'media': [],
              'author': Map.of(me),
              'created_at': '2026-11-21T15:00:00Z',
              'likes_count': 0,
              'comments_count': 0,
            };
            posts.add(post);
            me['posts_count'] = 1;
            return reply({'post': post}, 201);
          }
          if (path == '/posts') {
            return reply({
              'data': r.url.queryParameters['username'] == 'asha' ? [] : posts,
              'next_cursor': null,
            });
          }
          if (path == '/users/search') {
            return reply({
              'users': [
                {
                  'public_id': 'asha',
                  'username': 'asha',
                  'name': 'Asha Gurung',
                },
              ],
              'hashtags': [],
            });
          }
          if (path == '/users/asha/follow') {
            followed = true;
            return reply({});
          }
          if (path == '/users/asha') {
            return reply({
              'user': {
                'public_id': 'asha',
                'username': 'asha',
                'name': 'Asha Gurung',
                'following': followed,
                'followers_count': followed ? 1 : 0,
                'following_count': 0,
                'posts_count': 0,
              },
            });
          }
          if (path == '/users/new_member') return reply({'user': me});
          if (path == '/conversations' && r.method == 'POST') {
            return reply({
              'conversation': {
                'public_id': 'chat',
                'type': 'direct',
                'title': 'Asha Gurung',
                'members': [me, {'public_id': 'asha', 'username': 'asha', 'name': 'Asha Gurung'}],
              },
            });
          }
          if (path == '/conversations/chat/messages' && r.method == 'POST') {
            final body = jsonDecode(r.body) as Map;
            messageAttempts.add(Map.of(body));
            if (messageAttempts.length == 1) {
              return reply({'message': 'Synthetic temporary rejection'}, 503);
            }
            final message = <String, dynamic>{
              'public_id': 'message',
              'body': body['body'],
              'client_id': body['client_id'],
              'sender': me,
              'seq': 1,
              'kind': 'text',
              'created_at': '2026-11-21T15:00:00Z',
            };
            messages.add(message);
            return reply({'message': message});
          }
          if (path == '/conversations/chat/messages') {
            return reply({'data': messages, 'has_more': false});
          }
          if (r.method=='POST' && {'/conversations/chat/read','/conversations/chat/typing'}.contains(path)) return reply({});
          expect(
            r.method,
            'GET',
            reason: 'unexpected mutation in connected fixture',
          );
          expect(
            ['/notifications/summary', '/stories', '/calls/incoming'],
            contains(path),
            reason: 'unhandled read must not become a fake empty success',
          );
          return reply({
            'data': [],
            'next_cursor': null,
            'unread_messages': 0,
            'balance': 0,
            'entries': [],
          });
        }),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

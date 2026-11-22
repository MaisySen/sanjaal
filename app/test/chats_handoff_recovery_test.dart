// Connected synthetic create/send/Back and uncertain-result inbox recovery.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;
import 'profile_chat_receipt_test.dart' as receipt;

const person = {'public_id': 'asha', 'username': 'asha', 'name': 'Asha Gurung'};
IconButton newChat(WidgetTester t) => t.widget<IconButton>(
  find.byWidgetPredicate((w) => w is IconButton && w.tooltip == t_('New chat')),
);
Future<void> start(WidgetTester t, {bool group = false}) async {
  await t.tap(find.byTooltip(t_('New chat')));
  await p.flush(t);
  if (group) {
    await t.tap(find.byTooltip(t_('New group')));
    await p.flush(t);
    await t.enterText(find.byType(TextField).first, 'Community meetup');
  }
  await t.enterText(find.byType(TextField).last, 'asha');
  await p.flush(t);
  await t.tap(find.text('Asha Gurung'));
  await p.flush(t);
  if (group) {
    await t.tap(find.byType(FilledButton));
    await p.flush(t);
  }
}

void main() {
  extraRecoveryCases();
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final archived in [false, true]) {
    for (final failRead in [false, true]) {
      final language = archived ? 'ne' : 'en';
      testWidgets(
        'uncertain creation from ${archived ? 'Archived' : 'Chats'} ${failRead ? 'keeps creation gated through read failure' : 'resolves through the actual inbox'}',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final refresh = Completer<http.Response>();
          var creates = 0, inboxReads = 0, chatReads = 0;
          final scopes = <String?>[];
          await p.fixture(
            t,
            (s) => ChatsPage(session: s),
            () async {
              if (archived) {
                await t.tap(find.byTooltip(t_('More')));
                await p.flush(t);
                await t.tap(find.text(t_('Archived chats')));
                await p.flush(t);
              }
              final oldNew = newChat(t).onPressed!;
              final oldMore = t
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .onSelected!;
              await start(t);
              await t.ensureVisible(find.text(t_('Back to Chats')));
              await t.tap(find.text(t_('Back to Chats')));
              await p.flush(t);
              await t.pump(const Duration(milliseconds: 450));
              await t.pump();
              expect(find.text(t_('Chats')), findsOneWidget);
              expect(scopes.last, isNull);
              expect(newChat(t).onPressed, isNull);
              expect(find.byType(LinearProgressIndicator), findsOneWidget);
              oldNew();
              oldMore('archive');
              await p.flush(t);
              expect(find.byType(NewChatPage), findsNothing);
              expect(creates, 1);
              if (failRead) {
                await p.shot(t, 'inbox_uncertain_pending_$language');
              }
              refresh.complete(
                failRead
                    ? p.json({'message': 'Synthetic inbox unavailable'}, 503)
                    : p.json({
                        'data': [receipt.conversation()],
                      }),
              );
              await p.flush(t);
              if (failRead) {
                expect(find.text(t_('Could not load this.')), findsOneWidget);
                expect(newChat(t).onPressed, isNull);
                expect(find.text(t_('Start a conversation')), findsNothing);
                oldNew();
                oldMore('archive');
                await p.flush(t);
                expect(find.byType(NewChatPage), findsNothing);
                expect(scopes.last, isNull);
                await p.shot(t, 'inbox_uncertain_failed_$language');
                await t.tap(find.text(t_('Try again')));
                await p.flush(t);
              }
              expect(find.text('Selected member'), findsOneWidget);
              expect(newChat(t).onPressed, isNotNull);
              expect(creates, 1);
              expect(chatReads, 0);
              expect(find.byType(ChatPage), findsNothing);
              expect(inboxReads, (archived ? 3 : 2) + (failRead ? 1 : 0));
              expect(t.takeException(), isNull);
            },
            language: language,
            brightness: archived ? Brightness.dark : Brightness.light,
            scale: 1.8,
            respond: (r) async {
              if (r.url.path.endsWith('/users/search')) {
                return p.json({
                  'users': [person],
                });
              }
              if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
                creates++;
                return p.json({'message': 'Synthetic unknown creation'}, 503);
              }
              if (r.url.path.endsWith('/conversations')) {
                inboxReads++;
                scopes.add(r.url.queryParameters['archived']);
                if (creates == 0) return p.json({'data': []});
                if (inboxReads == (archived ? 3 : 2)) return refresh.future;
                return p.json({
                  'data': [receipt.conversation()],
                });
              }
              if (r.url.path.endsWith('/messages')) chatReads++;
              return p.json({'data': [], 'has_more': false});
            },
          );
        },
      );
    }
  }
  for (final group in [false, true]) {
    final language = group ? 'ne' : 'en';
    testWidgets(
      'actual ${group ? 'group' : 'direct'} create opens sends and returns to the refreshed inbox $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var creates = 0, inboxReads = 0, sends = 0;
        final messages = <Map<String, dynamic>>[];
        final convo = {
          ...receipt.conversation(),
          if (group) 'type': 'group',
          if (group) 'title': 'Community meetup',
          if (group) 'my_role': 'owner',
        };
        await p.fixture(
          t,
          (s) => ChatsPage(session: s),
          () async {
            await start(t, group: group);
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(ChatPage), findsOneWidget);
            expect(inboxReads, 1);
            expect(creates, 1);
            await t.enterText(
              find.byType(TextField),
              'Hello from the new conversation',
            );
            await t.tap(find.byTooltip(t_('Send message')));
            await p.flush(t);
            await p.flush(t);
            expect(sends, 1);
            expect(messages, hasLength(1));
            expect(
              find.text('Hello from the new conversation'),
              findsOneWidget,
            );
            await p.shot(t, 'inbox_handoff_sent_$language');
            await t.pageBack();
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(ChatPage), findsNothing);
            expect(inboxReads, 2);
            expect(creates, 1);
            expect(sends, 1);
            expect(
              find.text(group ? 'Community meetup' : 'Selected member'),
              findsOneWidget,
            );
            expect(
              find.text('Hello from the new conversation'),
              findsOneWidget,
            );
            await p.shot(t, 'inbox_handoff_back_$language');
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: group ? Brightness.dark : Brightness.light,
          scale: 1.8,
          respond: (r) async {
            final path = r.url.path;
            if (path.endsWith('/users/search')) {
              return p.json({
                'users': [person],
              });
            }
            if (r.method == 'POST' && path.endsWith('/conversations')) {
              creates++;
              return p.json({'conversation': convo});
            }
            if (path.endsWith('/conversations')) {
              inboxReads++;
              return p.json({
                'data': creates == 0
                    ? []
                    : [
                        {
                          ...convo,
                          'last_message': messages.isEmpty
                              ? null
                              : messages.last,
                          'unread': 0,
                        },
                      ],
              });
            }
            if (path.endsWith('/conversations/created-chat/messages')) {
              if (r.method == 'POST') {
                sends++;
                final body = jsonDecode(r.body) as Map;
                final message = <String, dynamic>{
                  'public_id': 'server-message',
                  'client_id': body['client_id'],
                  'body': body['body'],
                  'sender': {'public_id': 'me', 'username': 'fixture'},
                  'kind': 'text',
                  'seq': 1,
                  'created_at': '2026-11-22T00:00:00Z',
                };
                messages.add(message);
                return p.json({'message': message});
              }
              return p.json({'data': messages, 'has_more': false});
            }
            if (r.method == 'POST') {
              expect(
                path.endsWith('/read') || path.endsWith('/typing'),
                isTrue,
                reason: 'no other mutation in this journey',
              );
              return p.json({});
            }
            return p.json({'data': [], 'has_more': false});
          },
        );
      },
    );
  }
}

void extraRecoveryCases() {
  for (final mode in [
    'untouched cancel',
    'system Back',
    'malformed inbox',
    'cached inbox',
  ]) {
    testWidgets('inbox handoff handles $mode without replay', (t) async {
      final retry = Completer<http.Response>();
      var creates = 0, reads = 0, chatReads = 0;
      final scopes = <String?>[];
      final cancel = mode == 'untouched cancel';
      final badRead = mode == 'malformed inbox' || mode == 'cached inbox';
      await p.fixture(
        t,
        (s) => ChatsPage(session: s),
        () async {
          if (cancel) {
            await t.tap(find.byTooltip(t_('More')));
            await p.flush(t);
            await t.tap(find.text(t_('Archived chats')));
            await p.flush(t);
            await t.tap(find.byTooltip(t_('New chat')));
            await p.flush(t);
            await t.pumpAndSettle();
          } else {
            await start(t);
          }
          if (cancel) {
            await t.pageBack();
          } else if (mode == 'system Back') {
            await t.binding.handlePopRoute();
          } else {
            await t.ensureVisible(find.text(t_('Back to Chats')));
            await t.tap(find.text(t_('Back to Chats')));
          }
          await p.flush(t);
          // These first reads complete immediately; only the later retry is held.
          await t.pumpAndSettle();
          expect(find.byType(NewChatPage), findsNothing);
          expect(find.byType(ChatPage), findsNothing);
          if (cancel) {
            expect(find.text(t_('Archived')), findsOneWidget);
            expect(reads, 2, reason: 'Untouched cancel adds no inbox request');
            expect(scopes.last, '1');
            expect(newChat(t).onPressed, isNotNull);
          } else if (badRead) {
            expect(newChat(t).onPressed, isNull);
            expect(find.text(t_('Start a conversation')), findsNothing);
            if (mode == 'malformed inbox') {
              expect(
                find.text(t_('Chats could not be loaded.')),
                findsOneWidget,
              );
            } else {
              expect(find.text('Selected member'), findsOneWidget);
              expect(find.text(t_('Could not refresh.')), findsOneWidget);
            }
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(find.byType(LinearProgressIndicator), findsOneWidget);
            expect(newChat(t).onPressed, isNull);
            expect(find.text(t_('Start a conversation')), findsNothing);
            if (mode == 'malformed inbox') {
              expect(find.byType(CircularProgressIndicator), findsOneWidget);
            } else {
              expect(find.text('Selected member'), findsOneWidget);
              expect(
                t
                    .widget<TextButton>(
                      find.widgetWithText(TextButton, t_('Try again')),
                    )
                    .onPressed,
                isNull,
              );
            }
            retry.complete(
              p.json({
                'data': [receipt.conversation()],
              }),
            );
            await p.flush(t);
            expect(newChat(t).onPressed, isNotNull);
            expect(find.text('Selected member'), findsOneWidget);
            expect(reads, 3);
          } else {
            expect(reads, 2);
            expect(newChat(t).onPressed, isNotNull);
            expect(find.text('Selected member'), findsOneWidget);
          }
          expect(creates, cancel ? 0 : 1);
          expect(chatReads, 0);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/users/search')) {
            return p.json({
              'users': [person],
            });
          }
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            creates++;
            return p.json({'message': 'Synthetic unknown outcome'}, 503);
          }
          if (r.url.path.endsWith('/conversations')) {
            reads++;
            scopes.add(r.url.queryParameters['archived']);
            if (creates == 0) {
              return p.json({
                'data': mode == 'cached inbox' ? [receipt.conversation()] : [],
              });
            }
            if (badRead && reads == 2) {
              return mode == 'malformed inbox'
                  ? p.json({
                      'data': [
                        {'public_id': ''},
                      ],
                    })
                  : p.json({'message': 'Synthetic read unavailable'}, 503);
            }
            if (badRead) return retry.future;
            return p.json({
              'data': [receipt.conversation()],
            });
          }
          if (r.url.path.endsWith('/messages')) chatReads++;
          return p.json({'data': [], 'has_more': false});
        },
      );
    });
  }
}

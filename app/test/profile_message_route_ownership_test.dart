// Synthetic profile Message route ownership only. No live creation or read.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;
import 'profile_chat_receipt_test.dart' as receipt;
import 'profile_menu_ownership_test.dart' as m;

VoidCallback message(WidgetTester t) => t
    .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, t_('Message')))
    .onPressed!;
void main() {
  visualCases();
  testWidgets('covered profile cannot start a retained Message request', (
    t,
  ) async {
    var creates = 0;
    await p.fixture(
      t,
      (s) => UserProfilePage(session: s, username: 'asha'),
      () async {
        final old = message(t);
        await m.cover(t);
        old();
        await p.flush(t);
        expect(creates, 0);
        expect(find.text('Keep this route'), findsOneWidget);
        expect(find.byType(ChatPage), findsNothing);
      },
      respond: (r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
          creates++;
          return p.json({'conversation': receipt.conversation()});
        }
        return r.url.path.endsWith('/users/asha')
            ? p.json({'user': p.person()})
            : p.json({'data': [], 'next_cursor': null});
      },
    );
  });
  for (final leaving in [false, true]) {
    testWidgets(
      'valid Message reply cannot navigate over ${leaving ? 'a departing profile' : 'a covering route'}',
      (t) async {
        final response = Completer<http.Response>();
        var creates = 0, chatReads = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            message(t)();
            await p.flush(t);
            if (leaving) {
              Navigator.of(t.element(find.byType(UserProfilePage))).pop();
            } else {
              await m.cover(t);
            }
            response.complete(p.json({'conversation': receipt.conversation()}));
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(ChatPage), findsNothing);
            expect(chatReads, 0);
            expect(creates, 1);
            expect(
              find.text(leaving ? 'Create fixture' : 'Keep this route'),
              findsOneWidget,
            );
            if (!leaving) {
              await t.pageBack();
              await p.flush(t);
              await t.pumpAndSettle();
              expect(
                find.text(
                  'The chat may already exist. Check Chats before starting it again.',
                ),
                findsOneWidget,
              );
              expect(
                t
                    .widget<OutlinedButton>(
                      find.widgetWithText(OutlinedButton, 'Message'),
                    )
                    .onPressed,
                isNull,
              );
              await t.tap(find.text('Try again'));
              await p.flush(t);
              expect(creates, 1);
              expect(message(t), isNotNull);
            }
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              creates++;
              return response.future;
            }
            if (r.method == 'GET' && r.url.path.contains('/conversations/')) {
              chatReads++;
            }
            return r.url.path.endsWith('/users/asha')
                ? p.json({'user': p.person()})
                : p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
}

void visualCases() {
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
  for (final language in ['en', 'ne']) {
    testWidgets(
      'covered Message recovery and explicit read retry fit narrow large text $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final response = Completer<http.Response>();
        var creates = 0, chatReads = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            message(t)();
            await p.flush(t);
            await m.cover(t);
            response.complete(p.json({'conversation': receipt.conversation()}));
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Keep this route'), findsOneWidget);
            await t.pageBack();
            await p.flush(t);
            await t.pumpAndSettle();
            expect(
              find.text(
                t_(
                  'The chat may already exist. Check Chats before starting it again.',
                ),
              ),
              findsOneWidget,
            );
            expect(creates, 1);
            expect(chatReads, 0);
            await p.shot(t, 'profile_message_covered_recovery_$language');
            final button = find.widgetWithText(OutlinedButton, t_('Message'));
            await t.ensureVisible(button);
            await p.flush(t);
            expect(t.widget<OutlinedButton>(button).onPressed, isNull);
            await p.shot(t, 'profile_message_covered_actions_$language');
            await t.ensureVisible(find.text(t_('Try again')));
            await p.flush(t);
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(creates, 1);
            expect(chatReads, 0);
            expect(message(t), isNotNull);
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: language == 'en' ? Brightness.light : Brightness.dark,
          scale: 1.8,
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              creates++;
              return response.future;
            }
            if (r.method == 'GET' && r.url.path.contains('/conversations/')) {
              chatReads++;
            }
            return r.url.path.endsWith('/users/asha')
                ? p.json({'user': p.person()})
                : p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
}

// Actual editor/chat routes, synthetic requests only. No live publication/save/send.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/draft_exit_guard.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'chat_exit_continuity_test.dart' as chat;
import 'profile_journey_test.dart' as p;

Future<void> shot(WidgetTester t, String name, {String key = 'review'}) async {
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(ValueKey(key)),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive: true);
    File('test/renders/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

VoidCallback choice(WidgetTester t, String label) =>
    t.widget<TextButton>(find.widgetWithText(TextButton, t_(label))).onPressed!;
Future<void> cover(WidgetTester t) async {
  Navigator.of(t.element(find.byType(AlertDialog))).push(
    MaterialPageRoute<bool>(
      builder: (_) => const Scaffold(body: Text('Keep connected cover')),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
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
  for (final kind in ['group', 'profile', 'creator', 'chat']) {
    for (final keep in [true, false]) {
      testWidgets(
        'actual $kind covered ${keep ? 'Keep' : 'Discard'} stays owned and needs a fresh choice',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final language = kind == 'profile' || kind == 'chat' ? 'ne' : 'en';
          final brightness = language == 'ne'
              ? Brightness.dark
              : Brightness.light;
          final isChat = kind == 'chat',
              keepLabel = isChat ? 'Stay here' : 'Keep editing',
              leaveLabel = isChat ? 'Leave' : 'Discard';
          var writes = 0;
          Future<void> check() async {
            await t.pumpAndSettle();
            final nav = Navigator.of(t.element(find.byType(DraftExitGuard)));
            await nav.maybePop();
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            final old = choice(t, keep ? keepLabel : leaveLabel);
            if (keep) {
              await shot(
                t,
                'draft_exit_${kind}_dialog_$language',
                key: isChat ? 'exit-shot' : 'review',
              );
            }
            await cover(t);
            old();
            await t.pumpAndSettle();
            expect(find.text('Keep connected cover'), findsOneWidget);
            nav.pop();
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            choice(t, keep ? keepLabel : leaveLabel)();
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            if (keep) {
              expect(find.byType(DraftExitGuard), findsOneWidget);
              expect(
                find.text(
                  kind == 'group'
                      ? 'Guarded group plan'
                      : 'Guarded $kind draft',
                ),
                findsOneWidget,
              );
              if (kind == 'group') {
                expect(find.byType(InputChip), findsOneWidget);
              }
              await shot(
                t,
                'draft_exit_${kind}_kept_$language',
                key: isChat ? 'exit-shot' : 'review',
              );
            } else {
              expect(find.byType(DraftExitGuard), findsNothing);
              expect(
                find.text(isChat ? 'Conversation list' : 'Create fixture'),
                findsOneWidget,
              );
            }
            expect(writes, 0);
            expect(t.takeException(), isNull);
          }

          if (isChat) {
            prefs.lang = language;
            addTearDown(() => prefs.lang = 'en');
            final s = chat.ExitSession();
            await chat.open(t, s, brightness: brightness, scale: 1.8);
            await t.enterText(find.byType(TextField), 'Guarded chat draft');
            await p.flush(t);
            await check();
            expect(s.sends, 0);
          } else {
            await p.fixture(
              t,
              (s) => switch (kind) {
                'group' => NewChatPage(session: s),
                'profile' => EditProfilePage(session: s),
                _ => ComposePage(session: s),
              },
              () async {
                if (kind == 'group') {
                  await t.tap(find.byTooltip(t_('New group')));
                  await p.flush(t);
                  await t.enterText(
                    find.byType(TextField).first,
                    'Guarded group plan',
                  );
                  await t.enterText(find.byType(TextField).last, 'asha');
                  await p.flush(t);
                  await t.tap(find.text('Asha Gurung'));
                  await p.flush(t);
                } else if (kind == 'profile') {
                  await t.enterText(
                    find.byType(TextFormField).first,
                    'Guarded profile draft',
                  );
                  await p.flush(t);
                } else {
                  await t.enterText(
                    find.byType(TextField),
                    'Guarded creator draft',
                  );
                  await p.flush(t);
                }
                await check();
              },
              language: language,
              brightness: brightness,
              scale: 1.8,
              respond: (r) async {
                if (r.method != 'GET') writes++;
                expect(
                  r.method,
                  'GET',
                  reason: 'No create/update/publish from leaving a local draft',
                );
                return p.json({
                  'users': [
                    {
                      'public_id': 'asha',
                      'username': 'asha',
                      'name': 'Asha Gurung',
                    },
                  ],
                  'data': [],
                });
              },
            );
          }
        },
      );
    }
  }
  for (final covered in [false, true]) {
    testWidgets(
      'actual profile retirement clears its ${covered ? 'covered' : 'current'} draft prompt only',
      (t) async {
        late Session owner;
        var writes = 0;
        await p.fixture(
          t,
          (s) {
            owner = s;
            return EditProfilePage(session: s);
          },
          () async {
            await t.enterText(
              find.byType(TextFormField).first,
              'Guarded retired draft',
            );
            await p.flush(t);
            final nav = Navigator.of(t.element(find.byType(EditProfilePage)));
            await nav.maybePop();
            await t.pumpAndSettle();
            final old = choice(t, 'Discard');
            if (covered) await cover(t);
            owner.user = {
              'public_id': 'replacement',
              'username': 'replacement',
            };
            owner.notifyListeners();
            await t.pumpAndSettle();
            old();
            await t.pumpAndSettle();
            if (covered) {
              expect(find.text('Keep connected cover'), findsOneWidget);
              nav.pop();
              await t.pumpAndSettle();
            }
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.text('Guarded retired draft'), findsNothing);
            expect(find.byType(DraftExitGuard), findsNothing);
            expect(writes, 0);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method != 'GET') writes++;
            return p.json({});
          },
        );
      },
    );
  }
}

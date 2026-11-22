// Local synthetic report review. No live report or moderation action.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sanjaal/report_submission_store.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/actions.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/ui.dart';

import 'profile_journey_test.dart' as p;

void main() {
  setUpAll(() async {
    for (final f in [
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
      await (FontLoader(f.$1)..addFont(
            Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final replay in [false, true]) {
    for (final lang in ['en', 'ne']) {
      for (final dark in [false, true]) {
        testWidgets(
          'review explicit target and reason before send $lang dark=$dark replay=$replay',
          (t) async {
            t.view.physicalSize = const Size(320, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            var writes = 0;
            FlutterSecureStorage.setMockInitialValues({});
            if (replay) {
              await const ReportSubmissionStore().prepare(
                'me',
                'post',
                '11111111-1111-4111-8111-111111111111',
                'spam',
              );
            }
            await p.fixture(
              t,
              (s) {
                s.reportReplayEnabled = replay;
                s.reportHistoryEnabled = replay;
                return Builder(
                  builder: (c) => Scaffold(
                    body: TextButton(
                      onPressed: () => reportFlow(
                        c,
                        s,
                        'post',
                        '11111111-1111-4111-8111-111111111111',
                        targetLabel:
                            '@asha\nCommunity music and weekend walks.',
                      ),
                      child: const Text('Open fixture'),
                    ),
                  ),
                );
              },
              () async {
                await t.tap(find.text('Open fixture'));
                await p.flush(t);
                await t.tap(find.text(t_('Spam')));
                await p.flush(t);
                await t.pumpAndSettle();
                expect(writes, 0);
                expect(find.text(t_('Review report')), findsOneWidget);
                expect(
                  find.text('@asha\nCommunity music and weekend walks.'),
                  findsOneWidget,
                );
                expect(
                  find.text('11111111-1111-4111-8111-111111111111'),
                  findsNothing,
                );
                await t.tap(find.text(t_('Reference')));
                await t.pumpAndSettle();
                expect(
                  find.text('11111111-1111-4111-8111-111111111111'),
                  findsOneWidget,
                );
                await t.tap(find.text(t_('Reference')));
                await t.pumpAndSettle();
                expect(find.text(t_('Spam')), findsOneWidget);
                expect(t.takeException(), isNull);
                await p.shot(
                  t,
                  'report_review_${lang}_${dark ? 'dark' : 'light'}${replay ? '_replay' : ''}',
                );
                await t.drag(
                  find.byType(SingleChildScrollView).last,
                  const Offset(0, -400),
                );
                await t.pumpAndSettle();
                expect(
                  find
                      .text(
                        t_(
                          replay
                              ? 'Retry the same report?'
                              : 'Send this report?',
                        ),
                      )
                      .hitTestable(),
                  findsOneWidget,
                );
                expect(t.takeException(), isNull);
                await t.tap(find.text(t_('Send report')));
                await p.flush(t);
                expect(writes, 1);
                expect(
                  find.text(
                    t_(replay ? 'Report received' : 'Report submitted.'),
                  ),
                  findsOneWidget,
                );
                expect(t.takeException(), isNull);
              },
              language: lang,
              scale: 1.8,
              brightness: dark ? Brightness.dark : Brightness.light,
              respond: (r) async {
                writes++;
                expect(
                  r.body,
                  contains('11111111-1111-4111-8111-111111111111'),
                );
                return replay
                    ? p.json({
                        'report': {
                          'public_id': '22222222-2222-4222-8222-222222222222',
                          'type': 'post',
                          'target': '11111111-1111-4111-8111-111111111111',
                          'reason': 'spam',
                          'note': null,
                          'status': 'received',
                          'created_at': null,
                          'updated_at': null,
                        },
                        'replayed': true,
                      })
                    : p.json({});
              },
            );
          },
        );
      }
    }
  }
  for (final exit in ['cancel', 'back', 'same login', 'covered']) {
    testWidgets('review $exit cannot submit retained callback', (t) async {
      var writes = 0;
      late Session session;
      await p.fixture(
        t,
        (s) {
          session = s;
          return Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => reportFlow(c, s, 'user', 'asha'),
                child: const Text('Open fixture'),
              ),
            ),
          );
        },
        () async {
          await t.tap(find.text('Open fixture'));
          await p.flush(t);
          await t.tap(find.text('Spam'));
          await p.flush(t);
          final old = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send report'),
              )
              .onPressed!;
          if (exit == 'cancel') {
            await t.tap(find.text('Cancel'));
          } else if (exit == 'back') {
            Navigator.of(t.element(find.byType(AlertDialog))).pop();
          } else if (exit.endsWith('login')) {
            await session.login('fixture', 'not-a-password');
          } else {
            Navigator.of(t.element(find.byType(AlertDialog))).push(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Keep cover')),
              ),
            );
          }
          await p.flush(t);
          old();
          await p.flush(t);
          expect(writes, 0);
          if (exit == 'covered') {
            expect(find.text('Keep cover'), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
        respond: (_) async {
          writes++;
          return p.json({});
        },
      );
    });
  }
  testWidgets('double send callback writes once', (t) async {
    var writes = 0;
    await p.fixture(
      t,
      (s) => Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => reportFlow(c, s, 'comment', 'comment-fixture'),
            child: const Text('Open fixture'),
          ),
        ),
      ),
      () async {
        await t.tap(find.text('Open fixture'));
        await p.flush(t);
        await t.tap(find.text('Spam'));
        await p.flush(t);
        final send = t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send report'),
            )
            .onPressed!;
        send();
        send();
        await p.flush(t);
        expect(writes, 1);
        expect(t.takeException(), isNull);
      },
      respond: (_) async {
        writes++;
        return p.json({});
      },
    );
  });
}

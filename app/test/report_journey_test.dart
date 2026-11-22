// Offline report submission/history fixtures. No live report or moderation action.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/actions.dart';
import 'package:sanjaal/reports_page.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;

const receiptId = '11111111-1111-4111-8111-111111111111';
const otherId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> report({
  String id = receiptId,
  String status = 'received',
}) => {
  'public_id': id,
  'type': 'post',
  'target': 'original-post',
  'reason': 'spam',
  'note': null,
  'status': status,
  'created_at': '2026-11-22T10:00:00Z',
  'updated_at': '2026-11-22T11:00:00Z',
};
Map<String, dynamic> details({
  String id = receiptId,
  String status = 'received',
}) => {
  'report': report(id: id, status: status),
  'events': [
    {'status': 'received', 'created_at': '2026-11-22T10:00:00Z'},
    if (status != 'received')
      {'status': 'in_review', 'created_at': '2026-11-22T10:30:00Z'},
    if (status == 'closed')
      {'status': 'closed', 'created_at': '2026-11-22T11:00:00Z'},
  ],
};
void main() {
  receiptVisualTests();
  normalReportVisualTests();
  followThroughTests();
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
  tearDown(() => prefs.lang = 'en');
  testWidgets(
    'report reason to persisted receipt to status detail is connected',
    (t) async {
      var writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        reportFlow(context, s, 'post', 'original-post'),
                    child: const Text('Report fixture'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Report fixture'));
          await t.pumpAndSettle();
          await t.tap(find.text('Spam'));
          await t.pumpAndSettle();
          await t.tap(find.text('Send report'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Report received'), findsOneWidget);
          expect(writes, 1);
          await t.tap(find.text('View report'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(ReportDetailPage), findsOneWidget);
          expect(find.text('Original report'), findsOneWidget);
          expect(find.text('original-post'), findsOneWidget);
          expect(find.text('Received'), findsNWidgets(2));
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'POST') {
            writes++;
            return h.json({'report': report()}, 201);
          }
          return h.json(details());
        },
      );
    },
  );
  testWidgets(
    'settings history opens the original receipt and refreshes its progress',
    (t) async {
      var detailReads = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'reports');
          await t.pump();
          await t.tap(find.widgetWithText(ListTile, 'Your reports'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Post · Received'), findsOneWidget);
          await t.tap(find.text('Post · Received'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Received'), findsNWidgets(2));
          final refresh = t
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh;
          await refresh();
          await t.pump();
          expect(find.text('Review closed'), findsNWidgets(2));
          expect(find.text('In review'), findsOneWidget);
          expect(detailReads, 2);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(find.text('Post · Review closed'), findsOneWidget);
          expect(detailReads, 2);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/reports')) {
            return h.json({
              'data': [report()],
              'next_cursor': null,
            });
          }
          return h.json(
            details(status: ++detailReads == 1 ? 'received' : 'closed'),
          );
        },
      );
    },
  );
  testWidgets('initial history failure retries and empty is not loading', (
    t,
  ) async {
    var reads = 0;
    await h.fixture(
      t,
      (s, c) async {
        s.reportHistoryEnabled = true;
        await t.pumpWidget(MaterialApp(home: ReportsPage(session: s)));
        await h.flush(t);
        expect(
          find.text('Reports could not be loaded. Try again.'),
          findsOneWidget,
        );
        await t.tap(find.text('Try again'));
        await h.flush(t);
        expect(find.textContaining('No reports yet.'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(t.takeException(), isNull);
      },
      respond: (_) async => ++reads == 1
          ? h.json({}, 503)
          : h.json({'data': [], 'next_cursor': null}),
    );
  });
  testWidgets(
    'failed next page keeps receipts and retries the same cursor once',
    (t) async {
      var pages = 0;
      final cursors = <String?>[];
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          await t.pumpWidget(MaterialApp(home: ReportsPage(session: s)));
          await h.flush(t);
          await t.tap(find.text('Load more'));
          await h.flush(t);
          expect(find.text('Post · Received'), findsOneWidget);
          await t.tap(find.text('Try again'));
          await h.flush(t);
          expect(find.text('Post · Received'), findsNWidgets(2));
          expect(cursors, [null, receiptId, receiptId]);
          expect(find.text('Load more'), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          cursors.add(r.url.queryParameters['cursor']);
          pages++;
          return pages == 1
              ? h.json({
                  'data': [report()],
                  'next_cursor': receiptId,
                })
              : pages == 2
              ? h.json({}, 503)
              : h.json({
                  'data': [report(id: otherId)],
                  'next_cursor': null,
                });
        },
      );
    },
  );
  testWidgets('legacy server hides history and manual entry makes no request', (
    t,
  ) async {
    var reads = 0;
    await h.fixture(
      t,
      (s, c) async {
        expect(s.reportHistoryEnabled, isFalse);
        await t.pumpWidget(MaterialApp(home: ReportsPage(session: s)));
        await h.flush(t);
        expect(
          find.text('Report history is not available on this server yet.'),
          findsOneWidget,
        );
        expect(reads, 0);
        expect(t.takeException(), isNull);
      },
      respond: (_) async {
        reads++;
        return h.json({});
      },
    );
  });
  for (final detail in [false, true]) {
    testWidgets(
      'late report ${detail ? 'detail' : 'list'} response cannot cross same-member login',
      (t) async {
        final answer = Completer<void>();
        await h.fixture(
          t,
          (s, c) async {
            s.reportHistoryEnabled = true;
            await t.pumpWidget(
              MaterialApp(
                home: detail
                    ? ReportDetailPage(session: s, receiptId: receiptId)
                    : ReportsPage(session: s),
              ),
            );
            await h.flush(t);
            await s.login('fixture', 'not-a-password');
            await h.flush(t);
            answer.complete();
            await h.flush(t);
            expect(find.text('original-post'), findsNothing);
            expect(find.text('Post · Received'), findsNothing);
            expect(
              find.textContaining('another signed-in session'),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            await answer.future;
            return h.json(
              detail
                  ? details()
                  : {
                      'data': [report()],
                      'next_cursor': null,
                    },
            );
          },
        );
      },
    );
  }
  for (final bad in [
    <String, dynamic>{'status': 'invented'},
    <String, dynamic>{'public_id': 'bad'},
    <String, dynamic>{'type': 'secret'},
  ]) {
    testWidgets('invalid history receipt is rejected $bad', (t) async {
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          await t.pumpWidget(MaterialApp(home: ReportsPage(session: s)));
          await h.flush(t);
          expect(
            find.text('Reports could not be loaded. Try again.'),
            findsOneWidget,
          );
          expect(find.text('Post · Received'), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (_) async => h.json({
          'data': [
            {...report(), ...bad},
          ],
          'next_cursor': null,
        }),
      );
    });
  }
  for (final language in ['en', 'ne']) {
    for (final scenario in ['empty', 'history', 'detail', 'error']) {
      testWidgets('report $scenario narrow large text $language', (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await p.fixture(
          t,
          (s) {
            s.reportHistoryEnabled = true;
            return scenario == 'detail'
                ? ReportDetailPage(session: s, receiptId: receiptId)
                : ReportsPage(session: s);
          },
          () async {
            await h.flush(t);
            expect(t.takeException(), isNull);
            await p.shot(t, 'reports_${scenario}_$language');
            if (scenario == 'detail') {
              await t.drag(find.byType(ListView), const Offset(0, -700));
              await t.pumpAndSettle();
              await p.shot(t, 'reports_timeline_$language');
            }
          },
          language: language,
          scale: 1.8,
          brightness: language == 'en' ? Brightness.light : Brightness.dark,
          respond: (_) async => scenario == 'error'
              ? p.json({}, 503)
              : p.json(
                  scenario == 'detail'
                      ? details(status: 'closed')
                      : {
                          'data': scenario == 'empty'
                              ? []
                              : [report(status: 'in_review')],
                          'next_cursor': null,
                        },
                ),
        );
      });
    }
  }
}

void followThroughTests() {
  for (final malformed in [false, true]) {
    testWidgets(
      'uncertain report opens safe history readback malformed=$malformed',
      (t) async {
        var writes = 0;
        await h.fixture(
          t,
          (s, c) async {
            s.reportHistoryEnabled = true;
            await t.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () =>
                          reportFlow(context, s, 'post', 'original-post'),
                      child: const Text('Report fixture'),
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.text('Report fixture'));
            await t.pumpAndSettle();
            await t.tap(find.text('Spam'));
            await t.pumpAndSettle();
            await t.tap(find.text('Send report'));
            await h.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Report received'), findsNothing);
            expect(
              find.text(
                'Report result unconfirmed. Check Your reports before submitting again.',
              ),
              findsOneWidget,
            );
            await t.tap(find.text('Your reports'));
            await h.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(ReportsPage), findsOneWidget);
            expect(find.text('Post · Received'), findsOneWidget);
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST') {
              writes++;
              return malformed
                  ? h.json({
                      'report': report(id: otherId)
                        ..['target'] = 'another-post',
                    }, 201)
                  : h.json({}, 503);
            }
            return h.json({
              'data': [report()],
              'next_cursor': null,
            });
          },
        );
      },
    );
  }
  testWidgets('stale reason choice cannot dismiss the later receipt dialog', (
    t,
  ) async {
    var writes = 0;
    await h.fixture(
      t,
      (s, c) async {
        s.reportHistoryEnabled = true;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      reportFlow(context, s, 'post', 'original-post'),
                  child: const Text('Report fixture'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Report fixture'));
        await t.pumpAndSettle();
        final choose = t
            .widget<SimpleDialogOption>(
              find.widgetWithText(SimpleDialogOption, 'Spam'),
            )
            .onPressed!;
        choose();
        await h.flush(t);
        await t.pumpAndSettle();
        choose();
        await t.pump();
        expect(writes, 0);
        await t.tap(find.text('Send report'));
        await h.flush(t);
        await t.pumpAndSettle();
        expect(find.text('Report received'), findsOneWidget);
        expect(writes, 1);
        await t.tap(find.text('Done'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
      respond: (_) async {
        writes++;
        return h.json({'report': report()}, 201);
      },
    );
  });
  testWidgets('unknown legacy report time is not replaced by current time', (
    t,
  ) async {
    await h.fixture(
      t,
      (s, c) async {
        s.reportHistoryEnabled = true;
        await t.pumpWidget(MaterialApp(home: ReportsPage(session: s)));
        await h.flush(t);
        expect(find.textContaining(t_('Time unavailable')), findsOneWidget);
        expect(t.takeException(), isNull);
      },
      respond: (_) async => h.json({
        'data': [
          {...report(), 'created_at': null, 'updated_at': null},
        ],
        'next_cursor': null,
      }),
    );
  });
}

void receiptVisualTests() {
  for (final language in ['en', 'ne']) {
    testWidgets('report receipt confirmation narrow large text $language', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await p.fixture(
        t,
        (s) {
          s.reportHistoryEnabled = true;
          return Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    reportFlow(context, s, 'post', 'original-post'),
                child: const Text('Report fixture'),
              ),
            ),
          );
        },
        () async {
          await t.tap(find.text('Report fixture'));
          await t.pumpAndSettle();
          await t.tap(find.text(t_('Spam')));
          await t.pumpAndSettle();
          await t.tap(find.text(t_('Send report')));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.text(t_('Report received')), findsOneWidget);
          expect(t.takeException(), isNull);
          await p.shot(t, 'reports_receipt_$language');
          await t.tap(find.text(t_('Done')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
        language: language,
        scale: 1.8,
        brightness: language == 'en' ? Brightness.light : Brightness.dark,
        respond: (_) async => p.json({'report': report()}, 201),
      );
    });
  }
}

void normalReportVisualTests() {
  for (final language in ['en', 'ne']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final detail in [false, true]) {
        final name =
            'reports_normal_${detail ? 'detail' : 'history'}_${language}_${brightness.name}';
        testWidgets(name, (t) async {
          t.view.physicalSize = const Size(390, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await p.fixture(
            t,
            (s) {
              s.reportHistoryEnabled = true;
              return detail
                  ? ReportDetailPage(session: s, receiptId: receiptId)
                  : ReportsPage(session: s);
            },
            () async {
              await h.flush(t);
              expect(t.takeException(), isNull);
              await p.shot(t, name);
            },
            language: language,
            scale: 1,
            brightness: brightness,
            respond: (_) async => p.json(
              detail
                  ? details(status: 'closed')
                  : {
                      'data': [
                        report(status: 'in_review'),
                        {
                          ...report(id: otherId),
                          'type': 'user',
                          'target': 'original-member',
                          'reason': 'abuse',
                        },
                      ],
                      'next_cursor': null,
                    },
            ),
          );
        });
      }
    }
  }
}

// Device-local storage mock and synthetic HTTP only. No live reports.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/pending_reports_page.dart';
import 'package:sanjaal/reports_page.dart';
import 'package:sanjaal/report_submission_store.dart';
import 'package:sanjaal/ui.dart';

import 'profile_journey_test.dart' as p;
import 'report_journey_test.dart' as r;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
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
  for (final lang in ['en', 'ne']) {
    for (final dark in [false, true]) {
      testWidgets(
        'pending list readable and explicit recovery $lang dark=$dark',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final key = await const ReportSubmissionStore().prepare(
            'me',
            'post',
            'original-post',
            'spam',
          );
          var writes = 0;
          await p.fixture(
            t,
            (s) {
              s.reportHistoryEnabled = true;
              s.reportReplayEnabled = true;
              return PendingReportsPage(session: s);
            },
            () async {
              await t.pumpAndSettle();
              expect(writes, 0);
              expect(find.text('original-post'), findsOneWidget);
              expect(t.takeException(), isNull);
              await p.shot(
                t,
                'pending_reports_${lang}_${dark ? 'dark' : 'light'}',
              );
              await t.tap(find.text('original-post'));
              await p.flush(t);
              expect(find.text(t_('Review report')), findsOneWidget);
              expect(writes, 0);
              await t.tap(find.text(t_('Cancel')));
              await p.flush(t);
              expect(writes, 0);
              expect(find.text('original-post'), findsOneWidget);
              await t.tap(find.text('original-post'));
              await p.flush(t);
              await t.tap(find.text(t_('Send report')));
              await p.flush(t);
              expect(writes, 1);
              expect(find.text(t_('Report received')), findsOneWidget);
              await t.tap(find.text(t_('Done')));
              await p.flush(t);
              expect(
                find.text(t_('No unconfirmed reports on this device.')),
                findsOneWidget,
              );
              expect(t.takeException(), isNull);
            },
            language: lang,
            scale: 1.8,
            brightness: dark ? Brightness.dark : Brightness.light,
            respond: (req) async {
              writes++;
              expect(req.body, contains(key));
              return p.json({'report': r.report(), 'replayed': true});
            },
          );
        },
      );
    }
  }
  for (final lang in ['en', 'ne']) {
    for (final dark in [false, true]) {
      testWidgets('unreadable attempts fail closed then recover $lang $dark', (
        t,
      ) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await const ReportSubmissionStore().prepare(
          'me',
          'user',
          'asha',
          'spam',
        );
        const storage = FlutterSecureStorage();
        final saved = Map<String, String>.from(await storage.readAll());
        final storageKey = saved.keys.single;
        await storage.write(key: storageKey, value: 'broken local fixture');
        await p.fixture(
          t,
          (s) {
            s.reportHistoryEnabled = true;
            s.reportReplayEnabled = true;
            return PendingReportsPage(session: s);
          },
          () async {
            await t.pumpAndSettle();
            expect(
              find.text(
                t_(
                  'Unconfirmed reports could not be read. Nothing was changed.',
                ),
              ),
              findsOneWidget,
            );
            expect(find.text('@asha'), findsNothing);
            expect(await storage.read(key: storageKey), 'broken local fixture');
            expect(t.takeException(), isNull);
            await p.shot(
              t,
              'pending_reports_error_${lang}_${dark ? 'dark' : 'light'}',
            );
            await storage.write(key: storageKey, value: saved[storageKey]!);
            await t.ensureVisible(find.text(t_('Try again')));
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(find.text('@asha'), findsOneWidget);
            expect(
              find.text(
                t_(
                  'Unconfirmed reports could not be read. Nothing was changed.',
                ),
              ),
              findsNothing,
            );
            expect(t.takeException(), isNull);
          },
          language: lang,
          scale: 1.8,
          brightness: dark ? Brightness.dark : Brightness.light,
          respond: (_) async =>
              throw StateError('Local recovery must not call API'),
        );
      });
    }
  }
  testWidgets('history entry opens local attempts with no report write', (
    t,
  ) async {
    var writes = 0;
    await const ReportSubmissionStore().prepare('me', 'user', 'asha', 'spam');
    await p.fixture(
      t,
      (s) {
        s.reportHistoryEnabled = true;
        s.reportReplayEnabled = true;
        return ReportsPage(session: s);
      },
      () async {
        await p.flush(t);
        await t.tap(find.text('Unconfirmed reports'));
        await p.flush(t);
        expect(find.byType(PendingReportsPage), findsOneWidget);
        expect(find.text('@asha'), findsOneWidget);
        expect(writes, 0);
      },
      respond: (req) async {
        if (req.method != 'GET') writes++;
        return p.json({'data': [], 'next_cursor': null});
      },
    );
  });
  testWidgets(
    'local pending view retires on same login and never leaks another account',
    (t) async {
      late Session session;
      await const ReportSubmissionStore().prepare('me', 'user', 'asha', 'spam');
      await p.fixture(
        t,
        (s) {
          session = s;
          s.reportHistoryEnabled = true;
          s.reportReplayEnabled = true;
          return PendingReportsPage(session: s);
        },
        () async {
          await p.flush(t);
          expect(find.text('@asha'), findsOneWidget);
          await session.login('fixture', 'not-a-password');
          await p.flush(t);
          expect(find.text('@asha'), findsNothing);
          expect(
            find.textContaining('another signed-in session'),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        },
        respond: (_) async =>
            throw StateError('Local pending page must not call report API'),
      );
    },
  );
}

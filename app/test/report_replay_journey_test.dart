// Synthetic HTTP + secure-storage mock, no real report or account.
import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/actions.dart';
import 'package:sanjaal/report_submission_store.dart';

import 'upload_center_test.dart' as h;
import 'report_journey_test.dart' as r;

class DelayedReportStorage extends TestFlutterSecureStoragePlatform {
  DelayedReportStorage() : super({});
  final written = Completer<void>();
  final release = Completer<void>();
  bool loseWrite = false;
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key.startsWith('report_submissions_v1_')) {
      if (!written.isCompleted) written.complete();
      await release.future;
      if (loseWrite) return;
    }
    await super.write(key: key, value: value, options: options);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'member-bound retry never downgrades to mutable handle on older server',
    (t) async {
      const ref = '11111111-1111-4111-8111-111111111111';
      var writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          s.reportReplayEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => reportFlow(
                      context,
                      s,
                      'user',
                      'asha',
                      initialReason: 'spam',
                      memberRef: ref,
                    ),
                    child: const Text('Open fixture'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Open fixture'));
          await h.flush(t);
          expect(writes, 0);
          expect(find.text('Send report'), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (_) async {
          writes++;
          return h.json({});
        },
      );
    },
  );
  for (final matching in [false, true]) {
    testWidgets(
      'member reference binds request and receipt matching=$matching',
      (t) async {
        const ref = '11111111-1111-4111-8111-111111111111';
        var writes = 0;
        await h.fixture(
          t,
          (s, c) async {
            s.reportHistoryEnabled = true;
            s.reportReplayEnabled = true;
            s.reportMemberRefsEnabled = true;
            await t.pumpWidget(
              MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => reportFlow(
                        context,
                        s,
                        'user',
                        'asha',
                        memberRef: ref,
                        targetLabel: 'Asha',
                      ),
                      child: const Text('Open fixture'),
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.text('Open fixture'));
            await h.flush(t);
            await t.tap(find.text('Spam'));
            await h.flush(t);
            expect(writes, 0);
            await t.tap(find.text('Send report'));
            await h.flush(t);
            await t.pumpAndSettle();
            expect(writes, 1);
            expect(
              find.text('Report received'),
              matching ? findsOneWidget : findsNothing,
            );
            final pending = await const ReportSubmissionStore().find(
              'me',
              'user',
              'asha',
              'spam',
              memberRef: ref,
            );
            expect(pending, matching ? isNull : isNotNull);
            expect(t.takeException(), isNull);
          },
          respond: (req) async {
            writes++;
            expect((jsonDecode(req.body) as Map)['target_public_id'], ref);
            final receipt = r.report()
              ..addAll({
                'type': 'user',
                'target': 'asha',
                'target_public_id': matching
                    ? ref
                    : '22222222-2222-4222-8222-222222222222',
              });
            return h.json({'report': receipt, 'replayed': false});
          },
        );
      },
    );
  }
  testWidgets(
    'unconfirmed explicit retry restores same key and receipt then clears pending',
    (t) async {
      final keys = <String>[];
      var writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          s.reportHistoryEnabled = true;
          s.reportReplayEnabled = true;
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        reportFlow(context, s, 'post', 'original-post'),
                    child: const Text('Open fixture'),
                  ),
                ),
              ),
            ),
          );
          Future<void> open() async {
            await t.tap(find.text('Open fixture'));
            await h.flush(t);
            await t.tap(find.text('Spam'));
            await h.flush(t);
          }

          await open();
          expect(writes, 0);
          await t.tap(find.text('Send report'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(writes, 1);
          expect(
            await const ReportSubmissionStore().find(
              'me',
              'post',
              'original-post',
              'spam',
            ),
            keys.first,
          );
          await open();
          expect(find.text('Retry the same report?'), findsOneWidget);
          expect(writes, 1);
          await t.tap(find.text('Send report'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(keys, [keys.first, keys.first]);
          expect(find.text('Report received'), findsOneWidget);
          expect(
            await const ReportSubmissionStore().find(
              'me',
              'post',
              'original-post',
              'spam',
            ),
            isNull,
          );
          expect(t.takeException(), isNull);
        },
        respond: (req) async {
          writes++;
          keys.add((jsonDecode(req.body) as Map)['submission_id'] as String);
          return writes == 1
              ? h.json({}, 503)
              : h.json({
                  'report': r.report(status: 'closed'),
                  'replayed': true,
                });
        },
      );
    },
  );
  testWidgets('legacy server never adds unsupported submission key', (t) async {
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      reportFlow(context, s, 'post', 'original-post'),
                  child: const Text('Open fixture'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open fixture'));
        await h.flush(t);
        await t.tap(find.text('Spam'));
        await h.flush(t);
        await t.tap(find.text('Send report'));
        await h.flush(t);
        expect(find.text('Report submitted.'), findsOneWidget);
      },
      respond: (req) async {
        expect(jsonDecode(req.body), isNot(contains('submission_id')));
        return h.json({});
      },
    );
  });
  testWidgets('unreadable durable storage fails closed before a write', (
    t,
  ) async {
    var writes = 0;
    await h.fixture(
      t,
      (s, c) async {
        s.reportHistoryEnabled = true;
        s.reportReplayEnabled = true;
        final key =
            'report_submissions_v1_${sha256.convert(utf8.encode('me'))}';
        await const FlutterSecureStorage().write(key: key, value: 'not json');
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      reportFlow(context, s, 'post', 'original-post'),
                  child: const Text('Open fixture'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open fixture'));
        await h.flush(t);
        await t.tap(find.text('Spam'));
        await h.flush(t);
        expect(writes, 0);
        expect(
          find.text('Report retry could not be saved. Nothing was sent.'),
          findsOneWidget,
        );
        expect(await const FlutterSecureStorage().read(key: key), 'not json');
        expect(t.takeException(), isNull);
      },
      respond: (_) async {
        writes++;
        return h.json({});
      },
    );
  });
  for (final change in ['same login', 'other identity', 'write lost']) {
    testWidgets(
      'pending durable save $change never sends an unowned or unverified request',
      (t) async {
        var writes = 0;
        await h.fixture(
          t,
          (s, c) async {
            s.reportHistoryEnabled = true;
            s.reportReplayEnabled = true;
            final delayed = DelayedReportStorage();
            FlutterSecureStoragePlatform.instance = delayed;
            await t.pumpWidget(
              MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () =>
                          reportFlow(context, s, 'post', 'original-post'),
                      child: const Text('Open fixture'),
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.text('Open fixture'));
            await h.flush(t);
            await t.tap(find.text('Spam'));
            await h.flush(t);
            await t.tap(find.text('Send report'));
            await h.flush(t);
            expect(delayed.written.isCompleted, isTrue);
            expect(writes, 0);
            if (change == 'same login') {
              await s.login('fixture', 'not-a-password');
            } else if (change == 'other identity') {
              s.user = {'public_id': 'another', 'username': 'another'};
              s.notifyListeners();
            } else {
              delayed.loseWrite = true;
            }
            delayed.release.complete();
            await h.flush(t);
            expect(writes, 0);
            if (change == 'write lost') {
              expect(
                find.text('Report retry could not be saved. Nothing was sent.'),
                findsOneWidget,
              );
            } else {
              expect(
                await const ReportSubmissionStore().find(
                  'me',
                  'post',
                  'original-post',
                  'spam',
                ),
                isNotNull,
              );
            }
            expect(
              await const ReportSubmissionStore().find(
                'another',
                'post',
                'original-post',
                'spam',
              ),
              isNull,
            );
            expect(t.takeException(), isNull);
          },
          respond: (_) async {
            writes++;
            return h.json({});
          },
        );
      },
    );
  }
}

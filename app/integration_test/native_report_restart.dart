// Synthetic local API + real Keychain/Keystore. Never imported by product code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/actions.dart';
import 'package:sanjaal/pending_reports_page.dart';
import 'package:sanjaal/report_submission_store.dart';

Future<void> nativeReportRestartJourney(
  WidgetTester t,
  Session session, {
  required bool recover,
  required Future<void> Function(bool Function()) waitUntil,
  required Future<void> Function(String) capture,
}) async {
  const base = String.fromEnvironment('E2E_TOKEN_BASE');
  const token = String.fromEnvironment('E2E_TOKEN');
  final uri = Uri.parse(base);
  expect(['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host), isTrue);
  expect(uri.port, 8002);
  expect(
    session.reportReplayEnabled && session.reportMemberRefsEnabled,
    isTrue,
  );
  final owner = session.user!['public_id'] as String;
  const store = ReportSubmissionStore();
  final directory = await t.runAsync(getApplicationSupportDirectory);
  final identity = File('${directory!.path}/report-restart-identity.json');
  final headers = {'Authorization': 'Bearer $token'};
  final profile = await t.runAsync(
    () => session.call('GET', '/users/asha_e2e'),
  );
  final member = (profile as Map)['user'] as Map;
  final ref = member['public_id'] as String;
  if (!recover) {
    expect(await t.runAsync(() => store.pending(owner)), isEmpty);
    final armed = await t.runAsync(
      () =>
          http.post(Uri.parse('$base/e2e/report-fault-arm'), headers: headers),
    );
    expect(armed!.statusCode, 200);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => reportFlow(
                context,
                session,
                'user',
                'asha_e2e',
                memberRef: ref,
                targetLabel: 'Asha Gurung',
              ),
              child: const Text('Review synthetic report'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Review synthetic report'));
    await t.pumpAndSettle();
    await t.tap(find.text('Spam'));
    await t.pumpAndSettle();
    expect(await t.runAsync(() => store.pending(owner)), isEmpty);
    await capture('ios_report_review_before_send');
    await t.tap(find.text('Send report'));
    await waitUntil(
      () => find
          .text(
            'Report result unconfirmed. Check Your reports before submitting again.',
          )
          .evaluate()
          .isNotEmpty,
    );
    final rows = await t.runAsync(() => store.pending(owner));
    expect(rows, hasLength(1));
    expect(rows!.single['target_public_id'], ref);
    final history = await t.runAsync(() => session.call('GET', '/reports'));
    final receipts = (history as Map)['data'] as List;
    expect(receipts, hasLength(1));
    await t.runAsync(
      () => identity.writeAsString(
        jsonEncode({
          'owner': owner,
          'attempt': rows.single,
          'receipt': receipts.single['public_id'],
        }),
        flush: true,
      ),
    );
    await t.pumpWidget(MaterialApp(home: PendingReportsPage(session: session)));
    await waitUntil(() => find.text('@asha_e2e').evaluate().isNotEmpty);
    await capture('ios_report_reply_lost_pending');
    return;
  }
  final prior =
      jsonDecode(await t.runAsync(identity.readAsString) as String) as Map;
  expect(owner, prior['owner']);
  final restored = await t.runAsync(() => store.pending(owner));
  expect(restored, [prior['attempt']]);
  expect(
    await t.runAsync(() => store.pending('another-synthetic-owner')),
    isEmpty,
  );
  await t.pumpWidget(MaterialApp(home: PendingReportsPage(session: session)));
  await waitUntil(() => find.text('@asha_e2e').evaluate().isNotEmpty);
  await capture('ios_report_restart_restored');
  await t.tap(find.text('@asha_e2e'));
  await t.pumpAndSettle();
  expect(find.text('Retry the same report?'), findsOneWidget);
  await capture('ios_report_restart_explicit_review');
  await t.tap(find.text('Cancel'));
  await t.pumpAndSettle();
  expect(await t.runAsync(() => store.pending(owner)), restored);
  await t.tap(find.text('@asha_e2e'));
  await t.pumpAndSettle();
  await t.tap(find.text('Send report'));
  await waitUntil(() => find.text('Report received').evaluate().isNotEmpty);
  expect(await t.runAsync(() => store.pending(owner)), isEmpty);
  await t.tap(find.text('Done'));
  await t.pumpAndSettle();
  expect(find.text('No unconfirmed reports on this device.'), findsOneWidget);
  final history = await t.runAsync(() => session.call('GET', '/reports'));
  expect(
    ((history as Map)['data'] as List).single['public_id'],
    prior['receipt'],
  );
  await capture('ios_report_restart_same_receipt');
  await t.runAsync(identity.delete);
}

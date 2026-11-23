// Next combined native batch only. Real secure storage, disposable local API.
// Never imported by the shipped runtime; this helper never sends a message.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/chat_text_draft_store.dart';
import 'package:sanjaal/main.dart' show buildTheme;

import 'native_text_input.dart';

Future<void> nativeChatTextRestartJourney(
  WidgetTester t,
  Session session, {
  required bool recover,
  Map<String, dynamic>? conversation,
  required Future<void> Function(bool Function()) waitUntil,
  required Future<void> Function(String) capture,
  required Future<void> Function(String) stage,
}) async {
  final base = Uri.parse(const String.fromEnvironment('E2E_TOKEN_BASE'));
  expect(['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host), isTrue);
  expect(base.port, 8002);
  expect(Uri.parse(apiBase).origin, base.origin);
  expect(Uri.parse(apiBase).path, '/api/v1');
  final owner = session.user!['public_id'] as String;
  const store = ChatTextDraftStore();
  final support = await t.runAsync(getApplicationSupportDirectory);
  final identity = File('${support!.path}/chat-text-restart-identity.json');
  const text = 'Native process-restart saved chat text';
  Map? prior;
  if (recover) {
    prior =
        jsonDecode(await t.runAsync(identity.readAsString) as String) as Map;
    expect(prior['owner'], owner);
    conversation = (prior['conversation'] as Map).cast<String, dynamic>();
  }
  expect(conversation, isNotNull);
  final convo = conversation!;
  final id = convo['public_id'] as String;
  Future<List> messages() async {
    final reply = await t.runAsync(
      () => session.call('GET', '/conversations/$id/messages'),
    );
    return (reply as Map)['data'] as List;
  }

  final before = await messages();
  if (recover) {
    expect(before, prior!['messages']);
    expect(
      (await t.runAsync(() => store.read(owner, id)))!.toJson(),
      prior['saved'],
    );
    expect(
      await t.runAsync(() => store.read('another-synthetic-owner', id)),
      isNull,
    );
  } else {
    expect(await t.runAsync(() => store.read(owner, id)), isNull);
  }
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChatPage(session: session, convo: convo),
    ),
  );
  await waitUntil(
    () =>
        find.byType(TextField).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  final field = find.byType(TextField);
  expect(t.widget<TextField>(field).controller!.text, isEmpty);
  if (!recover) {
    await confirmedNativeTextInput(
      t,
      field,
      text,
      waitUntil: waitUntil,
      stage: stage,
      label: 'explicit saved chat text',
    );
    await waitUntil(
      () => find
          .byWidgetPredicate(
            (w) =>
                w is IconButton &&
                w.tooltip == 'Save chat text' &&
                w.onPressed != null,
          )
          .evaluate()
          .isNotEmpty,
    );
    await capture('ios_chat_text_full_width_native_keyboard');
    await t.tap(find.byTooltip('Save chat text'));
    await waitUntil(
      () =>
          find.byTooltip('Saved text').evaluate().isNotEmpty &&
          t.widget<TextField>(field).enabled == true,
    );
    final saved = await t.runAsync(() => store.read(owner, id));
    expect(saved!.text, text);
    expect(await messages(), before);
    await t.runAsync(
      () => identity.writeAsString(
        jsonEncode({
          'owner': owner,
          'conversation': convo,
          'saved': saved.toJson(),
          'messages': before,
        }),
        flush: true,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await waitUntil(() => t.view.viewInsets.bottom == 0);
    await capture('ios_chat_text_saved_before_restart');
    return;
  }
  await waitUntil(() => find.byTooltip('Saved text').evaluate().isNotEmpty);
  expect(t.widget<TextField>(field).controller!.text, isEmpty);
  await capture('ios_chat_text_restart_no_autofill');
  await t.tap(find.byTooltip('Saved text'));
  await t.pumpAndSettle();
  expect(
    find.text(
      'Device-only text copy, not an outbox. It stays after sending. Restore to edit it.',
    ),
    findsOneWidget,
  );
  await t.tap(find.text('Cancel'));
  await t.pumpAndSettle();
  expect(t.widget<TextField>(field).controller!.text, isEmpty);
  await t.tap(find.byTooltip('Saved text'));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Restore text'));
  await t.tap(find.text('Restore text'));
  await t.pumpAndSettle();
  expect(t.widget<TextField>(field).controller!.text, text);
  expect(await messages(), before);
  await capture('ios_chat_text_restart_explicit_restore');
  await t.tap(find.byTooltip('Saved text'));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Remove saved copy'));
  await t.tap(find.text('Remove saved copy'));
  await waitUntil(() => find.byTooltip('Saved text').evaluate().isEmpty);
  expect(await t.runAsync(() => store.read(owner, id)), isNull);
  expect(t.widget<TextField>(field).controller!.text, text);
  expect(await messages(), before);
  await t.runAsync(identity.delete);
}

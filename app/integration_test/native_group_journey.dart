// Disposable local API + real iOS UI coverage. No real people or services.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';

Future<void> nativeGroupJourney(
  WidgetTester t,
  Session session, {
  required Future<void> Function(bool Function()) waitUntil,
  required Future<void> Function(String) capture,
  required Future<void> Function(String) stage,
}) async {
  Future<void> present() async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
  }

  Future<void> tap(Finder target) async {
    await t.ensureVisible(target);
    await present();
    expect(target.hitTestable(), findsOneWidget);
    await t.tap(target);
  }

  const title = 'Native group review';
  expect(session.groupOwnershipEnabled, isTrue);
  expect(session.groupMemberRemovalEnabled, isTrue);
  await stage('native group create awaiting available inbox entry');
  // A returned chat can still be reconciling its receipt while Rooms is open.
  // Hit testing alone does not distinguish an enabled from a disabled button.
  await waitUntil(
    () =>
        find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  w.tooltip == 'New chat' &&
                  w.onPressed != null,
            )
            .hitTestable()
            .evaluate()
            .length ==
        1,
  );
  await stage('native group create through member search');
  await tap(find.byTooltip('New chat'));
  await waitUntil(() => find.byTooltip('New group').evaluate().isNotEmpty);
  await tap(find.byTooltip('New group'));
  await stage('native group mode selected');
  final name = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Group name',
  );
  final search = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        w.decoration?.hintText == 'Search by name or username',
  );
  await waitUntil(() => name.evaluate().isNotEmpty);
  await t.enterText(name, title);
  for (final member in [
    ('asha_e2e', 'Asha Gurung'),
    ('bikram_e2e', 'Bikram Test'),
  ]) {
    await stage('native group searching ${member.$1}');
    await t.enterText(search, member.$1);
    await waitUntil(() => find.text(member.$2).evaluate().isNotEmpty);
    FocusManager.instance.primaryFocus?.unfocus();
    await waitUntil(() => t.view.viewInsets.bottom == 0);
    await t.pump(const Duration(milliseconds: 600));
    await t.ensureVisible(find.text(member.$2));
    await tap(find.text(member.$2));
    await stage('native group selected ${member.$1}');
    await t.pump();
  }
  await stage('native group submitting two selected members');
  await tap(find.text('Create group (2)'));
  await waitUntil(
    () =>
        find.byType(ChatPage).evaluate().isNotEmpty &&
        find.text(title).evaluate().isNotEmpty &&
        find.byTooltip('Send message').evaluate().isNotEmpty,
  );
  await present();
  final groupId =
      t.widget<ChatPage>(find.byType(ChatPage)).convo['public_id'] as String;
  Future<Map> snapshot() async {
    final value = await t.runAsync(
      () => session.call('GET', '/conversations/$groupId'),
    );
    expect(value, isA<Map>());
    final result = (value as Map)['conversation'];
    expect(result, isA<Map>());
    return result as Map;
  }

  Future<void> send(String body) async {
    final input = find.widgetWithText(TextField, 'Message');
    await t.enterText(input, body);
    await t.pump(const Duration(milliseconds: 600));
    await tap(find.byTooltip('Send message'));
    await waitUntil(
      () =>
          find.text(body).evaluate().isNotEmpty &&
          find.text('Sending').evaluate().isEmpty,
    );
    expect(find.text('Delivery unconfirmed. Tap to retry.'), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await waitUntil(() => t.view.viewInsets.bottom == 0);
    await t.pump(const Duration(milliseconds: 600));
  }

  await send('Native group history remains after membership changes');
  expect(find.text('3 members'), findsOneWidget);
  await capture('ios_group_created');
  final before = await snapshot();
  expect(before['my_role'], 'owner');
  expect((before['members'] as List).length, 3);

  await tap(find.text(title));
  await waitUntil(() => find.text('Manage members').evaluate().isNotEmpty);
  await tap(find.text('Manage members'));
  await waitUntil(
    () =>
        find.byTooltip('Remove from group: @bikram_e2e').evaluate().isNotEmpty,
  );
  await t.ensureVisible(find.byTooltip('Remove from group: @bikram_e2e'));
  await tap(find.byTooltip('Remove from group: @bikram_e2e'));
  await waitUntil(() => find.text('Remove member?').evaluate().isNotEmpty);
  expect(find.text('Bikram Test\n@bikram_e2e'), findsOneWidget);
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_group_remove_confirm');
  await tap(find.widgetWithText(FilledButton, 'Remove from group'));
  await waitUntil(
    () => find
        .text('Member removed. Their earlier messages have not been deleted.')
        .evaluate()
        .isNotEmpty,
  );
  expect(find.text('Bikram Test'), findsNothing);
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_group_removed');
  final removed = await snapshot();
  expect(removed['my_role'], 'owner');
  expect((removed['members'] as List).map((m) => m['username']).toSet(), {
    'synthetic_member',
    'asha_e2e',
  });
  expect(removed['ownership_revision'], isNot(before['ownership_revision']));

  await t.pageBack();
  await waitUntil(
    () =>
        find.byType(GroupInfoPage).evaluate().isNotEmpty &&
        find.text('2 members').evaluate().isNotEmpty,
  );
  await present();
  expect(find.text('Rename group'), findsOneWidget);
  await tap(find.text('Group ownership'));
  await waitUntil(
    () => find.byTooltip('Make owner: @asha_e2e').evaluate().isNotEmpty,
  );
  await t.ensureVisible(find.byTooltip('Make owner: @asha_e2e'));
  await tap(find.byTooltip('Make owner: @asha_e2e'));
  await waitUntil(() => find.text('Make owner?').evaluate().isNotEmpty);
  expect(find.text('Asha Gurung\n@asha_e2e'), findsOneWidget);
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_group_owner_confirm');
  await tap(find.widgetWithText(FilledButton, 'Make owner'));
  await waitUntil(
    () => find
        .text('Ownership transferred. You are still a group member.')
        .evaluate()
        .isNotEmpty,
  );
  expect(find.byTooltip('Make owner: @asha_e2e'), findsNothing);
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_group_transferred');
  final transferred = await snapshot();
  expect(transferred['my_role'], 'member');
  final members = transferred['members'] as List;
  expect(members.map((m) => m['username']).toSet(), {
    'synthetic_member',
    'asha_e2e',
  });
  expect(
    members.singleWhere((m) => m['group_role'] == 'owner')['username'],
    'asha_e2e',
  );
  expect(
    transferred['ownership_revision'],
    isNot(removed['ownership_revision']),
  );

  await t.pageBack();
  await waitUntil(
    () =>
        find.byType(GroupInfoPage).evaluate().isNotEmpty &&
        find.text('2 members').evaluate().isNotEmpty &&
        find.text('Rename group').evaluate().isEmpty,
  );
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_group_member_role');
  await t.pageBack();
  await waitUntil(
    () =>
        find.byType(ChatPage).evaluate().isNotEmpty &&
        find.text('2 members').evaluate().isNotEmpty,
  );
  await present();
  expect(find.text('3 members'), findsNothing);
  expect(
    find.text('Native group history remains after membership changes'),
    findsOneWidget,
  );
  await send('Native member can still send after ownership handoff');
  await t.pageBack();
  await waitUntil(() => find.byTooltip('New chat').evaluate().isNotEmpty);
  await stage(
    'native group removal and ownership receipt verified; history and member send retained',
  );
}

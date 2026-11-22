// Synthetic membership UI only. No real member, message or group is changed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/group_ownership_page.dart';
import 'package:sanjaal/ui.dart';

import 'group_ownership_test.dart' as h;
import 'upload_center_test.dart' as base;

Map<String, dynamic> removed() {
  final value = h.copy(h.snapshot());
  value['ownership_revision'] = 'c' * 64;
  value['members'] = (value['members'] as List)
      .where((m) => m['public_id'] != h.next)
      .toList();
  return value;
}

Future<void> fixture(
  WidgetTester t,
  Future<void> Function(Session) run,
  Future<http.Response> Function(http.Request) respond,
) => h.fixture(t, (s) async {
  s.groupMemberRemovalEnabled = true;
  s.groupOwnershipEnabled = false; // These capabilities are independent.
  await run(s);
}, respond);
Future<void> mount(
  WidgetTester t,
  Session s, {
  double scale = 1,
  Widget? home,
}) => h.mount(
  t,
  s,
  scale: scale,
  home:
      home ??
      GroupOwnershipPage(session: s, groupId: h.group, removeMembers: true),
);
Future<void> choose(WidgetTester t) async {
  final button = find.byWidgetPredicate(
    (w) => w is IconButton && w.tooltip == '${t_('Remove from group')}: @next',
  );
  await t.scrollUntilVisible(
    button.hitTestable(),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.tap(button.hitTestable());
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) => t.runAsync(() async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('group-ownership-review')),
  );
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('/downloads/sanjaal-group-member-removal-$name.png')
      .writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
});
void phone(WidgetTester t, [Size size = const Size(390, 844)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    for (final pair in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final file = File(pair.$2);
      if (file.existsSync()) {
        await (FontLoader(pair.$1)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });
  testWidgets(
    'confirmed removal dispatches exact stable member once and verifies remaining owner',
    (t) async {
      phone(t);
      final requests = <Map>[];
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          expect(find.byTooltip('Remove from group: @owner'), findsNothing);
          await capture(t, 'page-en');
          await choose(t);
          final approve = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Remove from group'),
              )
              .onPressed!;
          approve();
          approve();
          await base.flush(t);
          await t.pumpAndSettle();
          expect(requests, [
            {'member_id': h.next, 'ownership_revision': h.revision},
          ]);
          expect(
            find.text(
              'Member removed. Their earlier messages have not been deleted.',
            ),
            findsOneWidget,
          );
          expect(find.text('Synthetic Next'), findsNothing);
          expect(find.text('Synthetic Third'), findsOneWidget);
          expect(find.text('Synthetic Owner (@owner)'), findsOneWidget);
          await capture(t, 'success-en');
        },
        (r) async {
          if (r.method == 'POST') {
            expect(r.url.path.endsWith('/member-removals'), isTrue);
            requests.add(jsonDecode(r.body) as Map);
            return base.json({'conversation': removed()});
          }
          return base.json({'conversation': h.snapshot()});
        },
      );
    },
  );
  testWidgets('cancel and non-owner reads offer no removal', (t) async {
    var writes = 0;
    await fixture(
      t,
      (s) async {
        await mount(t, s);
        await choose(t);
        await t.tap(find.widgetWithText(TextButton, 'Cancel'));
        await t.pumpAndSettle();
        expect(writes, 0);
        await t.pumpWidget(const SizedBox());
        await mount(t, s);
      },
      (r) async {
        if (r.method == 'POST') writes++;
        return base.json({'conversation': h.snapshot()});
      },
    );
    await fixture(t, (s) async {
      await mount(t, s);
      expect(
        find.text('Only the current owner can remove another member.'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip ?? '').startsWith('Remove from group:'),
        ),
        findsNothing,
      );
    }, (r) async => base.json({'conversation': h.snapshot(transferred: true)}));
  });
  for (final invalid in [
    'target-still-present',
    'wrong-member-removed',
    'owner-changed',
    'revision-unchanged',
  ]) {
    testWidgets(
      '$invalid acknowledgement is not confirmed and requires explicit reload',
      (t) async {
        var writes = 0;
        await fixture(
          t,
          (s) async {
            await mount(t, s);
            await choose(t);
            await t.tap(find.widgetWithText(FilledButton, 'Remove from group'));
            await base.flush(t);
            expect(writes, 1);
            expect(
              find.text(
                'Member removed. Their earlier messages have not been deleted.',
              ),
              findsNothing,
            );
            expect(
              find.text(
                'The result could not be confirmed. Reload the group before choosing again.',
              ),
              findsOneWidget,
            );
            expect(find.byTooltip('Remove from group: @next'), findsNothing);
          },
          (r) async {
            if (r.method != 'POST') {
              return base.json({'conversation': h.snapshot()});
            }
            writes++;
            final value = removed();
            if (invalid == 'target-still-present') {
              value['members'] = h.snapshot()['members'];
            }
            if (invalid == 'wrong-member-removed') {
              value['members'] = (h.snapshot()['members'] as List)
                  .where((m) => m['public_id'] != h.third)
                  .toList();
            }
            if (invalid == 'owner-changed') {
              value['my_role'] = 'member';
              for (final m in value['members']) {
                m['group_role'] = m['public_id'] == h.third
                    ? 'owner'
                    : 'member';
              }
            }
            if (invalid == 'revision-unchanged') {
              value['ownership_revision'] = h.revision;
            }
            return base.json({'conversation': value});
          },
        );
      },
    );
  }
  testWidgets(
    'unknown removal outcome reloads current membership without another write',
    (t) async {
      var reads = 0, writes = 0;
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          await choose(t);
          await t.tap(find.widgetWithText(FilledButton, 'Remove from group'));
          await base.flush(t);
          await t.tap(find.widgetWithText(FilledButton, 'Reload group'));
          await base.flush(t);
          await t.pumpAndSettle();
          expect(reads, 2);
          expect(writes, 1);
          expect(find.text('Synthetic Next'), findsNothing);
          expect(find.text('Synthetic Third'), findsOneWidget);
        },
        (r) async {
          if (r.method == 'POST') {
            writes++;
            throw const SocketException('Synthetic acknowledgement lost');
          }
          return base.json({
            'conversation': ++reads == 1 ? h.snapshot() : removed(),
          });
        },
      );
    },
  );
  testWidgets('replacement session invalidates retained removal confirmation', (
    t,
  ) async {
    var writes = 0;
    await fixture(
      t,
      (s) async {
        await mount(t, s);
        await choose(t);
        final approve = t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Remove from group'),
            )
            .onPressed!;
        await s.login('same-owner', 'not-a-password');
        await base.flush(t);
        approve();
        await t.pumpAndSettle();
        expect(writes, 0);
        expect(find.byType(AlertDialog), findsNothing);
      },
      (r) async {
        if (r.method == 'POST') writes++;
        return base.json({'conversation': h.snapshot()});
      },
    );
  });
  testWidgets(
    'changing action mode permanently retires old removal authority',
    (t) async {
      var writes = 0;
      final removalMode = ValueNotifier(true);
      addTearDown(removalMode.dispose);
      await fixture(
        t,
        (s) async {
          s.groupOwnershipEnabled = true;
          await mount(
            t,
            s,
            home: ValueListenableBuilder<bool>(
              valueListenable: removalMode,
              builder: (_, removing, _) => GroupOwnershipPage(
                session: s,
                groupId: h.group,
                removeMembers: removing,
              ),
            ),
          );
          await choose(t);
          final approve = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Remove from group'),
              )
              .onPressed!;
          removalMode.value = false;
          await base.flush(t);
          approve();
          await t.pumpAndSettle();
          removalMode.value = true;
          await base.flush(t);
          expect(writes, 0);
          expect(
            find.text(
              'This group view has changed. Close it and open the group again.',
            ),
            findsOneWidget,
          );
        },
        (r) async {
          if (r.method == 'POST') writes++;
          return base.json({'conversation': h.snapshot()});
        },
      );
    },
  );
  testWidgets(
    'older server never borrows the ownership capability or reads membership',
    (t) async {
      var reads = 0;
      await fixture(
        t,
        (s) async {
          s.groupMemberRemovalEnabled = false;
          s.groupOwnershipEnabled = true;
          await mount(t, s);
          expect(
            find.text('Member management is not available on this server.'),
            findsOneWidget,
          );
          expect(find.byTooltip('Reload group'), findsNothing);
          expect(reads, 0);
        },
        (r) async {
          reads++;
          return base.json({'conversation': h.snapshot()});
        },
      );
    },
  );
  testWidgets('group info refreshes its member list after removal', (t) async {
    var writes = 0;
    await fixture(
      t,
      (s) async {
        await mount(
          t,
          s,
          home: GroupInfoPage(session: s, convo: h.snapshot()),
        );
        expect(find.text('Group ownership'), findsNothing);
        await t.tap(find.text('Manage members'));
        await base.flush(t);
        await t.pumpAndSettle();
        await choose(t);
        await t.tap(find.widgetWithText(FilledButton, 'Remove from group'));
        await base.flush(t);
        await t.pageBack();
        await base.flush(t);
        await t.pumpAndSettle();
        expect(find.text('2 members'), findsOneWidget);
        expect(find.text('Synthetic Next'), findsNothing);
        expect(find.text('Rename group'), findsOneWidget);
        expect(writes, 1);
      },
      (r) async {
        if (r.method == 'POST') writes++;
        return base.json({
          'conversation': writes == 0 ? h.snapshot() : removed(),
        });
      },
    );
  });
  for (final language in ['en', 'ne']) {
    testWidgets(
      'removal confirmation is readable at narrow large text $language',
      (t) async {
        phone(t, const Size(320, 640));
        prefs.lang = language;
        addTearDown(() => prefs.lang = 'en');
        await fixture(t, (s) async {
          await mount(t, s, scale: 1.8);
          await choose(t);
          expect(
            find.text(
              t_(
                'They will lose access to this group until someone adds them again. Messages and copies already received are not erased.',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find
                .widgetWithText(FilledButton, t_('Remove from group'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(TextButton, t_('Cancel')).hitTestable(),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await capture(t, 'confirm-$language');
        }, (r) async => base.json({'conversation': h.snapshot()}));
      },
    );
  }
  testWidgets(
    'revoked group read keeps cached messages and draft but retires send and recording callbacks',
    (t) async {
      phone(t);
      var reads = 0, writes = 0;
      final poll = Completer<http.Response>();
      await fixture(
        t,
        (s) async {
          await mount(
            t,
            s,
            home: ChatPage(session: s, convo: h.snapshot()),
          );
          await t.enterText(find.byType(TextField), 'Keep this unsent draft');
          final send = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Send message',
                ),
              )
              .onPressed!;
          final record = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Voice message',
                ),
              )
              .onPressed!;
          poll.complete(
            base.json({'message': 'Synthetic membership unavailable'}, 404),
          );
          await base.flush(t);
          await t.pumpAndSettle();
          send();
          record();
          await base.flush(t);
          expect(
            find.text(
              'This group is no longer available to you. You cannot load or send messages here.',
            ),
            findsOneWidget,
          );
          expect(find.text('Cached synthetic message'), findsOneWidget);
          final field = t.widget<TextField>(find.byType(TextField));
          expect(field.readOnly, isTrue);
          expect(field.controller!.text, 'Keep this unsent draft');
          expect(find.byTooltip('Send message'), findsNothing);
          expect(writes, 0);
          await t.pump(const Duration(seconds: 25));
          await base.flush(t);
          expect(reads, 2);
          expect(t.takeException(), isNull);
          await capture(t, 'unavailable-en');
        },
        (r) async {
          if (r.method == 'GET' && r.url.path.endsWith('/messages')) {
            if (++reads > 1) return poll.future;
            return base.json({
              'data': [
                {
                  'public_id': 'cached',
                  'seq': 1,
                  'body': 'Cached synthetic message',
                  'kind': 'text',
                  'sender': {'public_id': h.owner, 'username': 'owner'},
                  'created_at': '2026-11-22T14:00:00Z',
                },
              ],
              'typing': [],
            });
          }
          if (r.method == 'POST' && r.url.path.endsWith('/messages')) writes++;
          return base.json({});
        },
      );
    },
  );

  for (final language in ['en', 'ne']) {
    testWidgets(
      'unavailable group stays scrollable with large text and keyboard $language',
      (t) async {
        phone(t, const Size(320, 640));
        prefs.lang = language;
        addTearDown(() => prefs.lang = 'en');
        final poll = Completer<http.Response>();
        var reads = 0;
        await fixture(
          t,
          (s) async {
            await mount(
              t,
              s,
              scale: 1.8,
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(viewInsets: const EdgeInsets.only(bottom: 240)),
                  child: ChatPage(session: s, convo: h.snapshot()),
                ),
              ),
            );
            await t.enterText(
              find.byType(TextField),
              language == 'ne'
                  ? 'यो नपठाइएको मस्यौदा हो।'
                  : 'This draft is still mine.',
            );
            poll.complete(
              base.json({'message': 'Synthetic unavailable group'}, 404),
            );
            await base.flush(t);
            await t.pumpAndSettle();
            final field = find.byType(TextField);
            await t.scrollUntilVisible(
              field.hitTestable(),
              100,
              scrollable: find.byType(Scrollable).first,
            );
            await t.pumpAndSettle();
            expect(t.widget<TextField>(field).readOnly, isTrue);
            expect(find.byTooltip(t_('Send message')), findsNothing);
            expect(t.takeException(), isNull);
            await capture(t, 'unavailable-large-$language');
          },
          (r) async {
            if (r.method == 'GET' && r.url.path.endsWith('/messages')) {
              if (++reads == 1) return base.json({'data': [], 'typing': []});
              return poll.future;
            }
            return base.json({});
          },
        );
      },
    );
  }

  testWidgets(
    'hidden membership failure never dismisses another route keyboard',
    (t) async {
      final send = Completer<http.Response>(),
          poll = Completer<http.Response>();
      var reads = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await fixture(
        t,
        (s) async {
          await mount(
            t,
            s,
            home: ChatPage(session: s, convo: h.snapshot()),
          );
          await t.enterText(find.byType(TextField), 'Synthetic pending send');
          await t.tap(find.byTooltip('Send message'));
          await base.flush(t);
          final nav = t.state<NavigatorState>(find.byType(Navigator));
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: TextField(focusNode: focus, autofocus: true),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          send.complete(
            base.json({'message': 'Synthetic unavailable membership'}, 404),
          );
          await base.flush(t);
          expect(focus.hasFocus, isTrue);
          poll.complete(base.json({'data': []}));
          nav.pop();
          await t.pumpAndSettle();
          expect(
            find.text(
              'This group is no longer available to you. You cannot load or send messages here.',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'GET' && r.url.path.endsWith('/messages')) {
            if (++reads == 1) return base.json({'data': [], 'typing': []});
            return poll.future;
          }
          if (r.method == 'POST' && r.url.path.endsWith('/messages')) {
            return send.future;
          }
          return base.json({});
        },
      );
    },
  );

  testWidgets(
    'owner-only group has an explicit empty state and no self-removal',
    (t) async {
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          expect(
            find.text('There are no other members to remove.'),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  (w.tooltip ?? '').startsWith('Remove from group:'),
            ),
            findsNothing,
          );
        },
        (r) async {
          final value = h.copy(h.snapshot());
          value['members'] = [(value['members'] as List).first];
          return base.json({'conversation': value});
        },
      );
    },
  );
}

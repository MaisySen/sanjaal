// Synthetic group ownership only. No real group or account is changed.
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
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart';

import 'upload_center_test.dart' as h;

const group = '10000000-0000-4000-8000-000000000001';
const owner = '20000000-0000-4000-8000-000000000001';
const next = '20000000-0000-4000-8000-000000000002';
const third = '20000000-0000-4000-8000-000000000003';
String get revision => 'a' * 64;
Map<String, dynamic> snapshot({bool transferred = false}) => {
  'public_id': group,
  'type': 'group',
  'title': 'Synthetic group',
  'ownership_revision': transferred ? 'b' * 64 : revision,
  'my_role': transferred ? 'member' : 'owner',
  'members': [
    {
      'public_id': owner,
      'username': 'owner',
      'name': 'Synthetic Owner',
      'group_role': transferred ? 'member' : 'owner',
    },
    {
      'public_id': next,
      'username': 'next',
      'name': 'Synthetic Next',
      'group_role': transferred ? 'owner' : 'member',
    },
    {
      'public_id': third,
      'username': 'third',
      'name': 'Synthetic Third',
      'group_role': 'member',
    },
  ],
};
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
Future<void> fixture(
  WidgetTester t,
  Future<void> Function(Session) run,
  Future<http.Response> Function(http.Request) respond,
) => h.fixture(t, (s, _) async {
  s.user = {'public_id': owner, 'username': 'owner'};
  s.groupOwnershipEnabled = true;
  s.notifyListeners();
  await run(s);
}, respond: respond);
Future<void> mount(
  WidgetTester t,
  Session s, {
  Widget? home,
  double scale = 1,
}) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('group-ownership-review'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
          Brightness.light,
          fontFamily: 'Roboto',
          fontFamilyFallback: ['NotoDev'],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? GroupOwnershipPage(session: s, groupId: group),
      ),
    ),
  );
  await h.flush(t);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t) async {
  final button = find.byWidgetPredicate(
    (w) => w is IconButton && w.tooltip == '${t_('Make owner')}: @next',
  );
  await t.scrollUntilVisible(
    button.hitTestable(),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
  await t.tap(button.hitTestable());
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('group-ownership-review')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/downloads/sanjaal-group-ownership-$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final p in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final file = File(p.$2);
      if (file.existsSync()) {
        await (FontLoader(p.$1)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });

  test('snapshot binds exact group, actor, unique members and one owner', () {
    final parsed = GroupOwnershipSnapshot(snapshot(), group, owner);
    expect(parsed.isOwner, isTrue);
    expect(parsed.owner['public_id'], owner);
    for (final alter in <void Function(Map<String, dynamic>)>[
      (s) => s['public_id'] = '10000000-0000-4000-8000-000000000099',
      (s) => s['my_role'] = 'member',
      (s) => s['ownership_revision'] = 'bad',
      (s) => s['members'][1]['group_role'] = 'owner',
      (s) => s['members'][0]['group_role'] = 'member',
      (s) => s['members'][1]['public_id'] = owner,
      (s) => s['members'][1]['username'] = 'owner',
      (s) => s['members'][0]['public_id'] = third,
      (s) => s['members'][1]['name'] = 42,
      (s) => s['members'][1]['avatar_url'] = 42,
    ]) {
      final value = copy(snapshot());
      alter(value);
      expect(
        () => GroupOwnershipSnapshot(value, group, owner),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'explicit stable-member confirmation transfers once and keeps former owner in group',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var writes = 0;
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          await capture(t, 'page-normal-en');
          await choose(t);
          expect(find.text('Synthetic Next\n@next'), findsOneWidget);
          await t.tap(find.widgetWithText(TextButton, 'Cancel'));
          await t.pumpAndSettle();
          expect(writes, 0);
          await choose(t);
          final approve = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Make owner'),
              )
              .onPressed!;
          approve();
          approve();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(writes, 1);
          expect(
            find.text('Ownership transferred. You are still a group member.'),
            findsOneWidget,
          );
          expect(find.byTooltip('Make owner: @third'), findsNothing);
          expect(find.text('Synthetic Next (@next)'), findsOneWidget);
          await capture(t, 'success-en');
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            writes++;
            expect(r.url.path, '/api/v1/conversations/$group/ownership');
            expect(jsonDecode(r.body), {
              'member_id': next,
              'ownership_revision': revision,
            });
            return h.json({'conversation': snapshot(transferred: true)});
          }
          return h.json({'conversation': snapshot()});
        },
      );
    },
  );

  for (final changed in [false, true]) {
    testWidgets(
      'unknown handoff never replays and explicit read reconciles changed=$changed',
      (t) async {
        var writes = 0, reads = 0;
        VoidCallback? oldAction;
        await fixture(
          t,
          (s) async {
            await mount(t, s);
            oldAction = t
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Make owner: @next',
                  ),
                )
                .onPressed;
            await choose(t);
            await t.tap(find.widgetWithText(FilledButton, 'Make owner'));
            await h.flush(t);
            await t.pumpAndSettle();
            expect(writes, 1);
            expect(
              find.text(
                'The result could not be confirmed. Reload the group before choosing again.',
              ),
              findsOneWidget,
            );
            oldAction!();
            await h.flush(t);
            expect(find.byType(AlertDialog), findsNothing);
            expect(writes, 1);
            await t.tap(find.widgetWithText(FilledButton, 'Reload group'));
            await h.flush(t);
            await t.pumpAndSettle();
            expect(reads, 2);
            expect(
              find.text(
                'Synthetic ${changed ? 'Next (@next)' : 'Owner (@owner)'}',
              ),
              findsOneWidget,
            );
            expect(
              find.byTooltip('Make owner: @next'),
              changed ? findsNothing : findsOneWidget,
            );
            expect(t.takeException(), isNull);
          },
          (r) async {
            if (r.method == 'POST') {
              writes++;
              return h.json({'message': 'Synthetic lost reply'}, 500);
            }
            reads++;
            return h.json({
              'conversation': snapshot(transferred: changed && reads > 1),
            });
          },
        );
      },
    );
  }

  testWidgets('malformed acknowledgement is not success and requires reload', (
    t,
  ) async {
    await fixture(
      t,
      (s) async {
        await mount(t, s);
        await choose(t);
        await t.tap(find.widgetWithText(FilledButton, 'Make owner'));
        await h.flush(t);
        await t.pumpAndSettle();
        expect(
          find.text('Ownership transferred. You are still a group member.'),
          findsNothing,
        );
        expect(
          find.widgetWithText(FilledButton, 'Reload group'),
          findsOneWidget,
        );
        expect(find.byTooltip('Make owner: @next'), findsNothing);
      },
      (r) async => h.json({
        'conversation': r.method == 'POST' ? snapshot() : snapshot(),
      }),
    );
  });

  testWidgets('covered confirmation cannot write or pop another route', (
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
              find.widgetWithText(FilledButton, 'Make owner'),
            )
            .onPressed!;
        final nav = t.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover route')),
            ),
          ),
        );
        await t.pumpAndSettle();
        approve();
        await h.flush(t);
        expect(writes, 0);
        expect(find.text('Cover route'), findsOneWidget);
        nav.pop();
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(TextButton, 'Cancel'));
        await t.pumpAndSettle();
      },
      (r) async {
        if (r.method == 'POST') writes++;
        return h.json({'conversation': snapshot()});
      },
    );
  });

  testWidgets(
    'replacement session retires confirmation and its retained action',
    (t) async {
      var writes = 0;
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          await choose(t);
          final approve = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Make owner'),
              )
              .onPressed!;
          await s.login('same-owner', 'not-a-password');
          await h.flush(t);
          await t.pumpAndSettle();
          approve();
          await h.flush(t);
          expect(writes, 0);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('Synthetic group'), findsNothing);
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') writes++;
          return h.json({'conversation': snapshot()});
        },
      );
    },
  );

  testWidgets('late handoff receipt cannot enter replacement session', (
    t,
  ) async {
    final response = Completer<http.Response>();
    var writes = 0;
    await fixture(
      t,
      (s) async {
        await mount(t, s);
        await choose(t);
        await t.tap(find.widgetWithText(FilledButton, 'Make owner'));
        await h.flush(t);
        expect(writes, 1);
        await s.login('same-owner', 'not-a-password');
        await h.flush(t);
        response.complete(
          h.json({'conversation': snapshot(transferred: true)}),
        );
        await h.flush(t);
        await t.pumpAndSettle();
        expect(
          find.text('Ownership transferred. You are still a group member.'),
          findsNothing,
        );
        expect(find.text('Synthetic group'), findsNothing);
        expect(t.takeException(), isNull);
      },
      (r) async {
        if (r.method == 'POST') {
          writes++;
          return response.future;
        }
        return h.json({'conversation': snapshot()});
      },
    );
  });

  testWidgets(
    'group info refreshes role after handoff and removes old rename action',
    (t) async {
      var transferred = false;
      await fixture(
        t,
        (s) async {
          await mount(
            t,
            s,
            home: GroupInfoPage(session: s, convo: snapshot()),
          );
          await t.tap(find.text('Group ownership'));
          await h.flush(t);
          await t.pumpAndSettle();
          await choose(t);
          await t.tap(find.widgetWithText(FilledButton, 'Make owner'));
          await h.flush(t);
          await t.pumpAndSettle();
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Rename group'), findsNothing);
          expect(find.text('Leave group'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') transferred = true;
          return h.json({'conversation': snapshot(transferred: transferred)});
        },
      );
    },
  );

  testWidgets(
    'older server exposes neither a dead group action nor authenticated reads',
    (t) async {
      var calls = 0;
      await fixture(
        t,
        (s) async {
          s.groupOwnershipEnabled = false;
          await mount(t, s);
          expect(
            find.text(
              'Group ownership changes are not available on this server.',
            ),
            findsOneWidget,
          );
          expect(find.byTooltip('Reload group'), findsNothing);
          await mount(
            t,
            s,
            home: GroupInfoPage(session: s, convo: snapshot()),
          );
          expect(find.text('Group ownership'), findsNothing);
          expect(calls, 0);
        },
        (r) async {
          calls++;
          return h.json({'conversation': snapshot()});
        },
      );
    },
  );

  testWidgets(
    'malformed read cannot offer an owner action and explicit reload recovers',
    (t) async {
      var reads = 0, writes = 0;
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          expect(
            find.text('Could not load group ownership. Try again.'),
            findsOneWidget,
          );
          expect(find.byTooltip('Make owner: @next'), findsNothing);
          await t.tap(find.widgetWithText(FilledButton, 'Reload group'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byTooltip('Make owner: @next'), findsOneWidget);
          expect(writes, 0);
        },
        (r) async {
          if (r.method == 'POST') writes++;
          reads++;
          final value = snapshot();
          if (reads == 1) value['members'][1]['group_role'] = 'owner';
          return h.json({'conversation': value});
        },
      );
    },
  );

  testWidgets('covered page rejects a retained member choice', (t) async {
    var writes = 0;
    await fixture(
      t,
      (s) async {
        await mount(t, s);
        final action = t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Make owner: @next',
              ),
            )
            .onPressed!;
        final nav = t.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover route')),
            ),
          ),
        );
        await t.pumpAndSettle();
        action();
        await h.flush(t);
        expect(find.text('Cover route'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(writes, 0);
        nav.pop();
        await t.pumpAndSettle();
      },
      (r) async {
        if (r.method == 'POST') writes++;
        return h.json({'conversation': snapshot()});
      },
    );
  });

  testWidgets(
    'a newer group read retires an old confirmation without a write',
    (t) async {
      var reads = 0, writes = 0;
      await fixture(
        t,
        (s) async {
          await mount(t, s);
          final reload = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Reload group',
                ),
              )
              .onPressed!;
          await choose(t);
          final approve = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Make owner'),
              )
              .onPressed!;
          reload();
          await h.flush(t);
          approve();
          await t.pumpAndSettle();
          expect(reads, 2);
          expect(writes, 0);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await choose(t);
          await t.tap(find.widgetWithText(TextButton, 'Cancel'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            writes++;
          } else {
            reads++;
          }
          return h.json({'conversation': snapshot()});
        },
      );
    },
  );

  testWidgets('changing the group retires its state permanently', (t) async {
    var calls = 0;
    final selected = ValueNotifier(group);
    addTearDown(selected.dispose);
    await fixture(
      t,
      (s) async {
        await mount(
          t,
          s,
          home: ValueListenableBuilder<String>(
            valueListenable: selected,
            builder: (_, id, _) => GroupOwnershipPage(session: s, groupId: id),
          ),
        );
        await choose(t);
        final approve = t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Make owner'),
            )
            .onPressed!;
        selected.value = '10000000-0000-4000-8000-000000000099';
        await h.flush(t);
        await t.pumpAndSettle();
        approve();
        await h.flush(t);
        expect(
          find.text(
            'This group view has changed. Close it and open the group again.',
          ),
          findsOneWidget,
        );
        selected.value = group;
        await h.flush(t);
        expect(find.text('Synthetic group'), findsNothing);
        expect(calls, 1);
        expect(t.takeException(), isNull);
      },
      (r) async {
        calls++;
        return h.json({'conversation': snapshot()});
      },
    );
  });

  for (final language in ['en', 'ne']) {
    testWidgets(
      'ownership confirmation is readable at narrow large text $language',
      (t) async {
        prefs.lang = language;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await fixture(t, (s) async {
          await mount(t, s, scale: 1.8);
          await capture(t, 'page-$language');
          await t.ensureVisible(find.byTooltip('${t_('Make owner')}: @next'));
          await choose(t);
          await t.ensureVisible(
            find.widgetWithText(FilledButton, t_('Make owner')),
          );
          await t.pumpAndSettle();
          expect(
            find.widgetWithText(FilledButton, t_('Make owner')).hitTestable(),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('group-ownership-review')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('/downloads/sanjaal-group-ownership-confirm-$language.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await t.tap(find.widgetWithText(TextButton, t_('Cancel')));
          await t.pumpAndSettle();
        }, (r) async => h.json({'conversation': snapshot()}));
      },
    );
  }
}

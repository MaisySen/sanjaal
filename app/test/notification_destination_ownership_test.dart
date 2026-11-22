// Synthetic notification destinations only. No push registration or live activity.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/notifications_page.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/profile_pages.dart';

import 'upload_center_test.dart' as h;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  for (final post in [false, true]) {
    for (final same in [false, true]) {
      testWidgets(
        'retained Activity ${post ? 'post' : 'profile'} callback rejects ${same ? 'same-member login' : 'other account'}',
        (t) async {
          await h.fixture(
            t,
            (s, c) async {
              final routes = Routes();
              await t.pumpWidget(
                MaterialApp(
                  navigatorObservers: [routes],
                  home: NotificationsPage(session: s),
                ),
              );
              await h.flush(t);
              final open = t
                  .widget<ListTile>(find.byType(ListTile).first)
                  .onTap!;
              if (same) {
                await s.login('fixture', 'not-a-password');
              } else {
                s.user = {'public_id': 'other', 'username': 'other'};
                s.notifyListeners();
              }
              await h.flush(t);
              open();
              await t.pumpAndSettle();
              await h.flush(t);
              expect(routes.pushes, 1);
              expect(find.byType(PostPage), findsNothing);
              expect(find.byType(UserProfilePage), findsNothing);
              expect(t.takeException(), isNull);
            },
            respond: (r) async => h.json({
              'data': [
                {
                  'type': 'like',
                  'actor': 'asha',
                  if (post) 'post_id': 'fixture',
                },
              ],
            }),
          );
        },
      );
    }
  }
  testWidgets(
    'current Activity destination opens once and reopens after Back',
    (t) async {
      await h.fixture(
        t,
        (s, c) async {
          final routes = Routes();
          await t.pumpWidget(
            MaterialApp(
              navigatorObservers: [routes],
              home: NotificationsPage(session: s),
            ),
          );
          await h.flush(t);
          final open = t.widget<ListTile>(find.byType(ListTile).first).onTap!;
          open();
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 2);
          expect(find.byType(PostPage), findsOneWidget);
          expect(find.text('Confirmed fixture'), findsOneWidget);
          await t.pageBack();
          await t.pumpAndSettle();
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 3);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
        respond: (r) async => r.url.path.endsWith('/notifications')
            ? h.json({
                'data': [
                  {'type': 'like', 'actor': 'asha', 'post_id': 'fixture'},
                ],
              })
            : h.json({'post': h.post('fixture')}),
      );
    },
  );
  testWidgets('current follow notification opens its actor profile', (t) async {
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(MaterialApp(home: NotificationsPage(session: s)));
        await h.flush(t);
        await t.tap(find.text('@asha started following you'));
        await h.flush(t);
        await t.pumpAndSettle();
        expect(find.byType(UserProfilePage), findsOneWidget);
        expect(
          t.widget<UserProfilePage>(find.byType(UserProfilePage)).username,
          'asha',
        );
        expect(t.takeException(), isNull);
        await t.pageBack();
        await t.pumpAndSettle();
      },
      respond: (r) async => r.url.path.endsWith('/notifications')
          ? h.json({
              'data': [
                {'type': 'follow', 'actor': 'asha'},
              ],
            })
          : h.json({'message': 'Unavailable'}, 404),
    );
  });
  testWidgets('replaced Activity rows invalidate retained destinations', (
    t,
  ) async {
    var reads = 0;
    await h.fixture(
      t,
      (s, c) async {
        final routes = Routes();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: NotificationsPage(session: s),
          ),
        );
        await h.flush(t);
        final old = t.widget<ListTile>(find.byType(ListTile).first).onTap!;
        await t.tap(find.byTooltip('Refresh'));
        await h.flush(t);
        expect(reads, 2);
        expect(find.textContaining('@bina'), findsOneWidget);
        old();
        await h.flush(t);
        await t.pumpAndSettle();
        expect(routes.pushes, 1);
        expect(find.byType(UserProfilePage), findsNothing);
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.url.path.endsWith('/notifications')) {
          return h.json({
            'data': [
              {'type': 'follow', 'actor': ++reads == 1 ? 'asha' : 'bina'},
            ],
          });
        }
        return h.json({});
      },
    );
  });
  testWidgets('disposed Activity callback cannot navigate', (t) async {
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(MaterialApp(home: NotificationsPage(session: s)));
        await h.flush(t);
        final old = t.widget<ListTile>(find.byType(ListTile).first).onTap!;
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Current destination'))),
        );
        old();
        await h.flush(t);
        expect(find.text('Current destination'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
      respond: (r) async => h.json({
        'data': [
          {'type': 'follow', 'actor': 'asha'},
        ],
      }),
    );
  });
}

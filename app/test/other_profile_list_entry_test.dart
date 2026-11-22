// Synthetic default-off member-list candidate only. No live relationship reads.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
  for (final followers in [true, false]) {
    for (final scenario in [
      'revoked capability',
      'blocked refresh',
      'duplicate',
    ]) {
      testWidgets(
        'other-profile ${followers ? 'followers' : 'following'} guards $scenario',
        (t) async {
          var blocked = false, memberReads = 0;
          await h.fixture(
            t,
            (s, c) async {
              s.followListsEnabled = true;
              final routes = Routes();
              await t.pumpWidget(
                MaterialApp(
                  navigatorObservers: [routes],
                  home: UserProfilePage(session: s, username: 'asha'),
                ),
              );
              await h.flush(t);
              final header = t.widget<ProfileHeader>(
                find.byType(ProfileHeader),
              );
              final old = (followers
                  ? header.onFollowers
                  : header.onFollowing)!;
              if (scenario == 'revoked capability') {
                s.followListsEnabled = false;
              } else if (scenario == 'blocked refresh') {
                blocked = true;
                t
                    .widget<IconButton>(
                      find.byWidgetPredicate(
                        (w) =>
                            w is IconButton && w.tooltip == 'Refresh profile',
                      ),
                    )
                    .onPressed!();
                await h.flush(t);
              }
              old();
              if (scenario == 'duplicate') old();
              expect(routes.pushes, scenario == 'duplicate' ? 2 : 1);
              // Do not render the pending member-list destination.
              await t.pumpWidget(const SizedBox());
              await h.flush(t);
              expect(memberReads, 0);
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.url.path.endsWith('/followers') ||
                  r.url.path.endsWith('/following')) {
                memberReads++;
              }
              return h.json(
                r.url.path.endsWith('/users/asha')
                    ? {
                        'user': {
                          'public_id': 'asha',
                          'username': 'asha',
                          'name': 'Synthetic member',
                          'blocked': blocked,
                          'followers_count': 2,
                          'following_count': 3,
                          'posts_count': 0,
                        },
                      }
                    : {'data': []},
              );
            },
          );
        },
      );
    }
  }
}

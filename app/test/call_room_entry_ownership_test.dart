// Offline route-boundary checks only. Destinations are never rendered or joined.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/rooms_page.dart';

import 'upload_center_test.dart' as h;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

VoidCallback open(WidgetTester t, bool calls) => calls
    ? t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Voice call',
            ),
          )
          .onPressed!
    : t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Synthetic room'))
          .onTap!;

void main() {
  for (final calls in [true, false]) {
    final label = calls ? 'Calls' : 'Rooms';
    for (final scenario in ['duplicate', 'disposed', 'replaced row']) {
      testWidgets('$label rejects $scenario retained destination', (t) async {
        var sideEffects = 0;
        await h.fixture(
          t,
          (s, c) async {
            final routes = Routes();
            await t.pumpWidget(
              MaterialApp(
                navigatorObservers: [routes],
                home: calls ? CallsPage(session: s) : RoomsPage(session: s),
              ),
            );
            await h.flush(t);
            final old = open(t, calls);
            if (scenario == 'disposed') {
              await t.pumpWidget(const SizedBox());
            } else if (scenario == 'replaced row') {
              await t
                  .widget<RefreshIndicator>(find.byType(RefreshIndicator))
                  .onRefresh();
              await h.flush(t);
            }
            old();
            if (scenario == 'duplicate') old();
            // Inspect pushes synchronously, then remove all routes before a
            // destination builder can reach call/media/room setup.
            expect(routes.pushes, scenario == 'duplicate' ? 2 : 1);
            await t.pumpWidget(const SizedBox());
            await h.flush(t);
            expect(sideEffects, 0);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method != 'GET') sideEffects++;
            return h.json({
              'data': [
                calls
                    ? {
                        'public_id': 'call',
                        'conversation_id': 'chat',
                        'title': 'Synthetic call',
                        'caller': {'username': 'fixture'},
                        'direction': 'incoming',
                        'kind': 'voice',
                        'status': 'ended',
                        'duration_s': 12,
                        'created_at': '2026-11-17T00:00:00Z',
                      }
                    : {
                        'public_id': 'room',
                        'title': 'Synthetic room',
                        'host_name': 'Fixture',
                      },
              ],
            });
          },
        );
      });
    }
  }
}

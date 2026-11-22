// Synthetic callbacks and HTTP only. No real moderation action.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/settings_page.dart';

import 'upload_center_test.dart' as h;

Map<String, dynamic> member() => {
  'public_id': 'blocked-original',
  'username': 'blocked-original',
};
void main() {
  testWidgets('fresh blocked row stays actionable after refresh', (t) async {
    var writes = 0, reads = 0;
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
        await h.flush(t);
        await t.tap(find.byTooltip('Refresh'));
        await h.flush(t);
        await t.tap(find.text('Unblock'));
        await h.flush(t);
        expect(writes, 1);
        expect(reads, 3);
        expect(find.text('You have not blocked anyone'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.method == 'DELETE') {
          writes++;
          return h.json({'blocked': false});
        }
        reads++;
        return h.json({
          'data': writes == 0 ? [member()] : [],
        });
      },
    );
  });
  for (final shape in [
    'overlap',
    'pending refresh',
    'removed row',
    'replaced snapshot',
  ]) {
    testWidgets('blocked action rejects retained callback during $shape', (
      t,
    ) async {
      var writes = 0, reads = 0;
      final write = Completer<http.Response>();
      final refresh = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
          await h.flush(t);
          final retained = t
              .widget<TextButton>(find.widgetWithText(TextButton, 'Unblock'))
              .onPressed!;
          if (shape == 'overlap') {
            retained();
            retained();
            await h.flush(t);
          } else {
            await t.tap(find.byTooltip('Refresh'));
            await h.flush(t);
            retained();
            await h.flush(t);
          }
          final actualWrites = writes;
          if (!write.isCompleted) write.complete(h.json({}));
          if (!refresh.isCompleted) {
            refresh.complete(
              h.json({
                'data': [member()],
              }),
            );
          }
          await h.flush(t);
          await t.pumpWidget(const SizedBox());
          await h.flush(t);
          expect(actualWrites, shape == 'overlap' ? 1 : 0);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'DELETE') {
            writes++;
            return write.future;
          }
          reads++;
          if (reads == 1) {
            return h.json({
              'data': [member()],
            });
          }
          if (shape == 'pending refresh' && reads == 2) return refresh.future;
          return h.json({
            'data': shape == 'removed row' ? [] : [member()],
          });
        },
      );
    });
  }
}

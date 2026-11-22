// Synthetic settings requests and responses only. No real conversation change.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'upload_center_test.dart' as h;

void main() {
  for (final shape in [
    'same field',
    'other field',
    'other row',
    'pending read',
    'failed read',
    'lost reply',
  ]) {
    testWidgets('inbox settings own the pending operation: $shape', (t) async {
      var reads = 0, writes = 0;
      final pending = Completer<http.Response>();
      final read = Completer<http.Response>();
      final flags = <String, bool>{
        'pinned': false,
        'muted': false,
        'archived': false,
      };
      final otherFlags = <String, bool>{...flags};
      Map<String, dynamic> row(String id) => {
        'public_id': id,
        'type': 'direct',
        'title': id,
        'unread': 0,
        ...(id == 'Original thread' ? flags : otherFlags),
      };
      http.Response rows() => h.json({
        'data': [row('Original thread'), row('Other thread')],
      });
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          VoidCallback entry(String name) => t
              .widget<InkWell>(
                find.ancestor(
                  of: find.text(name),
                  matching: find.byType(InkWell),
                ),
              )
              .onLongPress!;
          final retained = entry(
            shape == 'other row' ? 'Other thread' : 'Original thread',
          );
          entry('Original thread')();
          await h.flush(t);
          await t.tap(find.widgetWithText(ListTile, 'Mute'));
          await h.flush(t);
          retained();
          await h.flush(t);
          final action = find.widgetWithText(
            ListTile,
            shape == 'other field' ? 'Pin to top' : 'Mute',
          );
          if (action.evaluate().isNotEmpty &&
              shape != 'failed read' &&
              shape != 'lost reply') {
            t.widget<ListTile>(action).onTap!();
            await h.flush(t);
          }
          final duplicateWrites = writes;
          final progress = find
              .text('Updating chat settings')
              .evaluate()
              .length;
          final recoverable = find.text('Could not refresh.').evaluate().length;
          final firstReads = reads;
          final unconfirmedMenu = find
              .widgetWithText(ListTile, 'Mute')
              .evaluate()
              .length;
          if (!pending.isCompleted) pending.complete(h.json(flags));
          if (!read.isCompleted) read.complete(rows());
          await h.flush(t);
          // Close an old-source menu before attempting a refresh retry.
          if (find.widgetWithText(ListTile, 'Mute').evaluate().isNotEmpty ||
              find.widgetWithText(ListTile, 'Unmute').evaluate().isNotEmpty) {
            Navigator.of(t.element(find.byType(ChatsPage))).pop();
            await h.flush(t);
          }
          final retry = find.text('Try again');
          if (retry.evaluate().isNotEmpty) {
            await t.tap(retry);
            await h.flush(t);
          }
          entry('Original thread')();
          await h.flush(t);
          final confirmedMuted = find
              .widgetWithText(ListTile, 'Unmute')
              .evaluate()
              .length;
          await t.pumpWidget(const SizedBox());
          await h.flush(t);
          expect(duplicateWrites, 1);
          expect(
            progress,
            shape == 'failed read' || shape == 'lost reply' ? 0 : 1,
          );
          if (shape == 'failed read') {
            expect(recoverable, 1);
            expect(unconfirmedMenu, 0);
          }
          if (shape == 'lost reply') expect(firstReads, 2);
          expect(confirmedMuted, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'PATCH') {
            writes++;
            final selected =
                r.url.pathSegments[r.url.pathSegments.length - 2] ==
                    'Other thread'
                ? otherFlags
                : flags;
            selected.addAll((jsonDecode(r.body) as Map).cast<String, bool>());
            if (shape == 'lost reply') {
              return h.json({'message': 'Synthetic lost reply'}, 503);
            }
            if (shape == 'pending read' || shape == 'failed read') {
              return h.json(selected);
            }
            return pending.future;
          }
          reads++;
          if (reads == 2 && shape == 'pending read') return read.future;
          if (reads == 2 && shape == 'failed read') {
            return h.json({'message': 'Synthetic read failed'}, 503);
          }
          return rows();
        },
      );
    });
  }
}

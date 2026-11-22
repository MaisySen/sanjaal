import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/main.dart' show buildTheme;

const items = [
  NavItem('Home', 'house', 'house-fill'),
  NavItem('Reels', 'play-circle', 'play-circle-fill'),
  NavItem('Chats', 'chat-circle', 'chat-circle-fill'),
  NavItem('Wallet', 'wallet', 'wallet-fill'),
  NavItem('Me', 'user-circle', 'user-circle-fill'),
];

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final compact in [false, true]) {
      for (final search in [false, true]) {
        testWidgets(
          'navigation targets retain 48 logical pixels at $width compact=$compact search=$search',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              t.view.physicalSize = Size(width, 640);
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.reset);
              final selected = <int>[];
              var searched = 0;
              await t.pumpWidget(
                MaterialApp(
                  theme: buildTheme(Brightness.light),
                  home: Scaffold(
                    bottomNavigationBar: GlassNavBar(
                      items: items,
                      index: 0,
                      compact: compact,
                      onSelected: selected.add,
                      onSearch: search ? () => searched++ : null,
                    ),
                  ),
                ),
              );
              await t.pumpAndSettle();
              await expectLater(t, meetsGuideline(androidTapTargetGuideline));
              Rect? previous;
              for (var i = 0; i < items.length; i++) {
                final control = find.byTooltip(items[i].label);
                final rect = t.getRect(control);
                expect(
                  rect.width,
                  greaterThanOrEqualTo(48),
                  reason: '${items[i].label} width',
                );
                expect(
                  rect.height,
                  greaterThanOrEqualTo(48),
                  reason: '${items[i].label} height',
                );
                if (previous != null) {
                  expect(
                    rect.left,
                    greaterThanOrEqualTo(previous.right - .000001),
                  );
                }
                previous = rect;
                await t.tapAt(rect.center);
                expect(selected.last, i);
              }
              expect(selected, [0, 1, 2, 3, 4]);
              if (search) {
                final rect = t.getRect(find.byTooltip('Search'));
                expect(rect.width, greaterThanOrEqualTo(48));
                expect(rect.height, greaterThanOrEqualTo(48));
                expect(
                  rect.left,
                  greaterThanOrEqualTo(previous!.right - .000001),
                );
                await t.tapAt(rect.center);
                expect(searched, 1);
              }
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}

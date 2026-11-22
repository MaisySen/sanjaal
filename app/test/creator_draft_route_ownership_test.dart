// Local synthetic drafts only. No post, account or external deletion.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:sanjaal/creator_drafts_page.dart';
import 'package:sanjaal/feed_page.dart';

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  const store = CreatorDraftStore();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('saved text draft opens once and reopens after Back', (t) async {
    await store.save('a', text: 'Local idea');
    final s = Session()..user = {'public_id': 'a'};
    final routes = Routes();
    await t.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: CreatorDraftsPage(session: s),
      ),
    );
    await t.pumpAndSettle();
    final open = t
        .widget<ListTile>(find.widgetWithText(ListTile, 'Local idea'))
        .onTap!;
    open();
    open();
    await t.pumpAndSettle();
    expect(routes.pushes, 2);
    expect(find.byType(ComposePage), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    final again = t
        .widget<ListTile>(find.widgetWithText(ListTile, 'Local idea'))
        .onTap!;
    again();
    await t.pumpAndSettle();
    expect(routes.pushes, 3);
    await t.pageBack();
    await t.pumpAndSettle();
    expect((await store.read('a')).single.text, 'Local idea');
  });
  testWidgets(
    'draft route rejects replacement Session object for same member',
    (t) async {
      await store.save('a', text: 'Private idea');
      final s = Session()..user = {'public_id': 'a'};
      final routes = Routes();
      await t.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: CreatorDraftsPage(session: s),
        ),
      );
      await t.pumpAndSettle();
      final old = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Private idea'))
          .onTap!;
      final replacement = Session()..user = {'public_id': 'a'};
      await t.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: CreatorDraftsPage(session: replacement),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Private idea'), findsNothing);
      old();
      await t.pumpAndSettle();
      expect(find.byType(ComposePage), findsNothing);
      expect(routes.pushes, 1);
      expect((await store.read('a')).single.text, 'Private idea');
    },
  );
  testWidgets(
    'retired draft callback never revives when original account returns',
    (t) async {
      await store.save('a', text: 'Private idea');
      final s = Session()..user = {'public_id': 'a'};
      await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: s)));
      await t.pumpAndSettle();
      final old = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Private idea'))
          .onTap!;
      s.user = {'public_id': 'b'};
      s.notifyListeners();
      await t.pump();
      s.user = {'public_id': 'a'};
      s.notifyListeners();
      await t.pump();
      old();
      await t.pumpAndSettle();
      expect(find.byType(ComposePage), findsNothing);
      expect(find.text('Private idea'), findsNothing);
      expect((await store.read('a')).single.text, 'Private idea');
    },
  );
  testWidgets(
    'old deletion confirmation stays retired when original account returns',
    (t) async {
      await store.save('a', text: 'Keep this idea');
      final s = Session()..user = {'public_id': 'a'};
      await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: s)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete draft'));
      await t.pumpAndSettle();
      s.user = {'public_id': 'b'};
      s.notifyListeners();
      await t.pump();
      s.user = {'public_id': 'a'};
      s.notifyListeners();
      await t.pump();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect((await store.read('a')).single.text, 'Keep this idea');
      expect(find.text('Keep this idea'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'disposed text draft callback is quiet and preserves stored copy',
    (t) async {
      await store.save('a', text: 'Local idea');
      final s = Session()..user = {'public_id': 'a'};
      await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: s)));
      await t.pumpAndSettle();
      final old = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Local idea'))
          .onTap!;
      await t.pumpWidget(const SizedBox());
      old();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect((await store.read('a')).single.text, 'Local idea');
    },
  );
}

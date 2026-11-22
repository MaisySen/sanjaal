// Synthetic route stacks and widget state only. No account, API or storage.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/draft_exit_guard.dart';

class DraftHarness {
  final nav = GlobalKey<NavigatorState>();
  final busy = ValueNotifier(false);
  final alive = ValueNotifier(true);
  final dirty = ValueNotifier(true);
  void dispose() {
    busy.dispose();
    alive.dispose();
    dirty.dispose();
  }

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('Root')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => const Scaffold(body: Text('Keep parent')),
      ),
    );
    await t.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => ValueListenableBuilder(
          valueListenable: alive,
          builder: (_, current, child) => current
              ? ListenableBuilder(
                  listenable: Listenable.merge([busy, dirty]),
                  builder: (_, child) => DraftExitGuard(
                    hasChanges: dirty.value,
                    busy: busy.value,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('Unsaved group plan')),
                      body: const Text('Retain this plan'),
                    ),
                  ),
                )
              : const Scaffold(body: Text('Retired draft owner')),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> ask(WidgetTester t) async {
    await nav.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Discard this draft?'), findsOneWidget);
  }

  VoidCallback choice(WidgetTester t, String label) =>
      t.widget<TextButton>(find.widgetWithText(TextButton, label)).onPressed!;
  void cover() {
    nav.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => const Scaffold(body: Text('Keep this cover')),
      ),
    );
  }
}

void main() {
  extraCases();
  deferredOwnerCase();
  for (final mode in ['Keep editing', 'Discard', 'result frame']) {
    testWidgets('guard preserves a cover during $mode and does not replay', (
      t,
    ) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      final old = h.choice(t, mode == 'result frame' ? 'Discard' : mode);
      if (mode == 'result frame') {
        old();
        await t.idle();
      }
      h.cover();
      if (mode != 'result frame') {
        await t.pumpAndSettle();
        old();
      }
      await t.pumpAndSettle();
      expect(find.text('Keep this cover'), findsOneWidget);
      h.nav.currentState!.pop();
      await t.pumpAndSettle();
      if (mode == 'result frame') {
        expect(find.text('Retain this plan'), findsOneWidget);
        await h.ask(t);
      } else {
        expect(find.text('Discard this draft?'), findsOneWidget);
      }
      h.choice(t, 'Keep editing')();
      await t.pumpAndSettle();
      expect(find.text('Retain this plan'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  for (final label in ['Keep editing', 'Discard']) {
    testWidgets('guard accepts $label only once', (t) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      final old = h.choice(t, label);
      old();
      old();
      await t.pumpAndSettle();
      expect(
        find.text(label == 'Discard' ? 'Keep parent' : 'Retain this plan'),
        findsOneWidget,
      );
      expect(find.text('Root'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  for (final when in ['before choice', 'result frame']) {
    testWidgets('busy $when prevents an accepted discard from leaving', (
      t,
    ) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      final old = h.choice(t, 'Discard');
      if (when == 'result frame') {
        old();
        await t.idle();
      }
      h.busy.value = true;
      await t.pump();
      if (when == 'before choice') {
        old();
      }
      await t.pumpAndSettle();
      expect(find.text('Retain this plan'), findsOneWidget);
      expect(find.text('Keep parent'), findsNothing);
      h.busy.value = false;
      await t.pumpAndSettle();
      await h.ask(t);
      h.choice(t, 'Keep editing')();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('retained blocked-Back callback cannot ask above a cover', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    final scope = t.widget<PopScope<dynamic>>(
      find.byWidgetPredicate((w) => w is PopScope<dynamic>),
    );
    final old = scope.onPopInvokedWithResult!;
    h.cover();
    await t.pumpAndSettle();
    old(false, null);
    await t.pumpAndSettle();
    expect(find.text('Keep this cover'), findsOneWidget);
    expect(find.text('Discard this draft?'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('retained choice after Keep cannot dismiss a later cover', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    await h.ask(t);
    final old = h.choice(t, 'Discard');
    h.choice(t, 'Keep editing')();
    await t.pumpAndSettle();
    h.cover();
    await t.pumpAndSettle();
    old();
    await t.pumpAndSettle();
    expect(find.text('Keep this cover'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'departing original route cannot also pop its parent after the result frame',
    (t) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      h.choice(t, 'Discard')();
      await t.idle();
      h.nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('Keep parent'), findsOneWidget);
      expect(find.text('Root'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final covered in [false, true]) {
    testWidgets(
      'retiring owner removes only its ${covered ? 'covered' : 'current'} confirmation',
      (t) async {
        final h = DraftHarness();
        addTearDown(h.dispose);
        await h.open(t);
        await h.ask(t);
        final old = h.choice(t, 'Discard');
        if (covered) {
          h.cover();
          await t.pumpAndSettle();
        }
        h.alive.value = false;
        await t.pumpAndSettle();
        expect(
          find.text('Discard this draft?', skipOffstage: false),
          findsNothing,
        );
        old();
        await t.pumpAndSettle();
        if (covered) {
          expect(find.text('Keep this cover'), findsOneWidget);
          h.nav.currentState!.pop();
          await t.pumpAndSettle();
        }
        expect(find.text('Discard this draft?'), findsNothing);
        expect(find.text('Retired draft owner'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}

void extraCases() {
  testWidgets('busy frame never publishes a discard bypass to another Back', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    await h.ask(t);
    h.choice(t, 'Discard')();
    await t.idle();
    h.busy.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      h.nav.currentState!.maybePop();
    });
    await t.pumpAndSettle();
    expect(find.text('Retain this plan'), findsOneWidget);
    h.busy.value = false;
    await t.pumpAndSettle();
    await h.ask(t);
    h.choice(t, 'Keep editing')();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  for (final first in ['Keep editing', 'Discard']) {
    testWidgets('$first wins over a conflicting second choice', (t) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      final keep = h.choice(t, 'Keep editing'), leave = h.choice(t, 'Discard');
      if (first == 'Discard') {
        leave();
        keep();
      } else {
        keep();
        leave();
      }
      await t.pumpAndSettle();
      expect(
        find.text(first == 'Discard' ? 'Keep parent' : 'Retain this plan'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'barrier dismissal retires its choice before the exit animation',
    (t) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.ask(t);
      final old = h.choice(t, 'Discard');
      h.nav.currentState!.pop();
      old();
      await t.pumpAndSettle();
      expect(find.text('Retain this plan'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('another blocked Back in the result frame cannot ask again', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    final old = t
        .widget<PopScope<dynamic>>(
          find.byWidgetPredicate((w) => w is PopScope<dynamic>),
        )
        .onPopInvokedWithResult!;
    await h.ask(t);
    h.choice(t, 'Discard')();
    await t.idle();
    old(false, null);
    await t.pumpAndSettle();
    expect(find.text('Keep parent'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('busy Back retains the original busy warning without a dialog', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    h.busy.value = true;
    await t.pumpAndSettle();
    await h.nav.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Retain this plan'), findsOneWidget);
    expect(find.text('Your upload is still in progress.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('untouched clean Back leaves without a discard dialog', (
    t,
  ) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    h.dirty.value = false;
    await t.pumpAndSettle();
    await h.nav.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Keep parent'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Keep after a clean update restores normal Back', (t) async {
    final h = DraftHarness();
    addTearDown(h.dispose);
    await h.open(t);
    await h.ask(t);
    h.dirty.value = false;
    await t.pumpAndSettle();
    h.choice(t, 'Keep editing')();
    await t.pumpAndSettle();
    expect(find.text('Retain this plan'), findsOneWidget);
    await h.nav.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Keep parent'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

void deferredOwnerCase() {
  testWidgets(
    'retirement before the dialog frame leaves no stale confirmation',
    (t) async {
      final h = DraftHarness();
      addTearDown(h.dispose);
      await h.open(t);
      await h.nav.currentState!.maybePop();
      h.alive.value = false;
      await t.pumpAndSettle();
      expect(
        find.text('Discard this draft?', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Retired draft owner'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}

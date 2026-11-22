// Offline settings search and route ownership fixtures. No live settings writes.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/appearance_settings_page.dart';
import 'package:sanjaal/notifications_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  testWidgets(
    'settings opens a destination once and releases its lock after Back',
    (t) async {
      await h.fixture(t, (s, c) async {
        final routes = Routes();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: SettingsPage(session: s),
          ),
        );
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'appearance');
        await t.pump();
        final open = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Appearance'))
            .onTap!;
        open();
        open();
        await t.pumpAndSettle();
        expect(routes.pushes, 2);
        expect(find.byType(AppearanceSettingsPage), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          'appearance',
        );
        open();
        await t.pumpAndSettle();
        expect(routes.pushes, 3);
        await t.pageBack();
        await t.pumpAndSettle();
      });
    },
  );
  testWidgets('notification Activity opens once and releases after Back', (
    t,
  ) async {
    await h.fixture(t, (s, c) async {
      final routes = Routes();
      await t.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: SettingsPage(session: s),
        ),
      );
      await h.flush(t);
      await t.enterText(find.byType(TextField), 'notifications');
      await t.pump();
      await t.tap(find.text('Notifications'));
      await t.pumpAndSettle();
      final open = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Activity'))
          .onTap!;
      open();
      open();
      await h.flush(t);
      await t.pumpAndSettle();
      expect(routes.pushes, 3);
      expect(find.byType(NotificationsPage), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      open();
      await h.flush(t);
      await t.pumpAndSettle();
      expect(routes.pushes, 4);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
    });
  });
  testWidgets(
    'retained settings destination callback rejects a replacement same-member login',
    (t) async {
      await h.fixture(t, (s, c) async {
        final routes = Routes();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: SettingsPage(session: s),
          ),
        );
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'appearance');
        await t.pump();
        final open = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Appearance'))
            .onTap!;
        await s.login('fixture', 'not-a-password');
        await h.flush(t);
        open();
        await t.pumpAndSettle();
        expect(routes.pushes, 1);
        expect(find.byType(AppearanceSettingsPage), findsNothing);
      });
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'localized settings search can recover no matches at narrow large text $lang',
      (t) async {
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await h.fixture(t, (s, c) async {
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('review'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(
                  lang == 'en' ? Brightness.light : Brightness.dark,
                  fontFamily: 'Roboto',
                  fontFamilyFallback: ['NotoDev'],
                ),
                builder: (context, w) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: w!,
                ),
                home: SettingsPage(session: s),
              ),
            ),
          );
          await h.flush(t);
          await t.enterText(find.byType(TextField), t_('Appearance'));
          await t.pump();
          expect(
            find.widgetWithText(ListTile, t_('Appearance')),
            findsOneWidget,
          );
          await t.enterText(find.byType(TextField), 'no-such-option');
          await t.pumpAndSettle();
          expect(find.text(t_('No matching settings')), findsOneWidget);
          expect(t.takeException(), isNull);
          await p.shot(t, 'settings_search_empty_$lang');
          await t.tap(find.byTooltip(t_('Clear search')));
          await t.pumpAndSettle();
          expect(
            t.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          expect(find.text(t_('No matching settings')), findsNothing);
          expect(find.text(t_('Edit profile')), findsOneWidget);
          expect(t.takeException(), isNull);
          await p.shot(t, 'settings_search_restored_$lang');
          await t.enterText(find.byType(TextField), '   ');
          await t.pump();
          expect(find.byTooltip(t_('Clear search')), findsOneWidget);
          await t.tap(find.byTooltip(t_('Clear search')));
          await t.pump();
          expect(
            t.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
        });
      },
    );
  }
}

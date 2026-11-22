// Synthetic profile PATCH/picker results and real editor routes only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;

class CountPicker extends ImagePickerPlatform {
  int starts = 0;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    starts++;
    return null;
  }
}

VoidCallback save(WidgetTester t) => t
    .widget<FilledButton>(find.widgetWithText(FilledButton, t_('Save')))
    .onPressed!;
VoidCallback avatar(WidgetTester t) => t
    .widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == t_('Change photo'),
      ),
    )
    .onPressed!;
Future<void> edit(WidgetTester t) async {
  await t.enterText(
    find.byKey(const ValueKey('profile-name')),
    'Submitted name',
  );
  await p.flush(t);
}

void pushCover(NavigatorState nav) {
  nav.push(
    MaterialPageRoute<bool>(
      builder: (_) => const Scaffold(body: Text('Keep profile cover')),
    ),
  );
}

Future<void> release(WidgetTester t, Completer<http.Response> response) async {
  response.complete(
    p.json({
      'user': {
        'public_id': 'me',
        'username': 'fixture',
        'name': 'Submitted name',
        'bio': 'Original bio',
      },
    }),
  );
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 25)),
  );
  await t.idle();
}

void main() {
  additionalCases();
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
  for (final action in ['Save', 'Change photo']) {
    testWidgets(
      'retained $action cannot start while profile editor is covered',
      (t) async {
        final oldPicker = ImagePickerPlatform.instance, picker = CountPicker();
        ImagePickerPlatform.instance = picker;
        addTearDown(() => ImagePickerPlatform.instance = oldPicker);
        var writes = 0;
        await p.fixture(
          t,
          (s) => EditProfilePage(session: s),
          () async {
            await edit(t);
            final old = action == 'Save' ? save(t) : avatar(t);
            pushCover(Navigator.of(t.element(find.byType(EditProfilePage))));
            await t.pumpAndSettle();
            old();
            await p.flush(t);
            expect(writes, 0);
            expect(picker.starts, 0);
            expect(find.text('Keep profile cover'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'PATCH') writes++;
            return p.json({
              'user': {'name': 'Submitted name'},
            });
          },
        );
      },
    );
  }
  for (final when in ['request', 'result frame']) {
    testWidgets('profile save preserves a cover introduced during $when', (
      t,
    ) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      await p.fixture(
        t,
        (s) => EditProfilePage(session: s),
        () async {
          await edit(t);
          final nav = Navigator.of(t.element(find.byType(EditProfilePage)));
          await t.tap(find.text(t_('Save')));
          await p.flush(t);
          if (when == 'request') {
            pushCover(nav);
            await t.pumpAndSettle();
          }
          await release(t, pending);
          if (when == 'result frame') pushCover(nav);
          await p.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Keep profile cover'), findsOneWidget);
          expect(writes, 1);
          expect(t.takeException(), isNull);
        },
        respond: (r) {
          writes++;
          return pending.future;
        },
      );
    });
  }
  for (final action in ['Save', 'Change photo']) {
    testWidgets(
      'accepted save keeps retained $action inert through its return frame',
      (t) async {
        final oldPicker = ImagePickerPlatform.instance, picker = CountPicker();
        ImagePickerPlatform.instance = picker;
        addTearDown(() => ImagePickerPlatform.instance = oldPicker);
        final pending = Completer<http.Response>();
        var writes = 0;
        await p.fixture(
          t,
          (s) => EditProfilePage(session: s),
          () async {
            await edit(t);
            final old = action == 'Save' ? save(t) : avatar(t);
            await t.tap(find.text(t_('Save')));
            await p.flush(t);
            await release(t, pending);
            old();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await t.idle();
            expect(writes, 1);
            expect(picker.starts, 0);
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(EditProfilePage), findsNothing);
            expect(find.text('Create fixture'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          respond: (r) {
            writes++;
            return pending.future;
          },
        );
      },
    );
  }
  for (final laterEdit in [false, true]) {
    final language = laterEdit ? 'ne' : 'en';
    testWidgets(
      'covered save baseline ${laterEdit ? 'protects a later edit' : 'allows clean Back'} $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final pending = Completer<http.Response>();
        var writes = 0;
        await p.fixture(
          t,
          (s) => EditProfilePage(session: s),
          () async {
            await edit(t);
            final nav = Navigator.of(t.element(find.byType(EditProfilePage)));
            await t.tap(find.text(t_('Save')));
            await p.flush(t);
            pushCover(nav);
            await t.pumpAndSettle();
            await release(t, pending);
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Keep profile cover'), findsOneWidget);
            nav.pop();
            await t.pumpAndSettle();
            expect(find.text('Submitted name'), findsOneWidget);
            await p.shot(t, 'profile_save_return_$language');
            if (laterEdit) {
              await t.ensureVisible(find.byKey(const ValueKey('profile-bio')));
              await t.enterText(
                find.byKey(const ValueKey('profile-bio')),
                'Later unsaved bio',
              );
              await p.flush(t);
            }
            await nav.maybePop();
            await t.pumpAndSettle();
            if (laterEdit) {
              expect(find.byType(AlertDialog), findsOneWidget);
              await t.tap(find.text(t_('Keep editing')));
              await t.pumpAndSettle();
              expect(find.text('Later unsaved bio'), findsOneWidget);
              await p.shot(t, 'profile_save_later_edit_$language');
            } else {
              expect(find.byType(EditProfilePage), findsNothing);
              expect(find.text('Create fixture'), findsOneWidget);
            }
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: laterEdit ? Brightness.dark : Brightness.light,
          scale: 1.8,
          respond: (r) {
            writes++;
            return pending.future;
          },
        );
      },
    );
  }
}

void additionalCases() {
  for (final leaving in [false, true]) {
    testWidgets(
      'accepted save does not discard ${leaving ? 'the route replacing its editor' : 'a queued later field change'}',
      (t) async {
        final pending = Completer<http.Response>();
        var writes = 0;
        await p.fixture(
          t,
          (s) => EditProfilePage(session: s),
          () async {
            await edit(t);
            final nav = Navigator.of(t.element(find.byType(EditProfilePage)));
            await t.tap(find.text(t_('Save')));
            await p.flush(t);
            await release(t, pending);
            if (leaving) {
              nav.pop();
              pushCover(nav);
            } else {
              t
                      .widget<TextFormField>(
                        find.byKey(const ValueKey('profile-name')),
                      )
                      .controller!
                      .text =
                  'Queued later name';
            }
            await p.flush(t);
            await t.pumpAndSettle();
            if (leaving) {
              expect(find.text('Keep profile cover'), findsOneWidget);
              nav.pop();
              await t.pumpAndSettle();
              expect(find.text('Create fixture'), findsOneWidget);
            } else {
              expect(find.byType(EditProfilePage), findsOneWidget);
              expect(find.text('Queued later name'), findsOneWidget);
              await nav.maybePop();
              await t.pumpAndSettle();
              expect(find.byType(AlertDialog), findsOneWidget);
              await t.tap(find.text(t_('Keep editing')));
              await t.pumpAndSettle();
              expect(find.text('Queued later name'), findsOneWidget);
            }
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (r) {
            writes++;
            return pending.future;
          },
        );
      },
    );
  }
}

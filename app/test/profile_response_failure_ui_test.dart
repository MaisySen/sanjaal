// Real editor widgets with synthetic HTTP and picker bytes. No live upload.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;

class FixturePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fixture.jpg');
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
  for (final lang in ['en', 'ne']) {
    for (final avatar in [false, true]) {
      for (final malformed in ['foreign', 'broken']) {
        testWidgets(
          '${avatar ? 'avatar' : 'profile'} $malformed failure preserves the editor and text draft in $lang',
          (t) async {
            t.view.physicalSize = const Size(320, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            final prior = ImagePickerPlatform.instance;
            ImagePickerPlatform.instance = FixturePicker();
            addTearDown(() => ImagePickerPlatform.instance = prior);
            late Session session;
            var writes = 0;
            late Map<String, dynamic> before;
            await p.fixture(
              t,
              (s) {
                session = s;
                before = Map<String, dynamic>.from(s.user!);
                return EditProfilePage(session: s);
              },
              () async {
                await t.enterText(
                  find.byKey(const ValueKey('profile-name')),
                  'Retained name',
                );
                if (avatar) {
                  final changePhoto = find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == t_('Change photo'),
                  );
                  await t.ensureVisible(changePhoto);
                  await t.tap(changePhoto);
                } else {
                  await t.tap(find.text(t_('Save')));
                }
                await p.flush(t);
                expect(writes, 1);
                expect(session.user, before);
                expect(find.byType(EditProfilePage), findsOneWidget);
                expect(find.text('Retained name'), findsOneWidget);
                expect(
                  find.text(
                    t_(
                      'Could not confirm the result. Check before trying again.',
                    ),
                  ),
                  findsOneWidget,
                );
                expect(
                  find.text(t_('Photo saved. Text changes still need Save.')),
                  findsNothing,
                );
                expect(
                  t
                      .widget<TextFormField>(
                        find.byKey(const ValueKey('profile-name')),
                      )
                      .enabled,
                  isTrue,
                );
                expect(
                  t
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, t_('Save')),
                      )
                      .onPressed,
                  isNotNull,
                );
                expect(t.takeException(), isNull);
                if (Platform.environment['PROFILE_RESPONSE_CAPTURE'] == '1') {
                  await p.shot(
                    t,
                    'profile_response_${avatar ? 'avatar' : 'text'}_${malformed}_$lang',
                  );
                }
                await t.pump(const Duration(seconds: 2));
                expect(writes, 1);
                await t.pageBack();
                await t.pumpAndSettle();
                expect(find.byType(AlertDialog), findsOneWidget);
                await t.tap(find.text(t_('Keep editing')));
                await t.pumpAndSettle();
                expect(find.text('Retained name'), findsOneWidget);
                expect(writes, 1);
                expect(session.user, before);
                expect(t.takeException(), isNull);
              },
              language: lang,
              brightness: lang == 'en' ? Brightness.light : Brightness.dark,
              scale: 1.8,
              respond: (r) async {
                writes++;
                return malformed == 'broken'
                    ? http.Response('{', 200)
                    : p.json({
                        'user': {
                          'public_id': 'other',
                          'username': 'other',
                          'name': 'Foreign fixture',
                        },
                      });
              },
            );
          },
        );
      }
    }
  }
}

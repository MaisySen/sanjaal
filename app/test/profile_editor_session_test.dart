// Synthetic account transitions only. Never calls production services.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/profile_pages.dart';

http.Response reply(Object body) => http.Response(jsonEncode(body), 200);
Future<void> flush(WidgetTester t) async { await t.pump(); await t.pump(const Duration(milliseconds: 400)); await t.pump(); }
class Picker extends ImagePickerPlatform {
  final result = Completer<XFile?>();
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) => result.future;
}
class DelayedFile extends XFile {
  DelayedFile() : super('private-fixture.jpg');
  final bytes = Completer<Uint8List>();
  bool reading = false;
  @override
  Future<Uint8List> readAsBytes() { reading = true; return bytes.future; }
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final same in [false, true]) {
    for (final stage in ['edited text', 'picker', 'file read', 'save response']) {
      testWidgets('profile editor retires $stage on ${same ? 'same' : 'other'} member login', (t) async {
        final previous = ImagePickerPlatform.instance;
        final picker = Picker(); ImagePickerPlatform.instance = picker;
        addTearDown(() => ImagePickerPlatform.instance = previous);
        final file = DelayedFile(), pending = Completer<http.Response>();
        String owner = 'a'; var writes = 0;
        await http.runWithClient(() async {
          final session = Session(); await session.login('fixture', 'not-a-password');
          await t.pumpWidget(MaterialApp(home: EditProfilePage(session: session)));
          await t.enterText(find.byKey(const ValueKey('profile-name')), 'Private unsaved name');
          if (stage == 'picker' || stage == 'file read') {
            await t.tap(find.byTooltip('Change photo')); await flush(t);
            if (stage == 'file read') { picker.result.complete(file); await flush(t); expect(file.reading, isTrue); }
          }
          if (stage == 'save response') { await t.tap(find.text('Save')); await flush(t); expect(writes, 1); }
          if (!same) owner = 'b';
          await session.login('replacement', 'not-a-password'); await flush(t);
          expect(find.textContaining('another signed-in session'), findsOneWidget);
          expect(find.byType(TextFormField), findsNothing);
          expect(find.text('Private unsaved name'), findsNothing);
          expect(find.byTooltip('Change photo'), findsNothing); expect(find.text('Save'), findsNothing);
          if (stage == 'picker') picker.result.complete(XFile.fromData(Uint8List.fromList([1,2,3]), name:'fixture.jpg'));
          if (stage == 'file read') file.bytes.complete(Uint8List.fromList([1,2,3]));
          if (stage == 'save response') pending.complete(reply({'user': {'name':'Old response', 'public_id':'a'}}));
          await flush(t);
          expect(writes, stage == 'save response' ? 1 : 0);
          expect(session.user?['public_id'], owner); expect(session.user?['name'], 'Current member');
          expect(find.textContaining('another signed-in session'), findsOneWidget);
          expect(find.textContaining('Photo saved'), findsNothing); expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }, () => MockClient((r) async {
          if (r.url.path.endsWith('/oauth/token')) return reply({'access_token':'fixture', 'expires_in':3600});
          if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) return reply({'user':{'public_id':owner,'username':owner*3,'name':'Current member','bio':'Private old bio'}});
          writes++; return r.method == 'PATCH' ? pending.future : reply({'user': {'name': 'Avatar result'}});
        }));
      });
    }
  }
  testWidgets('replacing Session object retires editor even for same member and epoch', (t) async {
    await http.runWithClient(() async {
      final first = Session(), second = Session();
      await first.login('fixture', 'not-a-password'); await second.login('fixture', 'not-a-password');
      expect(first.generation, second.generation);
      await t.pumpWidget(MaterialApp(home: EditProfilePage(session:first)));
      await t.enterText(find.byKey(const ValueKey('profile-bio')), 'Private draft');
      await t.pumpWidget(MaterialApp(home: EditProfilePage(session:second))); await flush(t);
      expect(find.textContaining('another signed-in session'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing); expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((r) async => r.url.path.endsWith('/oauth/token')
      ? reply({'access_token':'fixture','expires_in':3600})
      : reply({'user':{'public_id':'a','username':'aaa','name':'Current member'}})));
  });
}

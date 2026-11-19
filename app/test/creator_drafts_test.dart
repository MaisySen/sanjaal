// Storage-plugin mock and fixture widgets. Not native encrypted-storage/device
// restore proof. No real account or external publication is used.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:sanjaal/creator_drafts_page.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:sanjaal/main.dart' show buildTheme;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = CreatorDraftStore();
  setUp(() => prefs.lang = 'en');
  test(
    'save restores exact text and incomplete poll after new store instance',
    () async {
      final d = await store.save(
        'owner-a',
        text: 'My caption\nनमस्ते',
        options: ['Saturday', ''],
      );
      final read = await const CreatorDraftStore().read('owner-a');
      expect(read.single.toJson(), d.toJson());
      expect(read.single.options, ['Saturday', '']);
      expect(
        read.single.toJson().keys,
        unorderedEquals(['id', 'text', 'saved_at', 'revision', 'options']),
      );
    },
  );
  test('another account cannot see or overwrite this key', () async {
    await store.save('a', text: 'Private text');
    expect(await store.read('b'), isEmpty);
    await store.save('b', text: 'Different');
    expect((await store.read('a')).single.text, 'Private text');
  });
  test(
    'update keeps draft identity and replaces only own saved copy',
    () async {
      final one = await store.save('a', text: 'First');
      await store.save('a', text: 'Other');
      await store.save(
        'a',
        id: one.id,
        expectedRevision: one.revision,
        text: 'Edited',
      );
      final list = await store.read('a');
      expect(list.length, 2);
      expect(list.first.id, one.id);
      expect(list.first.text, 'Edited');
    },
  );
  test('concurrent saves serialize without dropping another draft', () async {
    await Future.wait(
      List.generate(6, (i) => store.save('a', text: 'Draft$i')),
    );
    expect((await store.read('a')).length, 6);
  });
  test('eight draft cap refuses growth but allows editing', () async {
    final list = await Future.wait(
      List.generate(8, (i) => store.save('a', text: 'Draft$i')),
    );
    await expectLater(store.save('a', text: 'Ninth'), throwsStateError);
    expect((await store.read('a')).length, 8);
    await store.save(
      'a',
      id: list.first.id,
      expectedRevision: list.first.revision,
      text: 'Edited',
    );
    expect((await store.read('a')).length, 8);
  });
  test(
    'removed draft cannot be silently resurrected by stale editor',
    () async {
      final d = await store.save('a', text: 'Delete');
      await store.remove('a', d.id, expectedRevision: d.revision);
      await expectLater(
        store.save('a', id: d.id, text: 'Stale'),
        throwsStateError,
      );
      expect(await store.read('a'), isEmpty);
    },
  );
  test('stale editor cannot overwrite a newer saved revision', () async {
    final d = await store.save('a', text: 'Original');
    await store.save(
      'a',
      id: d.id,
      expectedRevision: d.revision,
      text: 'Newer',
    );
    await expectLater(
      store.save('a', id: d.id, expectedRevision: d.revision, text: 'Stale'),
      throwsStateError,
    );
    expect((await store.read('a')).single.text, 'Newer');
  });
  test('stale delete cannot erase a newer revision', () async {
    final original = await store.save('a', text: 'Original');
    final newer = await store.save('a', id: original.id,
      expectedRevision: original.revision, text: 'Newer work');
    await expectLater(store.remove('a', original.id,
      expectedRevision: original.revision), throwsStateError);
    expect((await store.read('a')).single.toJson(), newer.toJson());
    await store.remove('a', newer.id, expectedRevision: newer.revision);
    expect(await store.read('a'), isEmpty);
  });
  test('queued edit settles before stale delete without losing text', () async {
    final original = await store.save('a', text: 'Original');
    final edit = store.save('a', id: original.id,
      expectedRevision: original.revision, text: 'Edited while dialog open');
    final deletion = store.remove('a', original.id,
      expectedRevision: original.revision);
    await expectLater(deletion, throwsStateError);
    final newer = await edit;
    expect((await store.read('a')).single.toJson(), newer.toJson());
  });
  test('malformed data fails closed without replacing it', () async {
    final key = 'creator_text_drafts_v1_${sha256.convert(utf8.encode('a'))}';
    FlutterSecureStorage.setMockInitialValues({key: 'unrecognized bytes'});
    await expectLater(
      store.save('a', text: 'Do not overwrite'),
      throwsFormatException,
    );
    expect(
      await const FlutterSecureStorage().read(key: key),
      'unrecognized bytes',
    );
  });
  test('schema rejects unbounded text and invalid poll length', () async {
    await expectLater(store.save('a', text: 'x' * 2001), throwsFormatException);
    await expectLater(
      store.save('a', text: 'Question', options: ['Only one']),
      throwsFormatException,
    );
    await expectLater(store.save('a', text: ''), throwsArgumentError);
    expect(await store.read('a'), isEmpty);
  });
  test('deletion is account-local and leaves other drafts', () async {
    final d = await store.save('a', text: 'One');
    await store.save('a', text: 'Two');
    await store.save('b', text: 'Three');
    await store.remove('a', d.id, expectedRevision: d.revision);
    expect((await store.read('a')).single.text, 'Two');
    expect((await store.read('b')).single.text, 'Three');
  });
  testWidgets('explicit save and reopen preserve text without publishing', (
    t,
  ) async {
    final session = Session()..user = {'public_id': 'a'};
    await t.pumpWidget(MaterialApp(home: ComposePage(session: session)));
    await t.enterText(find.byType(TextField), 'A local caption');
    await t.tap(find.byTooltip('Save text draft'));
    await t.pumpAndSettle();
    expect((await store.read('a')).single.text, 'A local caption');
    expect(find.textContaining('Nothing was posted.'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: session)));
    await t.pumpAndSettle();
    await t.tap(find.text('A local caption'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'A local caption'), findsOneWidget);
    expect(find.textContaining('Posting is manual.'), findsOneWidget);
  });
  testWidgets(
    'delete requires confirmation and never deletes published content',
    (t) async {
      final session = Session()..user = {'public_id': 'a'};
      await store.save('a', text: 'Saved idea');
      await t.pumpWidget(
        MaterialApp(home: CreatorDraftsPage(session: session)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete draft'));
      await t.pumpAndSettle();
      expect((await store.read('a')).length, 1);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(await store.read('a'), isEmpty);
      expect(find.textContaining('No saved drafts'), findsOneWidget);
    },
  );
  testWidgets('delete confirmation cannot erase edits made while it was open', (t) async {
    final session = Session()..user = {'public_id': 'a'};
    final original = await store.save('a', text: 'Original idea');
    await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: session)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Delete draft'));
    await t.pumpAndSettle();
    final newer = await store.save('a', id: original.id,
      expectedRevision: original.revision, text: 'Important newer idea');
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect((await store.read('a')).single.toJson(), newer.toJson());
    expect(find.textContaining('Reopen the saved copy before deleting it.'), findsOneWidget);
    expect(find.text('Important newer idea'), findsOneWidget);
    expect(find.text('Original idea'), findsNothing);
  });
  testWidgets('account change hides old local drafts immediately', (t) async {
    final session = Session()..user = {'public_id': 'a'};
    await store.save('a', text: 'Private idea');
    await t.pumpWidget(MaterialApp(home: CreatorDraftsPage(session: session)));
    await t.pumpAndSettle();
    expect(find.text('Private idea'), findsOneWidget);
    session.user = {'public_id': 'b'};
    session.setOffline(true);
    await t.pump();
    expect(find.text('Private idea'), findsNothing);
    expect(find.textContaining('Sign in again'), findsOneWidget);
  });
  testWidgets('restored poll respects server capability before publishing', (
    t,
  ) async {
    final session = Session()..user = {'public_id': 'a'};
    final d = await store.save('a', text: 'Question', options: ['One', 'Two']);
    await t.pumpWidget(
      MaterialApp(
        home: ComposePage(session: session, initialLocalDraft: d),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    await t.tap(find.text('Post'));
    await t.pump();
    expect(find.textContaining('Polls are not available'), findsOneWidget);
  });
  testWidgets(
    'account switch hides a restored editor and prevents wrong-account posting',
    (t) async {
      final session = Session()..user = {'public_id': 'a'};
      final d = await store.save('a', text: 'Private caption');
      await t.pumpWidget(
        MaterialApp(
          home: ComposePage(session: session, initialLocalDraft: d),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Private caption'), findsOneWidget);
      session.user = {'public_id': 'b'};
      session.setOffline(true);
      await t.pump();
      expect(find.text('Private caption'), findsNothing);
      expect(find.textContaining('another signed-in session'), findsOneWidget);
      expect(find.text('Post'), findsNothing);
    },
  );
  for (final language in ['en', 'ne']) {
    for (final brightness in Brightness.values) {
      testWidgets('saved draft list render ${brightness.name} $language', (
        t,
      ) async {
        final root = Platform.environment['FLUTTER_ROOT'] ?? '';
        final f = File(
          '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        if (f.existsSync()) {
          final loader = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
          await loader.load();
        }
        prefs.lang = language;
        final ne = File('assets/fonts/NotoSansDevanagari.ttf');
        final neLoader = FontLoader('NotoDev')
          ..addFont(Future.value(ByteData.sublistView(ne.readAsBytesSync())));
        await neLoader.load();
        final session = Session()..user = {'public_id': 'a'};
        await store.save(
          'a',
          text: 'A thought for our next community meetup',
          options: ['Saturday afternoon', 'Sunday morning'],
        );
        t.view.physicalSize = const Size(960, 1920);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                brightness,
                fontFamily: 'Roboto',
                fontFamilyFallback: ['NotoDev'],
              ),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: Column(
                  children: [
                    Expanded(child: w!),
                    Container(
                      width: double.infinity,
                      color: const Color(0xff444444),
                      padding: const EdgeInsets.all(3),
                      child: const Text(
                        'SYNTHETIC LOCAL DRAFT - NOT DEVICE PROOF',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                          fontSize: 10,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              home: CreatorDraftsPage(session: session),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('test/renders').createSync(recursive: true);
          File('test/renders/saved_drafts_${brightness.name}_$language.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        final original = (await store.read('a')).single;
        await t.tap(find.byTooltip(t_('Delete draft')));
        await t.pumpAndSettle();
        await store.save('a', id: original.id, expectedRevision: original.revision,
          text: 'Newer saved thought', options: ['Saturday', 'Sunday']);
        await t.tap(find.text(t_('Delete')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Newer saved thought'), findsOneWidget);
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()!
            as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('test/renders/saved_drafts_conflict_${brightness.name}_$language.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}

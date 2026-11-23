// Real chat routes, secure-storage mock, no live messages.
import 'dart:io';
import 'dart:async';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// Test-only platform fault injection, supplied by secure-storage dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_text_draft_store.dart';

import 'chat_exit_continuity_test.dart' as h;

class HeldStorage extends TestFlutterSecureStoragePlatform {
  HeldStorage() : super({});
  Completer<void>? hold;
  bool loseWrite = false,
      failRead = false,
      throwAfterWrite = false,
      loseDelete = false;
  int writes = 0;
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writes++;
    if (hold != null) await hold!.future;
    if (loseWrite) return;
    await super.write(key: key, value: value, options: options);
    if (throwAfterWrite) throw StateError('Synthetic lost acknowledgement');
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (loseDelete) return;
    await super.delete(key: key, options: options);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failRead) throw StateError('Synthetic read unavailable');
    return super.read(key: key, options: options);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
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
    for (final dark in [false, true]) {
      testWidgets('saved chat text narrow large $lang $dark', (t) async {
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await const ChatTextDraftStore().save(
          'me',
          'chat',
          'Synthetic saved text',
        );
        final session = h.ExitSession();
        await h.open(
          t,
          session,
          brightness: dark ? Brightness.dark : Brightness.light,
          scale: 1.8,
        );
        await t.pumpAndSettle();
        expect(find.text(t_('Saved text')), findsOneWidget);
        await t.ensureVisible(find.text(t_('Saved text')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('exit-shot')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('test/renders').createSync(recursive: true);
          File(
            'test/renders/chat_saved_text_${lang}_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        await t.tap(find.text(t_('Saved text')));
        await h.settle(t);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('exit-shot')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'test/renders/chat_saved_dialog_${lang}_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        await t.ensureVisible(find.widgetWithText(TextButton, t_('Cancel')));
        await h.settle(t);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('exit-shot')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'test/renders/chat_saved_actions_${lang}_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        await t.tap(find.text(t_('Cancel')));
        await h.settle(t);
        t.view.viewInsets = FakeViewPadding(bottom: 280);
        await h.settle(t);
        await t.enterText(find.byType(TextField), 'Synthetic keyboard text');
        await h.settle(t);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('exit-shot')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'test/renders/chat_saved_keyboard_${lang}_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
  for (final otherAccount in [false, true]) {
    testWidgets('held save retires safely on session change $otherAccount', (
      t,
    ) async {
      final storage = HeldStorage()..hold = Completer<void>();
      FlutterSecureStoragePlatform.instance = storage;
      final session = h.ExitSession();
      await h.open(t, session);
      await h.settle(t);
      await t.enterText(find.byType(TextField), 'Private old-session text');
      await h.settle(t);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      expect(storage.writes, 1);
      await t.pageBack();
      await h.settle(t);
      expect(find.text('Conversation list'), findsNothing);
      expect(session.sends, 0);
      session.epoch++;
      if (otherAccount) session.user = {'public_id': 'other'};
      session.notifyListeners();
      await h.settle(t);
      storage.hold!.complete();
      await h.settle(t);
      expect(find.text('Private old-session text'), findsNothing);
      expect(find.text('Saved text'), findsNothing);
      expect(
        (await const ChatTextDraftStore().read('me', 'chat'))!.text,
        'Private old-session text',
      );
      expect(await const ChatTextDraftStore().read('other', 'chat'), isNull);
      expect(session.sends, 0);
    });
  }
  testWidgets(
    'covered route receives completed saved copy without navigation or sending',
    (t) async {
      final storage = HeldStorage()..hold = Completer<void>();
      FlutterSecureStoragePlatform.instance = storage;
      final session = h.ExitSession();
      await h.open(t, session);
      await h.settle(t);
      await t.enterText(find.byType(TextField), 'Saved while covered');
      await h.settle(t);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      final nav = Navigator.of(t.element(find.byType(TextField)));
      nav.push(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Cover'))),
      );
      await h.settle(t);
      storage.hold!.complete();
      await h.settle(t);
      expect(find.text('Cover'), findsOneWidget);
      expect(session.sends, 0);
      nav.pop();
      await h.settle(t);
      expect(find.text('Saved text'), findsOneWidget);
      expect(find.text('Saved while covered'), findsOneWidget);
    },
  );
  testWidgets('disposed route save completes only into old account storage', (
    t,
  ) async {
    final storage = HeldStorage()..hold = Completer<void>();
    FlutterSecureStoragePlatform.instance = storage;
    final session = h.ExitSession();
    await h.open(t, session);
    await h.settle(t);
    await t.enterText(find.byType(TextField), 'Old route text');
    await h.settle(t);
    await t.tap(find.text('Save chat text'));
    await h.settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    storage.hold!.complete();
    await h.settle(t);
    expect(t.takeException(), isNull);
    expect(
      (await const ChatTextDraftStore().read('me', 'chat'))!.text,
      'Old route text',
    );
    expect(session.sends, 0);
  });
  testWidgets(
    'persisted write with lost acknowledgement requires read before replacement',
    (t) async {
      final storage = HeldStorage()..throwAfterWrite = true;
      FlutterSecureStoragePlatform.instance = storage;
      final session = h.ExitSession();
      await h.open(t, session);
      await h.settle(t);
      await t.enterText(find.byType(TextField), 'Saved despite lost reply');
      await h.settle(t);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Saved despite lost reply'), findsOneWidget);
      expect(storage.writes, 1);
      storage.throwAfterWrite = false;
      await t.tap(find.text('Try again'));
      await h.settle(t);
      expect(find.text('Saved text'), findsOneWidget);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      expect(storage.writes, 2);
      expect(session.sends, 0);
    },
  );
  testWidgets('lost removal keeps copy behind explicit read recovery', (
    t,
  ) async {
    final storage = HeldStorage();
    FlutterSecureStoragePlatform.instance = storage;
    await const ChatTextDraftStore().save('me', 'chat', 'Original copy');
    storage.loseDelete = true;
    final session = h.ExitSession();
    await h.open(t, session);
    await h.settle(t);
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    await t.tap(find.text('Remove saved copy'));
    await h.settle(t);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      t
          .widget<TextButton>(find.widgetWithText(TextButton, 'Saved text'))
          .onPressed,
      isNull,
    );
    storage.loseDelete = false;
    await t.tap(find.text('Try again'));
    await h.settle(t);
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    await t.tap(find.text('Remove saved copy'));
    await h.settle(t);
    expect(find.text('Saved text'), findsNothing);
    expect(session.sends, 0);
  });
  testWidgets(
    'storage write loss preserves composer and requires read reconciliation',
    (t) async {
      final storage = HeldStorage()..loseWrite = true;
      FlutterSecureStoragePlatform.instance = storage;
      final session = h.ExitSession();
      await h.open(t, session);
      await h.settle(t);
      await t.enterText(find.byType(TextField), 'Keep current text');
      await h.settle(t);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      expect(find.text('Keep current text'), findsOneWidget);
      expect(find.text('Saved text'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      storage.loseWrite = false;
      await t.tap(find.text('Try again'));
      await h.settle(t);
      await t.tap(find.text('Save chat text'));
      await h.settle(t);
      expect(find.text('Saved text'), findsOneWidget);
      expect(session.sends, 0);
    },
  );
  testWidgets(
    'unreadable storage cannot be overwritten and retry is explicit',
    (t) async {
      final storage = HeldStorage();
      FlutterSecureStoragePlatform.instance = storage;
      await const ChatTextDraftStore().save('me', 'chat', 'Existing copy');
      storage.failRead = true;
      final session = h.ExitSession();
      await h.open(t, session);
      await h.settle(t);
      await t.enterText(find.byType(TextField), 'New text');
      await h.settle(t);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Save chat text'),
            )
            .onPressed,
        isNull,
      );
      storage.failRead = false;
      await t.tap(find.text('Try again'));
      await h.settle(t);
      expect(find.text('Saved text'), findsOneWidget);
      expect(find.text('Existing copy'), findsNothing);
      expect(find.text('New text'), findsOneWidget);
      expect(session.sends, 0);
    },
  );
  testWidgets('saved text does not displace a selected reply', (t) async {
    await const ChatTextDraftStore().save('me', 'chat', 'Saved synthetic');
    final session = h.ExitSession();
    await h.open(t, session);
    await h.settle(t);
    await t.longPress(find.text('Original question'));
    await h.settle(t);
    await t.tap(find.text('Reply'));
    await h.settle(t);
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    expect(
      t
          .widget<TextButton>(find.widgetWithText(TextButton, 'Restore text'))
          .onPressed,
      isNull,
    );
    await t.tap(find.text('Cancel'));
    await h.settle(t);
    expect(find.textContaining('Replying to'), findsOneWidget);
    expect(session.sends, 0);
  });
  testWidgets('account retirement closes saved-text dialog without restoring', (
    t,
  ) async {
    await const ChatTextDraftStore().save('me', 'chat', 'Saved synthetic');
    final session = h.ExitSession();
    await h.open(t, session);
    await t.pumpAndSettle();
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    session.epoch++;
    session.notifyListeners();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Saved synthetic'), findsNothing);
    expect(session.sends, 0);
  });
  testWidgets(
    'retained saved-text restore callback cannot pop covering route',
    (t) async {
      await const ChatTextDraftStore().save('me', 'chat', 'Saved synthetic');
      final session = h.ExitSession();
      await h.open(t, session);
      await t.pumpAndSettle();
      await t.tap(find.text('Saved text'));
      await h.settle(t);
      final restore = t
          .widget<TextButton>(find.widgetWithText(TextButton, 'Restore text'))
          .onPressed!;
      Navigator.of(t.element(find.byType(AlertDialog))).push(
        MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Text('Covering synthetic route')),
        ),
      );
      await h.settle(t);
      restore();
      await h.settle(t);
      expect(find.text('Covering synthetic route'), findsOneWidget);
      expect(session.sends, 0);
    },
  );
  testWidgets(
    'saved text copy is not an outbox and sending never resends it automatically',
    (t) async {
      await const ChatTextDraftStore().save('me', 'chat', 'Saved copy');
      final session = h.ExitSession();
      await h.open(t, session);
      await t.pumpAndSettle();
      expect(session.sends, 0);
      await t.tap(find.text('Saved text'));
      await h.settle(t);
      await t.tap(find.text('Restore text'));
      await h.settle(t);
      await t.tap(find.byTooltip('Send message'));
      await h.settle(t);
      expect(session.sends, 1);
      expect(
        (await const ChatTextDraftStore().read('me', 'chat'))!.text,
        'Saved copy',
      );
      session.close();
      await h.settle(t);
      expect(session.sends, 1);
    },
  );
  testWidgets('save explicit text, leave, reopen and restore without send', (
    t,
  ) async {
    final s = h.ExitSession();
    await h.open(t, s);
    await t.enterText(find.byType(TextField), 'Private synthetic text');
    await h.settle(t);
    await t.tap(find.text('Save chat text'));
    await t.pumpAndSettle();
    expect(
      (await const ChatTextDraftStore().read('me', 'chat'))!.text,
      'Private synthetic text',
    );
    expect(s.sends, 0);
    await t.pageBack();
    await h.settle(t);
    await t.tap(find.text('Leave'));
    await h.settle(t);
    final second = h.ExitSession();
    await h.open(t, second);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Saved text'), findsOneWidget);
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    await t.tap(find.text('Restore text'));
    await h.settle(t);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Private synthetic text',
    );
    expect(second.sends, 0);
    await t.tap(find.text('Saved text'));
    await h.settle(t);
    await t.tap(find.text('Remove saved copy'));
    await t.pumpAndSettle();
    expect(await const ChatTextDraftStore().read('me', 'chat'), isNull);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Private synthetic text',
    );
  });
  testWidgets(
    'restoring over current text requires confirmation and cancel retains it',
    (t) async {
      await const ChatTextDraftStore().save('me', 'chat', 'Saved synthetic');
      final s = h.ExitSession();
      await h.open(t, s);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Current synthetic');
      await h.settle(t);
      await t.tap(find.text('Saved text'));
      await h.settle(t);
      await t.tap(find.text('Restore text'));
      await h.settle(t);
      expect(find.text('Replace unsent text?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await h.settle(t);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Current synthetic',
      );
      expect(s.sends, 0);
      await t.tap(find.text('Saved text'));
      await h.settle(t);
      await t.tap(find.text('Restore text'));
      await h.settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Restore text').last);
      await h.settle(t);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saved synthetic',
      );
      expect(s.sends, 0);
    },
  );
}

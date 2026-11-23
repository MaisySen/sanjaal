// Harness contract only: mocked secure storage, API and keyboard. Not native proof.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_text_draft_store.dart';
import 'package:sanjaal/ui.dart' show prefs;

import '../integration_test/native_chat_text_restart.dart';

class RestartSession extends Session {
  RestartSession() {
    user = {'public_id': 'native-copy-owner', 'username': 'synthetic'};
  }
  final poll = Completer<dynamic>();
  int writes = 0;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'GET') {
      if (query?.containsKey('after_seq') == true) return poll.future;
      return {'data': <dynamic>[]};
    }
    if (path.endsWith('/messages')) writes++;
    return {};
  }

  void close() {
    if (!poll.isCompleted) poll.complete({'data': []});
  }
}

void main() {
  testWidgets(
    'combined helper seeds then recovers only after explicit restore without sending',
    (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      prefs.lang = 'en';
      final directory = Directory.systemTemp.createTempSync(
        'chat-restart-contract-',
      );
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => directory.path,
      );
      t.view.physicalSize = const Size(402, 874);
      t.view.devicePixelRatio = 1;
      final sessions = <RestartSession>[];
      final captures = <String>[];
      addTearDown(() async {
        for (final s in sessions) {
          s.close();
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 3));
        t.view.reset();
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      Future<void> waitUntil(bool Function() ready) async {
        for (var i = 0; i < 60; i++) {
          await t.pump(const Duration(milliseconds: 100));
          final focused = find
              .byType(EditableText)
              .evaluate()
              .any((e) => (e.widget as EditableText).focusNode.hasFocus);
          t.view.viewInsets = FakeViewPadding(bottom: focused ? 250 : 0);
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await t.pump();
          if (ready()) return;
        }
        throw TestFailure('Synthetic helper did not settle');
      }

      for (final recover in [false, true]) {
        final session = RestartSession();
        sessions.add(session);
        await nativeChatTextRestartJourney(
          t,
          session,
          recover: recover,
          conversation: recover
              ? null
              : {
                  'public_id': 'native-copy-chat',
                  'title': 'Synthetic saved text',
                  'type': 'direct',
                },
          waitUntil: waitUntil,
          capture: (name) async {
            captures.add(name);
            if (name == 'ios_chat_text_restart_no_autofill') {
              expect(
                t.widget<TextField>(find.byType(TextField)).controller!.text,
                isEmpty,
              );
            }
          },
          stage: (_) async {},
        );
        expect(session.writes, 0);
        await t.pumpWidget(const SizedBox());
        session.close();
        await t.pump(const Duration(seconds: 3));
      }
      expect(captures, [
        'ios_chat_text_full_width_native_keyboard',
        'ios_chat_text_saved_before_restart',
        'ios_chat_text_restart_no_autofill',
        'ios_chat_text_restart_explicit_restore',
      ]);
      expect(
        File('${directory.path}/chat-text-restart-identity.json').existsSync(),
        isFalse,
      );
      expect(
        await const ChatTextDraftStore().read(
          'native-copy-owner',
          'native-copy-chat',
        ),
        isNull,
      );
    },
    skip:
        const String.fromEnvironment('E2E_TOKEN_BASE') !=
        'http://localhost:8002',
  );
}

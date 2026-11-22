import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../integration_test/native_text_input.dart';

void main() {
  for (final confirmed in [false, true]) {
    testWidgets('unregistered native keyboard refocus confirmed=$confirmed', (
      t,
    ) async {
      final controller = TextEditingController();
      var keyboard = false;
      // Integration binding does not register the test IME. Its native hide
      // therefore cannot invoke the mock's binding focus-cache reset callback.
      t.testTextInput.unregister();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          if (call.method == 'TextInput.show') keyboard = true;
          if (call.method == 'TextInput.hide' ||
              call.method == 'TextInput.clearClient') {
            keyboard = false;
          }
          return null;
        },
      );
      addTearDown(() {
        t.testTextInput.register();
        t.view.reset();
        controller.dispose();
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );
      final field = find.byType(TextField);
      Future<void> waitUntil(bool Function() ready) async {
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
          t.view.viewInsets = FakeViewPadding(bottom: keyboard ? 250 : 0);
          await t.pump();
          if (ready()) return;
        }
        throw TestFailure('Fixture native focus or keyboard did not settle');
      }

      Future<void> enter(String text) async {
        if (confirmed) {
          await confirmedNativeTextInput(
            t,
            field,
            text,
            waitUntil: waitUntil,
            stage: (_) async {},
            label: 'member',
          );
        } else {
          await t.enterText(field, text);
        }
      }

      try {
        await enter('asha_e2e');
        expect(controller.text, 'asha_e2e');
        FocusManager.instance.primaryFocus!.unfocus();
        await waitUntil(() => !keyboard);
        expect(
          t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
          isFalse,
        );
        await enter('bikram_e2e');
        expect(
          controller.text,
          confirmed ? 'bikram_e2e' : 'asha_e2e',
          reason: 'The old enterText-only path silently retains the first member after native hide',
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
      }
    });
  }

  testWidgets('native fixture input rejects a value overwritten after entry', (
    t,
  ) async {
    final controller = TextEditingController();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    final field = find.byType(TextField);
    var injected = false;
    controller.addListener(() {
      if (controller.text == 'bikram_e2e' && !injected) {
        injected = true;
        Future<void>.delayed(
          const Duration(milliseconds: 100),
          () => controller.text = 'asha_e2e',
        );
      }
    });
    try {
      await expectLater(
        confirmedNativeTextInput(
          t,
          field,
          'bikram_e2e',
          waitUntil: (ready) async {
            t.view.viewInsets = const FakeViewPadding(bottom: 250);
            await t.pump();
            expect(ready(), isTrue);
          },
          stage: (_) async {},
          label: 'member',
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(controller.text, 'asha_e2e');
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      t.view.reset();
      controller.dispose();
    }
  });
}

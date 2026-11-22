// Native fixture input. This is test injection, not physical typing proof.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> confirmedNativeTextInput(
  WidgetTester tester,
  Finder field,
  String value, {
  required Future<void> Function(bool Function()) waitUntil,
  required Future<void> Function(String) stage,
  required String label,
}) async {
  await tester.ensureVisible(field);
  await tester.pump(const Duration(milliseconds: 400));
  expect(field.hitTestable(), findsOneWidget);
  // showKeyboard/enterText caches the EditableTextState. A native hide does
  // not clear that cache as the registered test keyboard does. Tap to create
  // an actual focus/IME connection when returning to the same field.
  await tester.tap(field);
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  await waitUntil(
    () =>
        tester.widget<EditableText>(editable).focusNode.hasFocus &&
        tester.view.viewInsets.bottom > 0,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.enterText(field, value);
  expect(
    tester.widget<EditableText>(editable).controller.text,
    value,
    reason: '$label must receive the injected native fixture value',
  );
  await tester.pump(const Duration(milliseconds: 600));
  expect(
    tester.widget<EditableText>(editable).controller.text,
    value,
    reason: '$label must retain the value after native presentation',
  );
  await stage('native input confirmed $label length=${value.length}');
}

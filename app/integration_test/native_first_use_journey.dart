// Native first-use navigation, input and validation pixels only.
// No sign-up, sign-in or password-reset request is submitted to a provider.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart' show EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/password_recovery_page.dart';

Future<Session> nativeFirstUseJourney(
  WidgetTester t, {
  required Future<void> Function(bool Function()) waitUntil,
  required Future<void> Function(String) capture,
  required Future<void> Function(String) stage,
}) async {
  // A duration before one pump does not present a just-created opacity or
  // theme animation. Finish framework presentation before native capture.
  Future<void> present() async {
    await t.pump();
    await t.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  Future<void> picture(String name) async {
    await present();
    await capture(name);
  }

  await stage('native first-use introduction and safe input validation');
  await waitUntil(
    () => find.text('Share with your community').evaluate().isNotEmpty,
  );
  await t.pump(const Duration(milliseconds: 600));
  await picture('ios_first_use_intro');
  await t.tap(find.text('Create an account'));
  await waitUntil(
    () =>
        find.byType(AuthPage).evaluate().isNotEmpty &&
        find.byType(TextFormField).evaluate().length == 3,
  );
  final session = t.widget<AuthPage>(find.byType(AuthPage)).session;
  expect(session.user, isNull);
  final fields = find.byType(TextFormField);
  await t.tap(fields.first);
  await waitUntil(() => t.view.viewInsets.bottom > 0);
  await t.pump(const Duration(milliseconds: 600));
  await picture('ios_first_use_native_keyboard');
  await t.enterText(fields.at(0), 'invalid');
  await t.enterText(fields.at(1), 'x');
  await t.enterText(fields.at(2), 'short');
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  // Exercise the actual form's validators without submitting provider work.
  expect(t.state<FormState>(find.byType(Form)).validate(), isFalse);
  await present();
  expect(find.text('Enter a valid email'), findsOneWidget);
  expect(
    find.text('Use 3 to 30 letters, numbers, dots or underscores'),
    findsOneWidget,
  );
  expect(find.text('At least 8 characters'), findsOneWidget);
  await picture('ios_first_use_registration_validation');
  for (var i = 0; i < 3; i++) {
    await t.enterText(fields.at(i), '');
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  await t.ensureVisible(find.text('I already have an account'));
  await present();
  await t.tap(find.text('I already have an account'));
  await waitUntil(() => find.byType(TextFormField).evaluate().length == 2);
  expect(t.state<FormState>(find.byType(Form)).validate(), isFalse);
  await present();
  expect(find.text('Required'), findsNWidgets(2));
  await t.ensureVisible(find.text('Forgot password?'));
  await present();
  await t.tap(find.text('Forgot password?'));
  await waitUntil(
    () => find.byType(PasswordRecoveryPage).evaluate().isNotEmpty,
  );
  await present();
  final recoveryPage = find.byType(PasswordRecoveryPage);
  final recoveryField = find.descendant(
    of: recoveryPage,
    matching: find.byType(TextFormField),
  );
  final recoveryForm = find.descendant(
    of: recoveryPage,
    matching: find.byType(Form),
  );
  await t.enterText(recoveryField, 'invalid');
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  expect(t.state<FormState>(recoveryForm).validate(), isFalse);
  await present();
  expect(find.text('Enter a valid email'), findsOneWidget);
  expect(find.text('Check your inbox'), findsNothing);
  await picture('ios_first_use_recovery_validation');
  await t.pageBack();
  await waitUntil(() => find.byType(AuthPage).evaluate().isNotEmpty);
  await present();
  expect(
    identical(t.widget<AuthPage>(find.byType(AuthPage)).session, session),
    isTrue,
  );
  expect(session.user, isNull);
  await stage(
    'native first-use UI captured without provider submission; fixture session restore follows',
  );
  return session;
}

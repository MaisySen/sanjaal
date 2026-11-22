// Native first-use navigation, input and validation pixels only.
// No sign-up, sign-in or password-reset request is submitted to a provider.
import 'package:flutter_test/flutter_test.dart';
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
  await stage('native first-use introduction and safe input validation');
  await waitUntil(
    () => find.text('Share with your community').evaluate().isNotEmpty,
  );
  await t.pump(const Duration(milliseconds: 600));
  await capture('ios_first_use_intro');
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
  await capture('ios_first_use_native_keyboard');
  await t.enterText(fields.at(0), 'invalid');
  await t.enterText(fields.at(1), 'x');
  await t.enterText(fields.at(2), 'short');
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  // Exercise the actual form's validators without submitting provider work.
  expect(t.state<FormState>(find.byType(Form)).validate(), isFalse);
  await t.pump(const Duration(milliseconds: 600));
  expect(find.text('Enter a valid email'), findsOneWidget);
  expect(
    find.text('Use 3 to 30 letters, numbers, dots or underscores'),
    findsOneWidget,
  );
  expect(find.text('At least 8 characters'), findsOneWidget);
  await capture('ios_first_use_registration_validation');
  for (var i = 0; i < 3; i++) {
    await t.enterText(fields.at(i), '');
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  await t.ensureVisible(find.text('I already have an account'));
  await t.tap(find.text('I already have an account'));
  await waitUntil(() => find.byType(TextFormField).evaluate().length == 2);
  expect(t.state<FormState>(find.byType(Form)).validate(), isFalse);
  await t.pump(const Duration(milliseconds: 600));
  expect(find.text('Required'), findsNWidgets(2));
  await t.ensureVisible(find.text('Forgot password?'));
  await t.tap(find.text('Forgot password?'));
  await waitUntil(
    () => find.byType(PasswordRecoveryPage).evaluate().isNotEmpty,
  );
  await t.enterText(find.byType(TextFormField), 'invalid');
  FocusManager.instance.primaryFocus?.unfocus();
  await waitUntil(() => t.view.viewInsets.bottom == 0);
  expect(t.state<FormState>(find.byType(Form)).validate(), isFalse);
  await t.pump(const Duration(milliseconds: 600));
  expect(find.text('Enter a valid email'), findsOneWidget);
  expect(find.text('Check your inbox'), findsNothing);
  await capture('ios_first_use_recovery_validation');
  await t.pageBack();
  await waitUntil(() => find.byType(AuthPage).evaluate().isNotEmpty);
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

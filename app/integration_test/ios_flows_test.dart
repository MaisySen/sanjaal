// Real iOS simulator and plugins against a disposable local API only.
// Does not prove Auth0, APNs, phone camera/mic, store signing or physical iPhone behavior.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' as app;
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> until(WidgetTester t, bool Function() ready) async {
  for (var i=0;i<100;i++) {
    await t.pump(const Duration(milliseconds:200));
    await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
    if(ready()) return;
  }
  throw TestFailure('iOS local flow did not settle. Visible: ${t.widgetList<Text>(find.byType(Text)).map((w)=>w.data).whereType<String>().take(35).toList()}');
}
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('iOS keychain migration restore five tabs post and draft storage', (t) async {
  expect(Platform.isIOS,isTrue);
  final p=await SharedPreferences.getInstance();await p.clear();
  await RefreshStore.clear();
  await p.setString('refresh_token','local-e2e');
  expect(await RefreshStore.read(),'local-e2e');expect(p.getString('refresh_token'),isNull);
  const drafts=CreatorDraftStore();
  final draft=await drafts.save('ios-synthetic-owner',text:'Native iOS fixture');
  expect((await drafts.read('ios-synthetic-owner')).any((d)=>d.id==draft.id&&d.text=='Native iOS fixture'),isTrue);
  expect(await drafts.read('ios-other-owner'),isEmpty);
  await drafts.remove('ios-synthetic-owner',draft.id);
  app.main();
  await until(t,()=>find.textContaining('Sunrise over Phewa').evaluate().isNotEmpty);
  await binding.takeScreenshot('ios_home');
  for(final tab in ['Reels','Chats','Wallet','Me','Home']) {
   await t.tap(find.text(tab).last);
   await until(t,()=>find.byType(CircularProgressIndicator).evaluate().isEmpty);
   expect(find.text('Could not load this page.'),findsNothing);
   await binding.takeScreenshot('ios_tab_${tab.toLowerCase()}');
  }
  final session=Session();await t.runAsync(()=>session.restore());
  expect(session.user?['name'],'Synthetic Member');
  await t.tap(find.byTooltip('Post'));
  await until(t,()=>find.text('Post').evaluate().isNotEmpty);
  await until(t,()=>find.text('Continue').evaluate().isNotEmpty);
  await t.tap(find.text('Post').last);await t.pump(const Duration(milliseconds:300));
  await t.tap(find.widgetWithText(FilledButton,'Continue'));
  await until(t,()=>find.byType(TextField).evaluate().isNotEmpty);
  final caption='iOS simulator local post ${DateTime.now().millisecondsSinceEpoch}';
  await t.tap(find.byType(TextField).first);await t.enterText(find.byType(TextField).first,caption);
  await t.pump(const Duration(milliseconds:400));await binding.takeScreenshot('ios_post_keyboard');
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  await until(t,()=>find.text(caption).evaluate().isNotEmpty&&find.text('Your post is up.').evaluate().isNotEmpty);
  await binding.takeScreenshot('ios_post_confirmed');
  await t.runAsync(()=>session.logout());expect(await RefreshStore.read(),isNull);
  expect(p.getString('refresh_token'),isNull);
  await t.pumpWidget(const SizedBox());
  print('iOS simulator local keychain/draft/restore/five-tab/post checks passed; no live service or physical iPhone proof.');
 });
}

// Android emulator, actual secure-storage plugin, no HTTP/credentials/media.
// The driver writes a random run-specific marker in one process, force-stops it,
// then runs the recovery phase in a new process with package data preserved.
import 'dart:io';
import 'dart:convert';
import 'package:sanjaal/creator_draft_store.dart';
import 'package:sanjaal/creator_drafts_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';


const _id = String.fromEnvironment('MARKER_ID');
const _owner = 'synthetic-process-death-fixture';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'native marker recovery must settle within eight seconds');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(String name) async {
    print('DRAFT_STAGE capture conversion $name');
    await binding.convertFlutterSurfaceToImage();
    await binding.pump();
    print('DRAFT_STAGE capture screenshot $name');
    await binding.takeScreenshot(name);
  }
  testWidgets('saved text poll survives process restart without posting', (tester) async {
    print('DRAFT_STAGE support directory');
    final dir=await tester.runAsync(getApplicationSupportDirectory);
    final recover=File('/data/user/0/au.fintex.sanjaal/files/synthetic-marker-recover');
    final phase=recover.existsSync()?'recover':'seed';
    const drafts=CreatorDraftStore();
    final body='Saved native poll $_id';
    const options=['Saturday after work','Sunday morning'];
    final session=Session()..user={'public_id':_owner,'username':'synthetic'};
    print('DRAFT_STAGE phase=$phase');
    if(phase=='seed'){
      expect(await tester.runAsync(()=>drafts.read(_owner)),isEmpty);
      print('DRAFT_STAGE initial read complete');
      final draft=await tester.runAsync(()=>drafts.save(_owner,text:body,options:options));
      print('DRAFT_STAGE saved native draft');
      await tester.runAsync(()=>File('${dir!.path}/saved-draft-identity.json').writeAsString(jsonEncode(draft!.toJson()),flush:true));
      await tester.pumpWidget(MaterialApp(home:CreatorDraftsPage(session:session)));
      print('DRAFT_STAGE list mounted');
      await _until(tester,()=>find.text(body).evaluate().isNotEmpty);
      print('DRAFT_STAGE list loaded');
      expect(find.text('Poll draft'),findsOneWidget);
      await tester.pump(const Duration(milliseconds:500));
      await capture('draft_restart_1_saved_poll');
      return;
    }
    final prior=jsonDecode(await File('${dir!.path}/saved-draft-identity.json').readAsString()) as Map;
    final restored=await tester.runAsync(()=>drafts.read(_owner));
    expect(restored!.single.toJson(),prior);
    expect(restored.single.text,body);expect(restored.single.options,options);
    expect(await tester.runAsync(()=>drafts.read('another-synthetic-owner')),isEmpty);
    await tester.pumpWidget(MaterialApp(home:CreatorDraftsPage(session:session)));
    await _until(tester,()=>find.text(body).evaluate().isNotEmpty);
    await tester.tap(find.text(body));await tester.pumpAndSettle();
    final fields=tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((f)=>f.controller!.text).toList(),[body,...options]);
    await capture('draft_restart_2_reopened_caption_options');
    await tester.pageBack();await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete draft'));await tester.pumpAndSettle();
    expect(find.text('Delete this local draft?'),findsOneWidget);
    await tester.tap(find.text('Keep'));await tester.pumpAndSettle();
    expect((await tester.runAsync(()=>drafts.read(_owner)))!.single.revision,restored.single.revision);
    await tester.tap(find.byTooltip('Delete draft'));await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton,'Delete'));await tester.pumpAndSettle();
    await _until(tester,()=>find.textContaining('No saved drafts yet').evaluate().isNotEmpty);
    expect(await tester.runAsync(()=>drafts.read(_owner)),isEmpty);
    await capture('draft_restart_3_explicit_delete');
    expect(UploadCenter.of(session).result,isNull);
    expect(UploadCenter.of(session).confirmedPosts,isEmpty);
  });
}

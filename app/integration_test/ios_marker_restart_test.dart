// Android emulator, actual secure-storage plugin, no HTTP/credentials/media.
// The driver writes a random run-specific marker in one process, force-stops it,
// then runs the recovery phase in a new process with package data preserved.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/semantics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/upload_pending_store.dart';


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
  SemanticsHandle? suiteSemantics;
  setUpAll(() async {
    suiteSemantics=binding.ensureSemantics();
    final deadline=DateTime.now().add(const Duration(seconds:10));
    while(!ui.PlatformDispatcher.instance.semanticsEnabled && DateTime.now().isBefore(deadline)){
      await Future<void>.delayed(const Duration(milliseconds:100));
    }
  });
  tearDownAll(() {suiteSemantics?.dispose();});
  Future<void> capture(String name) async {
    await binding.takeScreenshot(name);
    final dir=await getApplicationSupportDirectory();
    final pending=File('${dir.path}/$name.native-pending');
    final done=File('${dir.path}/$name.native-done');
    await binding.runAsync(() async {
      await pending.writeAsString('waiting',flush:true);
      final deadline=DateTime.now().add(const Duration(seconds:20));
      while(!await done.exists()){
        if(DateTime.now().isAfter(deadline))throw TestFailure('Host native capture missing $name');
        await Future<void>.delayed(const Duration(milliseconds:100));
      }
    });
  }
  testWidgets('native uncertainty marker across processes with zero requests', (tester) async {
    final dir=await tester.runAsync(getApplicationSupportDirectory);
    final recover=File('${dir!.path}/synthetic-marker-recover');
    final phase = recover.existsSync() ? 'recover' : 'seed';
    expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(_id), isTrue);
    expect(['seed', 'recover'], contains(phase));
    const store = UploadPendingStore();
    if (phase == 'seed') {
      // No FlutterSecureStorage.setMockInitialValues: this uses Android storage.
      expect(await tester.runAsync(() => store.read(_owner)), isNull);
      await tester.runAsync(() => store.write(_owner, _id, 'story'));
      expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SafeArea(child: Center(child: Text('Synthetic upload safety marker saved. No upload was sent.'))))));
      await tester.pump();
      if(Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await capture('process_death_1_native_marker_saved');
      // ignore: avoid_print
      print('PROCESS_DEATH_SEED native marker read-back verified; no request or media job created');
      return;
    }

    expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id,
        reason: 'the preceding process saved this exact run-specific marker');
    final session = Session()..user = {'public_id': _owner, 'username': 'synthetic'};
    final center = UploadCenter.of(session);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(child: Column(children: [
      UploadStrip(center: center),
      const Expanded(child: Center(child: Text('Synthetic restart. No network or saved media.'))),
    ])))));
    await _until(tester, () => !center.restoring);
    expect(center.error, isA<UploadError>());
    expect(center.canRetry, isFalse);
    expect(center.occupied, isTrue);
    var sends = 0;
    expect(center.start('story', () async { sends++; throw StateError('must not run'); }), isFalse);
    expect(sends, 0);
    expect(find.text('Try again'), findsNothing);
    expect(find.textContaining('earlier upload may already be posted'), findsOneWidget);
    expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id);
    if(Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await capture('process_death_2_native_recovered_paused');

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this draft?'), findsOneWidget);
    expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id,
        reason: 'opening confirmation is not permission to clear');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await _until(tester, () => !center.restoring && !center.occupied);
    expect(await tester.runAsync(() => store.read(_owner)), isNull);
    expect(sends, 0);
    expect(center.result, isNull);
    expect(center.confirmedStories, isEmpty);
    await tester.pumpAndSettle();
    await capture('process_death_3_explicit_discard_no_send');
    // ignore: avoid_print
    print('PROCESS_DEATH_RECOVERY exact native marker survived process restart; paused; cancel preserved; explicit discard cleared; requests=0');
  });
}

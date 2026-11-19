// Android emulator, actual secure-storage plugin, no HTTP/credentials/media.
// The driver writes a random run-specific marker in one process, force-stops it,
// then runs the recovery phase in a new process with package data preserved.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/upload_pending_store.dart';

const _phase = String.fromEnvironment('MARKER_PHASE');
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
  testWidgets('native uncertainty marker $_phase with zero requests', (tester) async {
    expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(_id), isTrue);
    expect(['seed', 'recover'], contains(_phase));
    const store = UploadPendingStore();
    if (_phase == 'seed') {
      // No FlutterSecureStorage.setMockInitialValues: this uses Android storage.
      expect(await tester.runAsync(() => store.read(_owner)), isNull);
      await tester.runAsync(() => store.write(_owner, _id, 'story'));
      expect((await tester.runAsync(() => store.read(_owner)))?['id'], _id);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SafeArea(child: Center(child: Text('Synthetic upload safety marker saved. No upload was sent.'))))));
      await tester.pump();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('process_death_1_native_marker_saved');
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
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('process_death_2_native_recovered_paused');

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
    await binding.takeScreenshot('process_death_3_explicit_discard_no_send');
    // ignore: avoid_print
    print('PROCESS_DEATH_RECOVERY exact native marker survived process restart; paused; cancel preserved; explicit discard cleared; requests=0');
  });
}

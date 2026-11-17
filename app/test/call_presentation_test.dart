// Simulated room states and real widgets, not two-device audio/video evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/call_presentation.dart';
import 'package:sanjaal/call_page.dart';

void main() {
  test('server connection alone is not a person answering', () {
    final p = presentCall(
      transport: CallTransport.connected,
      setupComplete: true,
      remoteCount: 0,
      previouslyConnected: true,
    );
    expect(p.status, 'Waiting for others to join');
    expect(p.mediaAvailable, true);
  });
  test(
    'connected requires setup and remote participant for connected label',
    () {
      expect(
        presentCall(
          transport: CallTransport.connected,
          setupComplete: false,
          remoteCount: 1,
          previouslyConnected: false,
        ).status,
        'Connecting...',
      );
      expect(
        presentCall(
          transport: CallTransport.connected,
          setupComplete: true,
          remoteCount: 1,
          previouslyConnected: true,
        ).status,
        'Connected',
      );
    },
  );
  test('reconnection and disconnection disable media changes', () {
    for (final t in [CallTransport.reconnecting, CallTransport.disconnected]) {
      final p = presentCall(
        transport: t,
        setupComplete: true,
        remoteCount: 1,
        previouslyConnected: true,
      );
      expect(p.mediaAvailable, false);
      expect(p.status, isNot('Connected'));
    }
  });
  testWidgets(
    'reconnection remains visible with video and End stays available',
    (tester) async {
      var ends = 0, mutes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CallView(
            title: 'Test member',
            status: 'Reconnecting...',
            failed: false,
            video: true,
            muted: false,
            camOn: true,
            tiles: const [CallTile(name: 'Test member')],
            controlsBusy: true,
            onMute: () => mutes++,
            onCamera: () {},
            onEnd: () => ends++,
          ),
        ),
      );
      expect(find.text('Reconnecting...'), findsOneWidget);
      await tester.tap(find.byTooltip('Mute microphone'));
      expect(mutes, 0);
      await tester.tap(find.byTooltip('End call'));
      expect(ends, 1);
    },
  );
  testWidgets('own camera preview remains visible while waiting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CallView(
          title: 'Test member',
          status: 'Waiting for others to join',
          failed: false,
          video: true,
          muted: false,
          camOn: true,
          tiles: const [],
          selfPreview: const Text('LOCAL CAMERA'),
          onMute: () {},
          onCamera: () {},
          onEnd: () {},
        ),
      ),
    );
    expect(find.text('LOCAL CAMERA'), findsOneWidget);
    expect(find.text('Waiting for others to join'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/rooms_page.dart';

void main() {
  test('host label follows stable identity, not the display name', () {
    final stage = buildStage(
      meId: 'u9',
      meName: 'Me',
      meOnStage: false,
      meMuted: false,
      meSpeaking: false,
      iAmHost: false,
      hostIdentity: 'u1',
      remote: [
        (id: 'u1', name: 'Asha Gurung', muted: false, speaking: true),
        (id: 'u7', name: 'Asha Gurung', muted: true, speaking: false),
      ],
    );
    expect(stage.where((m) => m.host).map((m) => m.id), ['u1']);
    expect(stage.firstWhere((m) => m.id == 'u7').host, isFalse);
  });

  test('no host identity means no remote host label', () {
    final stage = buildStage(
      meId: 'u9', meName: 'Me', meOnStage: false, meMuted: false, meSpeaking: false, iAmHost: false, hostIdentity: null,
      remote: [(id: 'u1', name: 'Asha Gurung', muted: false, speaking: true)],
    );
    expect(stage.single.host, isFalse);
  });

  test('my own entry is marked you, and host only when I am the host', () {
    final stage = buildStage(
      meId: 'u1', meName: 'Bidur', meOnStage: true, meMuted: true, meSpeaking: true, iAmHost: true, hostIdentity: 'u1', remote: const [],
    );
    expect(stage.single.you, isTrue);
    expect(stage.single.host, isTrue);
    expect(stage.single.speaking, isFalse, reason: 'muted means not speaking');
  });
}

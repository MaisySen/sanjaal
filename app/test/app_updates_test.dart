// Simulated gateway contracts. These do not prove a Play-owned device update.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/app_updates.dart';
import 'package:sanjaal/app_update_tile.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

class FakeUpdates implements AppUpdateGateway {
  @override
  bool supported = true;
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Map<String, dynamic> info = {
    'availability': 2,
    'available': true,
    'flexibleAllowed': true,
    'availableVersionCode': 2009,
    'installStatus': 0,
  };
  Future<Map<String, dynamic>> Function()? onCheck;
  Future<String> Function()? onStart;
  bool failCheck = false, failInstall = false;
  int checks = 0, starts = 0, installs = 0;
  String consent = 'ACCEPTED';
  int subscriptions = 0;
  @override
  Stream<Map<String, dynamic>> get events {
    subscriptions++;
    return stream.stream;
  }

  @override
  Future<Map<String, dynamic>> check() async {
    checks++;
    if (failCheck) throw StateError('offline');
    return onCheck == null ? info : await onCheck!();
  }

  @override
  Future<String> start() async {
    starts++;
    return onStart == null ? consent : await onStart!();
  }

  @override
  Future<void> complete() async {
    installs++;
    if (failInstall) throw StateError('no storage');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeUpdates gateway;
  late AppUpdateController controller;
  setUp(() {
    gateway = FakeUpdates();
    controller = AppUpdateController(gateway);
  });
  tearDown(() {
    controller.dispose();
    gateway.stream.close();
  });
  testWidgets('Nepali update states and actions stay translated without side effects',(t)async{
    prefs.lang='ne';addTearDown(()=>prefs.lang='en');
    for(final phase in UpdatePhase.values){
      controller.phase=phase;
      await t.pumpWidget(MaterialApp(theme:buildTheme(Brightness.dark),home:Scaffold(body:AppUpdateTile(key:ValueKey(phase),controller:controller))));await t.pump();
      final texts=t.widgetList<Text>(find.byType(Text)).map((w)=>w.data??'').where((s)=>s.isNotEmpty).toList();
      expect(texts,everyElement(matches(RegExp(r'[\u0900-\u097F]'))),reason:'all status/action/help text is Nepali in $phase');
      expect(t.takeException(),isNull);
    }
    expect(gateway.checks+gateway.starts+gateway.installs,0);
  });
  test('idle has no silent check, download or install', () {
    expect(controller.phase, UpdatePhase.idle);
    expect(gateway.subscriptions, 0);
    expect(gateway.checks + gateway.starts + gateway.installs, 0);
  });
  test(
    'available does not download or install until explicit action',
    () async {
      await controller.check();
      expect(controller.phase, UpdatePhase.available);
      expect(controller.versionCode, 2009);
      expect(gateway.starts + gateway.installs, 0);
    },
  );
  test('full flexible flow separates download consent and restart', () async {
    await controller.check();
    await controller.download();
    expect(controller.phase, UpdatePhase.downloading);
    expect(gateway.installs, 0);
    gateway.stream.add({
      'installStatus': 2,
      'bytesDownloaded': 20,
      'totalBytes': 100,
    });
    expect(controller.progress, .2);
    gateway.stream.add({'installStatus': 11});
    expect(controller.phase, UpdatePhase.ready);
    expect(gateway.installs, 0);
    await controller.install();
    expect(gateway.installs, 1);
    expect(controller.phase, UpdatePhase.installing);
  });
  test('current only means Play reports no newer account build', () async {
    gateway.info['availability'] = 1;
    gateway.info['available'] = false;
    await controller.check();
    expect(controller.phase, UpdatePhase.current);
  });
  test('unknown and in-progress availability never claim current', () async {
    for (final availability in [0, 3]) {
      gateway.info['availability'] = availability;
      gateway.info['available'] = false;
      await controller.check();
      expect(controller.phase, UpdatePhase.unavailable);
      expect(gateway.starts + gateway.installs, 0);
    }
  });
  test('resume preserves Play canceled state instead of current or offer', () async {
    for (final availability in [1, 2]) {
      gateway.info['availability'] = availability;
      gateway.info['available'] = availability == 2;
      gateway.info['installStatus'] = 6;
      await controller.check(resume: true);
      expect(controller.phase, UpdatePhase.canceled);
      expect(gateway.starts + gateway.installs, 0);
    }
  });
  test('invalid native check cannot report current or offer an update', () async {
    final valid = Map<String, dynamic>.from(gateway.info);
    for (final changed in <Map<String, dynamic>>[
      {'availability': null}, {'availability': '2'}, {'availability': 2.0},
      {'availability': -1}, {'availability': 99}, {'availability': false},
      {'available': null}, {'available': 'true'}, {'available': false},
      {'flexibleAllowed': null}, {'flexibleAllowed': 'true'},
      {'installStatus': null}, {'installStatus': '0'}, {'installStatus': 0.0},
      {'installStatus': -1}, {'installStatus': 99},
      {'availability': 1, 'available': true},
    ]) {
      gateway.info = {...valid, ...changed};
      await controller.check();
      expect(controller.phase, UpdatePhase.unavailable, reason: '$changed');
      expect(gateway.starts + gateway.installs, 0);
    }
  });
  test('ready or downloading status is preserved with unknown availability', () async {
    gateway.info['availability'] = 0;
    gateway.info['available'] = false;
    gateway.info['installStatus'] = 11;
    await controller.check(resume: true);
    expect(controller.phase, UpdatePhase.ready);
    gateway.info['installStatus'] = 2;
    await controller.check(resume: true);
    expect(controller.phase, UpdatePhase.downloading);
    expect(gateway.installs, 0);
  });

  test('offline does not falsely report latest', () async {
    gateway.failCheck = true;
    await controller.check();
    expect(controller.phase, UpdatePhase.unavailable);
  });
  test(
    'disallowed flexible update never falls back to forced immediate',
    () async {
      gateway.info['flexibleAllowed'] = false;
      await controller.check();
      await controller.download();
      expect(controller.phase, UpdatePhase.unavailable);
      expect(gateway.starts, 0);
    },
  );
  test('user cancel is not failure or completion', () async {
    gateway.consent = 'CANCELED';
    await controller.check();
    await controller.download();
    expect(controller.phase, UpdatePhase.canceled);
    expect(gateway.installs, 0);
  });
  test(
    'resume recovers downloaded update without automatically installing',
    () async {
      gateway.info['installStatus'] = 11;
      await controller.check(resume: true);
      expect(controller.phase, UpdatePhase.ready);
      expect(gateway.installs, 0);
    },
  );
  test('resume recovers ongoing download', () async {
    gateway.info['installStatus'] = 2;
    await controller.check(resume: true);
    expect(controller.phase, UpdatePhase.downloading);
  });
  test('download-ready event beats delayed consent result', () async {
    final done = Completer<String>();
    gateway.onStart = () => done.future;
    await controller.check();
    final future = controller.download();
    gateway.stream.add({'installStatus': 11});
    done.complete('ACCEPTED');
    await future;
    expect(controller.phase, UpdatePhase.ready);
  });
  test('ongoing event beats stale checking response', () async {
    final done = Completer<Map<String, dynamic>>();
    gateway.onCheck = () => done.future;
    final future = controller.check();
    gateway.stream.add({'installStatus': 2});
    done.complete({'available': false});
    await future;
    expect(controller.phase, UpdatePhase.downloading);
  });
  test('double tap cannot launch two consent flows', () async {
    final done = Completer<String>();
    gateway.onStart = () => done.future;
    await controller.check();
    final future = controller.download();
    await controller.download();
    expect(gateway.starts, 1);
    done.complete('CANCELED');
    await future;
  });
  test('cannot install before downloaded', () async {
    await controller.install();
    expect(gateway.installs, 0);
  });
  test('install error is recoverable and does not claim success', () async {
    gateway.info['installStatus'] = 11;
    gateway.failInstall = true;
    await controller.check();
    await controller.install();
    expect(controller.phase, UpdatePhase.failed);
  });
  test('failed and canceled stream states are distinct', () async {
    await controller.check();
    gateway.stream.add({'installStatus': 5});
    expect(controller.phase, UpdatePhase.failed);
    gateway.stream.add({'installStatus': 6});
    expect(controller.phase, UpdatePhase.canceled);
  });
  test('unsupported platform never calls Play', () async {
    final other = FakeUpdates()..supported = false;
    final c = AppUpdateController(other);
    await c.check();
    expect(c.phase, UpdatePhase.unsupported);
    expect(other.checks, 0);
    c.dispose();
    await other.stream.close();
  });
  testWidgets('screen requires explicit restart tap', (tester) async {
    await controller.check();
    gateway.stream.add({'installStatus': 11});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdateTile(controller: controller)),
      ),
    );
    expect(find.text('Restart and install'), findsOneWidget);
    expect(gateway.installs, 0);
    await tester.tap(find.text('Restart and install'));
    await tester.pump();
    expect(gateway.installs, 1);
    expect(find.textContaining('may restart'), findsOneWidget);
  });
  for (final brightness in Brightness.values) {
    for (final scenario in ['ready', 'unknown', 'canceled', 'current']) {
    testWidgets('render $scenario $brightness at narrow large text', (
      tester,
    ) async {
      final font = FontLoader('Roboto');
      final root = Platform.environment['FLUTTER_ROOT'] ?? '';
      final f = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (f.existsSync()) {
        font.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        await font.load();
      }
      tester.view.physicalSize = const Size(960, 2100);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (scenario == 'unknown' || scenario == 'current') {
        gateway.info['availability'] = scenario == 'unknown' ? 0 : 1;
        gateway.info['available'] = false;
      }
      if (scenario == 'canceled') gateway.info['installStatus'] = 6;
      await controller.check();
      if (scenario == 'ready') gateway.stream.add({'installStatus': 11});
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(brightness, fontFamily: 'Roboto'),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.4),
              ),
              child: Scaffold(
                appBar: AppBar(title: const Text('App updates')),
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppUpdateTile(controller: controller),
                    const SizedBox(height: 32),
                    const Text(
                      'SIMULATED PLAY STATE - NOT DEVICE EVIDENCE',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('test/renders').createSync(recursive: true);
        File('test/renders/app_updates_${scenario}_${brightness.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/device_access_page.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;
import 'upload_center_test.dart' as h;

Map<String, Object> status({
  String platform = 'android',
  String camera = 'allowed',
}) => {
  'platform': platform,
  'states': {
    'camera': camera,
    'microphone': 'not_allowed',
    'photos': 'limited',
    'videos': 'limited',
  },
};

class FakeAccess extends DeviceAccessGateway {
  FakeAccess(this.next, {this.open});
  final Future<DeviceAccessSnapshot> Function() next;
  final Future<bool> Function()? open;
  int reads = 0, opens = 0;
  @override
  Future<DeviceAccessSnapshot> read() {
    reads++;
    return next();
  }

  @override
  Future<bool> openSettings() {
    opens++;
    return open?.call() ?? Future.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  test('native snapshot rejects unknown or incomplete status', () {
    expect(
      () => DeviceAccessSnapshot({'platform': 'android', 'states': {}}),
      throwsFormatException,
    );
    expect(
      () => DeviceAccessSnapshot(status(camera: 'limited')),
      throwsFormatException,
    );
    expect(
      () => DeviceAccessSnapshot(status(camera: 'invented')),
      throwsFormatException,
    );
    expect(
      () => DeviceAccessSnapshot(status(platform: 'web')),
      throwsFormatException,
    );
  });
  test('native bridge reads and opens only the named device channel', () async {
    final methods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DeviceAccessGateway.channel, (
      call,
    ) async {
      methods.add(call.method);
      return call.method == 'status' ? status() : true;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(DeviceAccessGateway.channel, null),
    );
    const gateway = DeviceAccessGateway();
    expect((await gateway.read()).values['photos'], 'limited');
    expect(methods, ['status']);
    expect(await gateway.openSettings(), isTrue);
    expect(methods, ['status', 'settings']);
  });
  testWidgets('settings search reaches actual device access page', (t) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      DeviceAccessGateway.channel,
      (_) async => status(),
    );
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(DeviceAccessGateway.channel, null),
    );
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
      await t.enterText(find.byType(TextField), 'permissions');
      await t.pump();
      await t.tap(find.text('Device access'));
      await h.flush(t);
      await t.pumpAndSettle();
      expect(find.byType(DeviceAccessPage), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Selected items only'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });
  });
  testWidgets('failed read has explicit retry rather than guessed grants', (
    t,
  ) async {
    var attempts = 0;
    final gateway = FakeAccess(() async {
      if (++attempts == 1) throw StateError('fixture');
      return DeviceAccessSnapshot(status());
    });
    await p.fixture(
      t,
      (s) => DeviceAccessPage(session: s, gateway: gateway),
      () async {
        expect(
          find.text('Device access could not be checked. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Allowed'), findsNothing);
        await t.tap(find.text('Check again'));
        await h.flush(t);
        expect(find.text('Camera'), findsOneWidget);
        expect(gateway.reads, 2);
        expect(t.takeException(), isNull);
      },
    );
  });
  testWidgets(
    'returning from OS settings reads grants again without a prompt',
    (t) async {
      var reads = 0;
      final gateway = FakeAccess(
        () async => DeviceAccessSnapshot(
          status(camera: ++reads == 1 ? 'allowed' : 'not_requested'),
        ),
      );
      await p.fixture(
        t,
        (s) => DeviceAccessPage(session: s, gateway: gateway),
        () async {
          expect(find.text('Allowed'), findsOneWidget);
          await t.tap(find.text('Open device settings'));
          await h.flush(t);
          expect(gateway.opens, 1);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await h.flush(t);
          expect(find.text('Not requested'), findsOneWidget);
          expect(gateway.reads, 2);
          expect(gateway.opens, 1);
          expect(t.takeException(), isNull);
        },
      );
    },
  );
  testWidgets('settings launch is guarded and failure stays recoverable', (
    t,
  ) async {
    final result = Completer<bool>();
    final gateway = FakeAccess(
      () async => DeviceAccessSnapshot(status()),
      open: () => result.future,
    );
    await p.fixture(
      t,
      (s) => DeviceAccessPage(session: s, gateway: gateway),
      () async {
        await t.tap(find.text('Open device settings'));
        await t.pump();
        expect(
          t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(gateway.opens, 1);
        result.complete(false);
        await h.flush(t);
        expect(
          find.text('Device settings could not be opened. Try again.'),
          findsOneWidget,
        );
        expect(
          t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
      },
    );
  });
  testWidgets('late native result cannot enter a replacement login', (t) async {
    final result = Completer<DeviceAccessSnapshot>();
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(
        MaterialApp(
          home: DeviceAccessPage(
            session: s,
            gateway: FakeAccess(() => result.future),
          ),
        ),
      );
      await s.login('fixture', 'not-a-password');
      await h.flush(t);
      result.complete(DeviceAccessSnapshot(status()));
      await h.flush(t);
      expect(find.text('Camera'), findsNothing);
      expect(find.textContaining('another signed-in session'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
  for (final lang in ['en', 'ne']) {
    for (final large in [false, true]) {
      for (final platform in ['android', 'ios']) {
        testWidgets('device access pixels $lang $platform large=$large', (
          t,
        ) async {
          t.view.physicalSize = large
              ? const Size(320, 640)
              : const Size(390, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await p.fixture(
            t,
            (s) => DeviceAccessPage(
              session: s,
              gateway: FakeAccess(
                () async => DeviceAccessSnapshot(status(platform: platform)),
              ),
            ),
            () async {
              await h.flush(t);
              expect(t.takeException(), isNull);
              expect(find.text(t_('Microphone')), findsOneWidget);
              await p.shot(
                t,
                'device_access_${lang}_${platform}_${large ? 'large' : 'normal'}',
              );
              await t.scrollUntilVisible(
                find.text(t_('Open device settings')),
                180,
                scrollable: find.byType(Scrollable),
              );
              await t.pumpAndSettle();
              await p.shot(
                t,
                'device_access_${lang}_${platform}_${large ? 'large' : 'normal'}_action',
              );
              expect(
                find.text(t_('Open device settings')).hitTestable(),
                findsOneWidget,
              );
              expect(t.takeException(), isNull);
            },
            language: lang,
            scale: large ? 1.8 : 1,
            brightness: lang == 'en' ? Brightness.light : Brightness.dark,
          );
        });
      }
    }
  }
}

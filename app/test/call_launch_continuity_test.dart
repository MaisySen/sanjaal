import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/active_call_host.dart';
import 'package:sanjaal/main.dart' show HomeShell;

import 'active_call_host_test.dart' show CallHarness;

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? '/tmp/sj-flutter-sdk'}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? '/tmp/sj-flutter-sdk'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(font.$1)
            ..addFont(File(font.$2).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  testWidgets(
    'actual call history opens and minimises the host-owned voice call',
    (t) async {
      final h = CallHarness();
      h.session.respond = (method, path, body) async {
        if (path == '/calls')
          return {
            'data': [
              {
                'public_id': 'history',
                'conversation_id': 'chat',
                'title': 'Synthetic caller',
                'caller': {'username': 'fixture'},
                'direction': 'incoming',
                'kind': 'voice',
                'status': 'ended',
                'duration_s': 12,
                'created_at': '2026-11-23T00:00:00Z',
              },
            ],
          };
        return {'data': []};
      };
      await h.mount(t, screen: CallsPage(session: h.session));
      await t.tap(find.byTooltip('Voice call'));
      await t.pumpAndSettle();
      expect(find.byType(CallPage), findsOneWidget);
      await h.minimize(t);
      expect(find.byType(ActiveCallBanner), findsOneWidget);
      expect(h.natives.single.events, ['connect', 'microphone:true']);
      await h.end(t);
      expect(find.byType(CallsPage), findsOneWidget);
      expect(
        h.session.requests.where((r) => r.path.contains('/call-token')).length,
        1,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual accepted incoming route hands ownership to host without ending on minimise',
    (t) async {
      final h = CallHarness();
      final call = <String, dynamic>{
        'public_id': 'incoming',
        'conversation_id': 'chat',
        'title': 'Synthetic caller',
        'caller': {'username': 'fixture'},
        'kind': 'voice',
        'status': 'ringing',
        'ring_expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      };
      h.session.respond = (method, path, body) async {
        if (path == '/calls/incoming/action')
          return {
            'call': {
              ...call,
              'status': body?['action'] == 'answer' ? 'answered' : 'ended',
            },
          };
        return {'data': []};
      };
      await h.mount(t);
      h.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => IncomingCallPage(session: h.session, call: call),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Accept'));
      await t.pumpAndSettle();
      expect(find.byType(CallPage), findsOneWidget);
      expect(find.byType(IncomingCallPage), findsNothing);
      await h.minimize(t);
      expect(find.byType(ActiveCallBanner), findsOneWidget);
      expect(
        h.session.requests
            .where((r) => r.path.contains('/call-token?call=incoming'))
            .length,
        1,
      );
      expect(h.natives.length, 1);
      await h.end(t);
      expect(find.text('Synthetic app'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual home shell does not poll a second ringing call while one is active',
    (t) async {
      final h = CallHarness();
      await h.mount(t, screen: HomeShell(session: h.session));
      unawaited(h.start());
      await t.pumpAndSettle();
      await h.minimize(t);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(
        h.session.requests.where((r) => r.path == '/calls/incoming'),
        isEmpty,
      );
      await h.end(t);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(
        h.session.requests.where((r) => r.path == '/calls/incoming').length,
        1,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final invalidation in ['expired', 'background-return', 'same-account', 'other-account', 'not-ringing', 'malformed', 'wrong-kind']) {
    testWidgets('home ignores $invalidation incoming snapshot', (t) async {
      final h = CallHarness();
      final reply = Completer<dynamic>();
      h.session.respond = (method, path, body) async {
        if (path == '/calls/incoming') return reply.future;
        return {'data': [], 'unread_messages': 0};
      };
      await h.mount(t, screen: HomeShell(session: h.session));
      await t.pump(const Duration(seconds: 5));
      expect(h.session.requests.where((r) => r.path == '/calls/incoming').length, 1);
      if (invalidation == 'background-return') {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pump();
      }
      if (invalidation == 'same-account') h.session.replace();
      if (invalidation == 'other-account') h.session.replace(owner: 'replacement');
      final call = <String, dynamic>{
        'public_id': 'incoming', 'conversation_id': 'chat', 'title': 'Synthetic caller',
        'caller': {'username': 'fixture'},
        'kind': invalidation == 'wrong-kind' ? 'unexpected' : 'voice',
        'status': invalidation == 'not-ringing' ? 'ended' : 'ringing',
        'ring_expires_at': invalidation == 'malformed' ? 'unknown' : DateTime.now().toUtc()
            .add(Duration(minutes: invalidation == 'expired' ? -1 : 1)).toIso8601String(),
      };
      reply.complete({'data': [call]});
      await t.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(h.natives, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('home presents a current live incoming call once', (t) async {
    final h = CallHarness();
    h.session.respond = (method, path, body) async {
      if (path == '/calls/incoming') return {'data': [{
        'public_id': 'incoming', 'conversation_id': 'chat', 'title': 'Synthetic caller',
        'caller': {'username': 'fixture'}, 'kind': 'voice', 'status': 'ringing',
        'ring_expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String(),
      }]};
      return {'data': [], 'unread_messages': 0};
    };
    await h.mount(t, screen: HomeShell(session: h.session));
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byType(IncomingCallPage), findsOneWidget);
    expect(h.natives, isEmpty);
    await t.pump(const Duration(seconds: 5));
    expect(h.session.requests.where((r) => r.path == '/calls/incoming').length, 1);
    await h.screenshot(t, 'incoming_current_snapshot');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('home reconciles a fresh poll after dropping pre-background response', (t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = CallHarness();
    final oldReply = Completer<dynamic>();
    var reads = 0;
    final current = {'data': [{
      'public_id': 'fresh', 'conversation_id': 'chat', 'title': 'Synthetic caller',
      'caller': {'username': 'fixture'}, 'kind': 'video', 'status': 'ringing',
      'ring_expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String(),
    }]};
    h.session.respond = (method, path, body) async {
      if (path == '/calls/incoming') return ++reads == 1 ? oldReply.future : current;
      return {'data': [], 'unread_messages': 0};
    };
    await h.mount(t, screen: HomeShell(session: h.session));
    await t.pump(const Duration(seconds: 5));
    expect(reads, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    oldReply.complete({'data': [{...(current['data'] as List).single as Map<String, dynamic>, 'public_id': 'retired-snapshot'}]});
    await t.pump();
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(reads, 2);
    expect(find.byType(IncomingCallPage), findsOneWidget);
    expect(t.widget<IncomingCallPage>(find.byType(IncomingCallPage)).call['public_id'], 'fresh');
    expect(h.natives, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

}

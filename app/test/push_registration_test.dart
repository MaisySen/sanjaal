// Fake device/token and server callbacks only. Not FCM delivery/device proof.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/push_registration.dart';

class Device implements PushDevice {
  final changes = StreamController<String>.broadcast(sync: true);
  Completer<bool>? permissionWait;
  Completer<String?>? tokenWait;
  bool allowed = true, failInvalidate = false;
  int invalidations = 0;
  @override
  Future<bool> permission() async =>
      permissionWait == null ? allowed : await permissionWait!.future;
  @override
  Future<String?> token() async =>
      tokenWait == null ? 'fixture-token' : await tokenWait!.future;
  @override
  Stream<String> get refreshes => changes.stream;
  @override
  Future<void> invalidate() async {
    invalidations++;
    if (failInvalidate) throw StateError('offline');
  }
}

class Account implements PushAccount {
  Account(this.owner);
  @override
  String? owner;
  final added = <String>[], removed = <String>[];
  Completer<void>? registerWait;
  bool failRemove = false;
  @override
  Future<void> registerToken(String token) async {
    added.add(token);
    await registerWait?.future;
  }

  @override
  Future<void> removeToken(String token) async {
    removed.add(token);
    if (failRemove) throw StateError('offline');
  }
}

Future<void> turns() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Device device;
  late PushRegistration push;
  late Account account;
  setUp(() {
    device = Device();
    push = PushRegistration(device);
    account = Account('a');
  });
  tearDown(() async {
    await push.dispose();
    await device.changes.close();
  });
  test('detached removal survives immediate local owner clearing', () async {
    await push.register(account);
    final removed = <String>[];
    final cleanup = push.unregister(account, removeForSignedOutAccount: (token) async { removed.add(token); });
    account.owner = null;
    await cleanup;
    expect(removed, ['fixture-token']);
    expect(device.invalidations, 1);
    expect(account.removed, isEmpty);
  });
  test('detached removal failure still invalidates the local token', () async {
    await push.register(account);
    final cleanup = push.unregister(account, removeForSignedOutAccount: (_) async { throw StateError('offline'); });
    account.owner = null;
    await cleanup;
    expect(device.invalidations, 1);
    expect(push.status.value, 'Local notification token removed');
  });
  test(
    'registration says unverified delivery and never includes token',
    () async {
      await push.register(account);
      expect(account.added, ['fixture-token']);
      expect(push.status.value, contains('not been verified'));
      expect(push.status.value, isNot(contains('fixture-token')));
    },
  );
  test('signout cancels refresh and invalidates device token', () async {
    await push.register(account);
    await push.unregister(account);
    device.changes.add('late-refresh');
    await turns();
    expect(account.added, ['fixture-token']);
    expect(account.removed, ['fixture-token']);
    expect(device.invalidations, 1);
  });
  test('signout during permission prompt cannot register later', () async {
    device.permissionWait = Completer<bool>();
    final registration = push.register(account);
    await turns();
    final signout = push.unregister(account);
    device.permissionWait!.complete(true);
    await registration;
    await signout;
    expect(account.added, isEmpty);
    expect(device.invalidations, 1);
  });
  test('signout during token fetch cannot register late token', () async {
    device.tokenWait = Completer<String?>();
    final registration = push.register(account);
    await turns();
    final signout = push.unregister(account);
    device.tokenWait!.complete('late-token');
    await registration;
    await signout;
    expect(account.added, isEmpty);
  });
  test(
    'inflight register drains before server removal and local invalidation',
    () async {
      account.registerWait = Completer<void>();
      final registration = push.register(account);
      await turns();
      expect(account.added.length, 1);
      final signout = push.unregister(account);
      account.registerWait!.complete();
      await registration;
      await signout;
      expect(account.removed, ['fixture-token']);
      expect(device.invalidations, 1);
      expect(push.status.value, 'Local notification token removed');
    },
  );
  test('next account owns refresh and old callbacks do not leak', () async {
    await push.register(account);
    await push.unregister(account);
    final other = Account('b');
    await push.register(other);
    device.changes.add('new-token');
    await turns();
    expect(other.added, ['fixture-token', 'new-token']);
    expect(account.added, ['fixture-token']);
  });
  test('old session signout cannot unregister new session binding', () async {
    await push.register(account);
    final other = Account('b');
    await push.register(other);
    await push.unregister(account);
    expect(device.invalidations, 1);
    device.changes.add('next');
    await turns();
    expect(other.added.last, 'next');
  });
  test('account changes during token wait discard original request', () async {
    device.tokenWait = Completer<String?>();
    final registration = push.register(account);
    await turns();
    account.owner = 'b';
    device.tokenWait!.complete('late');
    await registration;
    expect(account.added, isEmpty);
  });
  test('denied permission does not get token or attach refresh', () async {
    device.allowed = false;
    await push.register(account);
    device.changes.add('ignored');
    await turns();
    expect(account.added, isEmpty);
    expect(push.status.value, contains('Off:'));
  });
  test('offline server removal still invalidates local token', () async {
    await push.register(account);
    account.failRemove = true;
    await push.unregister(account);
    expect(device.invalidations, 1);
  });
  test('cleanup failure is not hidden as confirmed cleanup', () async {
    await push.register(account);
    device.failInvalidate = true;
    await push.unregister(account);
    expect(push.status.value, contains('could not be confirmed'));
  });
  test(
    'logout does not wait for unresolved system permission prompt',
    () async {
      device.permissionWait = Completer<bool>();
      final registration = push.register(account);
      await turns();
      await push.unregister(account).timeout(const Duration(seconds: 1));
      expect(device.invalidations, 1);
      device.permissionWait!.complete(true);
      await registration;
      expect(account.added, isEmpty);
    },
  );
  test('failed cleanup blocks reuse for a different owner', () async {
    await push.register(account);
    device.failInvalidate = true;
    await push.unregister(account);
    final other = Account('b');
    await push.register(other);
    expect(other.added, isEmpty);
    expect(push.status.value, contains('Not available'));
  });
  test(
    'new account invalidates old binding even without explicit logout',
    () async {
      await push.register(account);
      final other = Account('b');
      await push.register(other);
      expect(device.invalidations, 1);
      expect(other.added, ['fixture-token']);
      device.changes.add('refresh-b');
      await turns();
      expect(account.added, ['fixture-token']);
      expect(other.added.last, 'refresh-b');
    },
  );
  test(
    'queued refresh before signout cannot create late registration',
    () async {
      await push.register(account);
      device.changes.add('queued-refresh');
      await push.unregister(account);
      expect(account.added, ['fixture-token']);
      expect(account.removed, ['fixture-token']);
    },
  );
  test('refresh already in flight is removed using latest token', () async {
    await push.register(account);
    account.registerWait = Completer<void>();
    device.changes.add('inflight-refresh');
    await turns();
    final signout = push.unregister(account);
    account.registerWait!.complete();
    await signout;
    expect(account.removed, ['inflight-refresh']);
    expect(device.invalidations, 1);
  });
  test(
    'duplicate registration replaces rather than stacking listener',
    () async {
      await push.register(account);
      await push.register(account);
      device.changes.add('once-only');
      await turns();
      expect(account.added.where((t) => t == 'once-only').length, 1);
    },
  );
  test('unauthenticated account cannot register', () async {
    account.owner = null;
    await push.register(account);
    expect(account.added, isEmpty);
    expect(push.status.value, 'Not set up yet');
  });
}

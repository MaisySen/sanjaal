import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Store-managed full builds, not OTA patches. Never installs without a tap.
enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  consent,
  downloading,
  ready,
  installing,
  unavailable,
  canceled,
  failed,
  unsupported,
}

abstract class AppUpdateGateway {
  bool get supported;
  Stream<Map<String, dynamic>> get events;
  Future<Map<String, dynamic>> check();
  Future<String> start();
  Future<void> complete();
}

class PlayUpdateGateway implements AppUpdateGateway {
  static const _method = MethodChannel('au.fintex.sanjaal/updates');
  static const _events = EventChannel('au.fintex.sanjaal/updates/events');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
  @override
  Future<Map<String, dynamic>> check() async =>
      Map<String, dynamic>.from((await _method.invokeMethod<Map>('check'))!);
  @override
  Future<String> start() async =>
      (await _method.invokeMethod<String>('start'))!;
  @override
  Future<void> complete() => _method.invokeMethod<void>('complete');
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController(this.gateway) {
    if (!gateway.supported) {
      phase = UpdatePhase.unsupported;
      return;
    }
  }
  final AppUpdateGateway gateway;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  UpdatePhase phase = UpdatePhase.idle;
  int? versionCode;
  double? progress;
  bool _disposed = false;
  int _request = 0;
  bool get busy => {
    UpdatePhase.checking,
    UpdatePhase.consent,
    UpdatePhase.downloading,
    UpdatePhase.installing,
  }.contains(phase);
  void _set(UpdatePhase value) {
    if (_disposed) return;
    phase = value;
    notifyListeners();
  }

  void _event(Map<String, dynamic> event) {
    if (_disposed) return;
    final status = event['installStatus'];
    if ({1, 2, 3, 5, 6, 11}.contains(status)) {
      _request++;
    }
    final bytes = event['bytesDownloaded'];
    final total = event['totalBytes'];
    if (bytes is num && total is num && total > 0) {
      progress = (bytes / total).clamp(0.0, 1.0);
    }
    if (status == 11) {
      _set(UpdatePhase.ready);
    } else if (status == 1 || status == 2) {
      _set(UpdatePhase.downloading);
    } else if (status == 3) {
      _set(UpdatePhase.installing);
    } else if (status == 5) {
      _set(UpdatePhase.failed);
    } else if (status == 6) {
      _set(UpdatePhase.canceled);
    }
  }

  Future<void> check({bool resume = false}) async {
    if (_disposed ||
        !gateway.supported ||
        phase == UpdatePhase.checking ||
        phase == UpdatePhase.consent ||
        phase == UpdatePhase.installing) {
      return;
    }
    if (!resume && phase == UpdatePhase.downloading) return;
    _subscription ??= gateway.events.listen(
      _event,
      onError: (_) {
        _request++;
        _set(UpdatePhase.unavailable);
      },
    );
    final token = ++_request;
    _set(UpdatePhase.checking);
    try {
      final value = await gateway.check().timeout(const Duration(seconds: 20));
      if (_disposed || token != _request) return;
      versionCode = value['availableVersionCode'] is int
          ? value['availableVersionCode'] as int
          : null;
      final status = value['installStatus'];
      if (status == 11) {
        _set(UpdatePhase.ready);
      } else if (status == 1 || status == 2) {
        _set(UpdatePhase.downloading);
      } else if (status == 3) {
        _set(UpdatePhase.installing);
      } else if (status == 5) {
        _set(UpdatePhase.failed);
      } else if (value['available'] == true) {
        _set(
          value['flexibleAllowed'] == true
              ? UpdatePhase.available
              : UpdatePhase.unavailable,
        );
      } else {
        _set(UpdatePhase.current);
      }
    } catch (_) {
      if (!_disposed && token == _request) _set(UpdatePhase.unavailable);
    }
  }

  Future<void> download() async {
    if (_disposed || phase != UpdatePhase.available) return;
    final token = ++_request;
    progress = null;
    _set(UpdatePhase.consent);
    try {
      final result = await gateway.start();
      if (_disposed || token != _request) return;
      switch (result) {
        case 'DOWNLOADED':
          _set(UpdatePhase.ready);
        case 'ACCEPTED':
          if (phase != UpdatePhase.ready) _set(UpdatePhase.downloading);
        case 'CANCELED':
          _set(UpdatePhase.canceled);
        case 'NOT_ALLOWED':
          _set(UpdatePhase.unavailable);
        default:
          _set(UpdatePhase.failed);
      }
    } catch (_) {
      if (!_disposed && token == _request) _set(UpdatePhase.failed);
    }
  }

  Future<void> install() async {
    if (_disposed || phase != UpdatePhase.ready) return;
    _request++;
    _set(UpdatePhase.installing);
    try {
      await gateway.complete().timeout(const Duration(seconds: 20));
    } catch (_) {
      if (!_disposed) _set(UpdatePhase.failed);
    }
    // A successful call starts Play's restart. It is not proof of installation.
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _subscription?.cancel();
    super.dispose();
  }
}

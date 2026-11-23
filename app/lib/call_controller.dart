import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'call_connection.dart';
import 'call_lifecycle.dart';
import 'call_media_guard.dart';
import 'call_presentation.dart';

/// Owns one native call independently of whether its screen is presented.
/// Credentials remain bound to the login that created this owner.
class CallController extends ChangeNotifier {
  CallController({
    required this.session,
    required this.conversationId,
    required this.title,
    required this.video,
    this._callId,
    this.startCamera = true,
    this.beforeConnect,
    CallConnection? connection,
  }) : connection = connection ?? NativeCallConnection(),
       _owner = session.user?['public_id'] as String?,
       _generation = session.generation {
    session.addListener(_accountChanged);
    this.connection.addListener(_changed);
    _joining = Future<void>.microtask(_join);
  }
  final Session session;
  final String conversationId, title;
  final bool video;
  /// System incoming answers must never start a camera in the background.
  final bool startCamera;
  final Future<void> Function()? beforeConnect;
  Future<bool> get connected async {
    await _joining;
    return active && _setupComplete && !failed;
  }
  final CallConnection connection;
  final String? _owner;
  final int _generation;
  String? _callId;
  bool _ended = false, _closed = false, _disposed = false;
  bool muted = false, camOn = false, failed = false, mediaBusy = false;
  bool _setupComplete = false;
  String status = 'Connecting...';
  final _mediaGuard = CallMediaGuard();
  late final Future<void> _joining;
  Future<void>? _mediaChange;
  Future<bool>? _release;
  bool get ownerMatches =>
      _owner != null &&
      session.user?['public_id'] == _owner &&
      session.generation == _generation;
  bool get active => !_closed && !_disposed && ownerMatches;
  bool get closed => _closed;
  CallPresentation get presentation => failed
      ? CallPresentation(status, mediaAvailable: false)
      : presentCall(
          transport: connection.transport,
          setupComplete: _setupComplete,
          remoteCount: connection.remoteCount,
          previouslyConnected: _setupComplete,
        );

  void _changed() {
    if (_disposed) return;
    if (_setupComplete && active && !mediaBusy) {
      final microphone = connection.microphoneEnabled;
      final camera = connection.cameraEnabled;
      if (microphone != null) muted = !microphone;
      if (camera != null) camOn = camera;
    }
    notifyListeners();
  }

  void _accountChanged() {
    if (ownerMatches || _closed) return;
    // Never send an End action with a replacement login's credentials.
    unawaited(close(endRemote: false));
  }

  Future<void> _join() async {
    try {
      if (beforeConnect != null) {
        if (!active) return;
        await beforeConnect!();
        if (!active) return;
      }
      late Map<String, dynamic> token;
      final connected = await connectCallWhileActive(
        isActive: () => active,
        requestToken: () async {
          final query = _callId != null
              ? '?call=$_callId'
              : '?kind=${video ? 'video' : 'voice'}';
          token = await session.call(
            'POST',
            '/conversations/$conversationId/call-token$query',
          ) as Map<String, dynamic>;
          _callId = token['call_id'] as String? ?? _callId;
        },
        connect: () => connection.connect(
          token['url'] as String,
          token['token'] as String,
        ),
        microphone: () => connection.microphone(true),
        camera: () => connection.camera(true),
        video: video && startCamera,
      );
      if (!connected) {
        _endCall();
        await _disconnectSafely();
        return;
      }
      if (active) {
        _setupComplete = true;
        camOn = video && startCamera;
        _changed();
      }
    } on ApiError catch (error) {
      _endCall();
      await _disconnectSafely();
      if (active) {
        failed = true;
        status = error.message;
        _changed();
      }
    } catch (_) {
      _endCall();
      await _disconnectSafely();
      if (active) {
        failed = true;
        status = 'Could not start the call. Check your connection and microphone permission.';
        _changed();
      }
    }
  }

  void _endCall() {
    if (!ownerMatches || _ended || _callId == null) return;
    _ended = true;
    session
        .call('POST', '/calls/$_callId/action', body: {'action': 'end'})
        .catchError((_) => null);
  }

  Future<void> _disconnectSafely() async {
    try {
      await connection.disconnect();
    } catch (_) {}
  }

  Future<void> changeMedia({required bool camera}) async {
    if (!active || mediaBusy || failed || !connection.localAvailable) return;
    final pending = _changeMedia(camera: camera);
    _mediaChange = pending;
    try {
      await pending;
    } finally {
      if (identical(_mediaChange, pending)) _mediaChange = null;
    }
  }

  Future<void> _changeMedia({required bool camera}) async {
    mediaBusy = true;
    _changed();
    try {
      final next = camera ? !camOn : !muted;
      final applied = await _mediaGuard.change(
        isActive: () => active && !failed,
        apply: () =>
            camera ? connection.camera(next) : connection.microphone(!next),
        onFailure: () {
          if (active) {
            failed = true;
            status = 'Media controls failed. Leave this call. Microphone or camera state could not be confirmed.';
            _changed();
          }
          _endCall();
        },
        stopMicrophone: () => connection.microphone(false),
        stopCamera: () => connection.camera(false),
        disconnect: connection.disconnect,
      );
      if (applied && active) {
        if (camera) {
          camOn = next;
        } else {
          muted = next;
        }
      }
    } catch (_) {
      // A failed native mutation is terminal. Never turn controls back on.
    } finally {
      mediaBusy = false;
      _changed();
    }
  }

  /// False means native release could not be confirmed. A host must quarantine
  /// further calls rather than opening another microphone/camera owner.
  Future<bool> close({bool endRemote = true}) {
    if (_release != null) return _release!;
    final completed = Completer<bool>();
    _release = completed.future;
    _closed = true;
    if (endRemote) {
      _endCall();
    } else {
      _ended = true;
    }
    _changed();
    unawaited(
      _releaseConnection().then(
        completed.complete,
        onError: (Object error, StackTrace stack) => completed.complete(false),
      ),
    );
    return completed.future;
  }

  Future<bool> _releaseConnection() async {
    var confirmed = true;
    try {
      await connection.stopCapture();
    } catch (_) {
      confirmed = false;
    }
    try {
      await connection.disconnect();
    } catch (_) {
      confirmed = false;
    }
    try {
      await _joining;
    } catch (_) {
      confirmed = false;
    }
    try {
      await _mediaChange;
    } catch (_) {
      confirmed = false;
    }
    try {
      await connection.stopCapture();
    } catch (_) {
      confirmed = false;
    }
    try {
      await connection.disconnect();
    } catch (_) {
      confirmed = false;
    }
    try {
      await connection.dispose();
    } catch (_) {
      confirmed = false;
    }
    return confirmed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_accountChanged);
    connection.removeListener(_changed);
    unawaited(close());
    super.dispose();
  }
}

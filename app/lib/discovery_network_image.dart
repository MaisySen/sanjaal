import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// A decoded Discovery thumbnail is valid only for one visible result scope.
/// This is cache isolation, not server authorization or erasure of public URLs.
class DiscoveryImageScope {
  bool _active = true;
  bool get active => _active;
  int _inFlight = 0;
  final _waiting = <Completer<VoidCallback>>[];
  Future<VoidCallback> acquire() {
    if (!active) return Future.error(StateError('Expired preview'));
    if (_inFlight < 4) return SynchronousFuture(_lease());
    if (_waiting.length >= 48) {
      return Future.error(StateError('Preview queue is full'));
    }
    final pending = Completer<VoidCallback>();
    _waiting.add(pending);
    return pending.future;
  }

  VoidCallback _lease() {
    _inFlight++;
    bool released = false;
    return () {
      if (released) return;
      released = true;
      _inFlight--;
      if (active && _waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(_lease());
      }
    };
  }

  final _aborters = <VoidCallback>{};
  void attach(VoidCallback abort) {
    if (active) {
      _aborters.add(abort);
    } else {
      abort();
    }
  }

  void detach(VoidCallback abort) => _aborters.remove(abort);
  void retire() {
    _active = false;
    for (final pending in _waiting) {
      pending.completeError(StateError('Expired preview'));
    }
    _waiting.clear();
    for (final abort in _aborters.toList()) {
      abort();
    }
    _aborters.clear();
  }
}

class DiscoveryNetworkImage extends ImageProvider<DiscoveryNetworkImage> {
  const DiscoveryNetworkImage(this.url, this.scope);
  final Uri url;
  final DiscoveryImageScope scope;
  static const maxBytes = 4 * 1024 * 1024;
  // Key lookup must remain possible after retirement so ResizeImage.evict can
  // remove both pending and decoded entries without an asynchronous error.
  @override
  Future<DiscoveryNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    DiscoveryNetworkImage key,
    ImageErrorListener handleError,
  ) {
    if (!scope.active) {
      handleError(StateError('Expired preview'), StackTrace.current);
      return;
    }
    super.resolveStreamForKey(configuration, stream, key, handleError);
  }

  @override
  ImageStreamCompleter loadImage(
    DiscoveryNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final release = await scope.acquire();
    final client = http.Client();
    // Closing the client is required as well as timing out the future. A slow
    // stream must not continue buffering after the visible result expires.
    bool timedOut = false;
    final abort = client.close;
    scope.attach(abort);
    final timeout = Timer(const Duration(seconds: 15), () {
      timedOut = true;
      client.close();
    });
    try {
      if (!scope.active) throw StateError('Expired preview');
      final request = http.Request('GET', url)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
            'image/',
          ) ||
          (response.contentLength ?? 0) > maxBytes) {
        throw StateError('Unavailable preview');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (timedOut ||
            !scope.active ||
            bytes.length + chunk.length > maxBytes) {
          throw StateError('Expired or oversized preview');
        }
        bytes.add(chunk);
      }
      if (timedOut || !scope.active || bytes.isEmpty) {
        throw StateError('Expired or empty preview');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes.takeBytes());
      if (!scope.active) {
        buffer.dispose();
        throw StateError('Expired preview');
      }
      final codec = await decode(buffer);
      if (!scope.active) {
        codec.dispose();
        throw StateError('Expired preview');
      }
      return codec;
    } finally {
      scope.detach(abort);
      timeout.cancel();
      client.close();
      release();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveryNetworkImage &&
      identical(scope, other.scope) &&
      url == other.url;
  @override
  int get hashCode => Object.hash(identityHashCode(scope), url);
}

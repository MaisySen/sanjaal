import 'dart:async';
import 'package:flutter/services.dart';

/// One bounded local first-frame decode, never a network URL or grid player.
/// A missing/unsupported extractor must not prevent publishing the video.
class VideoPoster {
  static const channel = MethodChannel('au.fintex.sanjaal/video-poster');
  static bool _busy = false;
  static Future<Uint8List?> fromPath(String path) async {
    if (_busy || path.isEmpty || path.contains('://')) return null;
    _busy = true;
    try {
      final value = await channel.invokeMethod<Uint8List>('extract', {'path': path}).timeout(const Duration(seconds: 8));
      if (value == null || value.isEmpty || value.length > 256 * 1024) return null;
      return Uint8List.fromList(value).asUnmodifiableView();
    } catch (_) { return null; }
    finally { _busy = false; }
  }
}

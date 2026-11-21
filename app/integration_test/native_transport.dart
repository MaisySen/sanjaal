// Local-native harness only. Real HTTP except the explicit offline interval.
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sanjaal/api.dart' show resetApiKeepAlive;

class NativeTransport extends http.BaseClient {
  final http.Client _real;
  NativeTransport({http.Client? real}) : _real = real ?? IOClient(HttpClient());
  bool offline = false;
  int pending = 0;
  int rejected = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline && request.url.path.startsWith('/api/v1/')) {
      rejected++;
      throw const SocketException('Disposable native fixture connection unavailable');
    }
    pending++;
    try {
      final response = await _real.send(request);
      Stream<List<int>> body() async* {
        try { yield* response.stream; } finally { pending--; }
      }
      return http.StreamedResponse(body(), response.statusCode,
        contentLength: response.contentLength, request: response.request,
        headers: response.headers, isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase);
    } catch (_) { pending--; rethrow; }
  }
  Future<void> idle() async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (pending != 0) {
      if (DateTime.now().isAfter(end)) throw StateError('Native fixture requests did not drain');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    // Let response consumers finish decoding and clearing their old status.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  // http top-level helpers close their temporary client. This scope owns it.
  @override
  void close() {}
  void dispose() => _real.close();
}
Future<T> withNativeTransport<T>(Future<T> Function(NativeTransport) body) async {
  final transport = NativeTransport();
  resetApiKeepAlive();
  try { return await http.runWithClient(() => body(transport), () => transport); }
  finally { resetApiKeepAlive(); transport.dispose(); }
}

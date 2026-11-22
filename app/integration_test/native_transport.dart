// Disposable native fixture socket control, not physical network-loss proof.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sanjaal/api.dart';

class NativeTransport {
  final http.Client _control = IOClient(HttpClient());
  static const base = String.fromEnvironment('E2E_TOKEN_BASE');
  static const token = String.fromEnvironment('E2E_TOKEN');
  Map<String,dynamic> last = {};
  Future<Map<String,dynamic>> setOffline(bool value) async {
    final uri = Uri.parse(base);
    if (!['localhost','127.0.0.1','10.0.2.2'].contains(uri.host) || uri.port != 8002 || token.isEmpty) {
      throw StateError('Socket gate requires the isolated native fixture route');
    }
    final response = await _control.post(Uri.parse('$base/_native/transport'),
      headers: {'Authorization':'Bearer $token','Content-Type':'application/json'},
      body: jsonEncode({'offline':value})).timeout(const Duration(seconds:8));
    if(response.statusCode != 200) throw StateError('Native socket gate did not drain');
    last = jsonDecode(response.body) as Map<String,dynamic>;
    if(last['offline']!=value || last['active']!=0) throw StateError('Native socket gate state mismatch');
    return last;
  }
  Future<bool> proveOffline(Session session) async {
    final before = await setOffline(true);
    if((before['forwarded_api'] as int) < 1) return false;
    var failed = false;
    try { await session.call('GET','/calls/incoming'); }
    on ApiError { failed = true; }
    final after = await setOffline(true);
    return failed && session.offline && (after['rejected'] as int) > (before['rejected'] as int);
  }
  Future<bool> proveOnline(Session session) async {
    final before = await setOffline(false);
    await session.call('GET','/calls/incoming');
    final after = await setOffline(false);
    return !session.offline && (after['forwarded_api'] as int) > (before['forwarded_api'] as int);
  }
  void dispose()=>_control.close();
}
Future<T> withNativeTransport<T>(Future<T> Function(NativeTransport) body) async {
  final transport=NativeTransport();
  try { return await body(transport); }
  finally { transport.dispose(); }
}

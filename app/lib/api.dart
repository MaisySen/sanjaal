import 'dart:async';
import 'push.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apiBase = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'https://sanjaal-api.onrender.com/api/v1');
const auth0Domain = 'dev-rymtbo3wlo3tzsxv.us.auth0.com';

/// Test builds only: a base URL that answers the token request instead of Auth0 (the emulator test uses a
/// local fixture). Empty in every normal and release build. It is a client setting; the API still checks
/// every token's signature, issuer, audience and expiry.
const _tokenBase = String.fromEnvironment('E2E_TOKEN_BASE');

/// True in release and profile builds. A build like that with E2E_TOKEN_BASE set refuses to sign in.
const _isProductBuild = bool.fromEnvironment('dart.vm.product');
const auth0ClientId = 'fKyNH32VRbrAFF1DUX3GRhKRW7gMR8yT';
const auth0Audience = 'https://api.sanjaal.app';
const socialScheme = 'au.fintex.sanjaal';
const socialRedirect = '$socialScheme://login-callback';
const _wait = Duration(seconds: 90); // free hosts sleep and need about a minute to wake

class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

String _errorText(http.Response r) {
  try {
    final j = jsonDecode(r.body);
    if (j is Map) {
      final errs = j['errors'];
      if (errs is Map && errs.isNotEmpty) {
        final first = errs.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      for (final k in ['message', 'error_description', 'description', 'error']) {
        if (j[k] is String && (j[k] as String).isNotEmpty) return j[k] as String;
      }
    }
  } catch (_) {}
  return 'Request failed (${r.statusCode})';
}

/// Holds the Auth0 session and makes authenticated API calls.
class Session extends ChangeNotifier {
  String? _access;
  String? _refresh;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? user;
  bool loading = true;
  /// Sign-in header for files that need it (chat photos). Used by widgets that cannot await.
  Map<String, String> get mediaHeaders => {if (_access != null) 'Authorization': 'Bearer $_access'};

  /// Downloads a file that needs sign-in, such as a chat voice message.
  Future<Uint8List> fetchBytes(String url) async {
    final token = await _token();
    final r = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'}).timeout(_wait);
    if (r.statusCode != 200) throw ApiError('Could not load this file.', r.statusCode);
    return r.bodyBytes;
  }

  /// True after a request failed for lack of a connection; cleared by the next response.
  bool offline = false;
  void setOffline(bool v) {
    if (offline == v) return;
    offline = v;
    notifyListeners();
  }

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    _refresh = p.getString('refresh_token');
    if (_refresh != null) {
      try {
        await _grant({'grant_type': 'refresh_token', 'refresh_token': _refresh!});
        await _loadMe();
      } on ApiError catch (e) {
        // Only a rejected refresh token ends the session. A network error keeps it.
        if (e.status == 400 || e.status == 401 || e.status == 403) {
          await _clear();
        }
      } catch (_) {}
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _grant(Map<String, String> form) async {
    if (_tokenBase.isNotEmpty && _isProductBuild) {
      throw ApiError('This build is not allowed to use a test token endpoint.');
    }
    final http.Response r;
    try {
      r = await http
          .post(_tokenBase.isEmpty ? Uri.https(auth0Domain, '/oauth/token') : Uri.parse('$_tokenBase/oauth/token'), body: {...form, 'client_id': auth0ClientId})
          .timeout(_wait);
    } on TimeoutException {
      throw ApiError('The server took too long. Try again.');
    } catch (_) {
      throw ApiError('No connection. Check your internet and try again.');
    }
    if (r.statusCode != 200) {
      var msg = _errorText(r);
      if (msg.toLowerCase().contains('wrong email or password')) msg = 'Wrong email or password.';
      throw ApiError(msg, r.statusCode);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    _access = j['access_token'] as String;
    _expires = DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    final rt = j['refresh_token'] as String?;
    if (rt != null) {
      _refresh = rt;
      final p = await SharedPreferences.getInstance();
      await p.setString('refresh_token', rt);
    }
  }

  Future<void> login(String id, String password) async {
    await _grant({
      'grant_type': 'password',
      'username': id,
      'password': password,
      'audience': auth0Audience,
      'scope': 'openid profile email offline_access',
    });
    await _loadMe();
    notifyListeners();
  }

  /// Social sign in through Auth0 with PKCE. [connection] is an Auth0 connection name,
  /// for example google-oauth2 or facebook. Uses Auth0 development keys until we have our own.
  Future<void> loginSocial(String connection) async {
    final rnd = Random.secure();
    final verifier = base64UrlEncode(List<int>.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final state = base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final url = Uri.https(auth0Domain, '/authorize', {
      'response_type': 'code',
      'client_id': auth0ClientId,
      'redirect_uri': socialRedirect,
      'scope': 'openid profile email offline_access',
      'audience': auth0Audience,
      'connection': connection,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: socialScheme);
    } catch (_) {
      throw ApiError('Sign in was cancelled.');
    }
    final back = Uri.parse(result);
    if (back.queryParameters['state'] != state) throw ApiError('Sign in failed. Try again.');
    final err = back.queryParameters['error_description'] ?? back.queryParameters['error'];
    if (err != null) throw ApiError(err);
    final code = back.queryParameters['code'];
    if (code == null) throw ApiError('Sign in failed. Try again.');
    await _grant({
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': socialRedirect,
    });
    await _loadMe();
    notifyListeners();
  }

  Future<void> register(String email, String username, String password) async {
    final http.Response r;
    try {
      r = await http
          .post(Uri.https(auth0Domain, '/dbconnections/signup'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'client_id': auth0ClientId,
                'email': email,
                'username': username,
                'password': password,
                'connection': 'Username-Password-Authentication',
              }))
          .timeout(_wait);
    } catch (_) {
      throw ApiError('No connection. Check your internet and try again.');
    }
    if (r.statusCode != 200) {
      var msg = _errorText(r);
      if (msg.contains('user already exists') || msg.contains('already exists')) {
        msg = 'That email or username is already taken.';
      }
      throw ApiError(msg, r.statusCode);
    }
    await login(email, password);
  }

  Future<void> _loadMe() async {
    final j = await call('GET', '/auth/me') as Map<String, dynamic>;
    user = (j['user'] ?? j) as Map<String, dynamic>;
    unawaited(Push.register(this));
  }

  Future<void> logout() async {
    await Push.unregister(this);
    await _clear();
    notifyListeners();
  }

  Future<void> _clear() async {
    _access = null;
    _refresh = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('refresh_token');
  }

  Future<String> _token() async {
    if (_access != null && DateTime.now().isBefore(_expires.subtract(const Duration(seconds: 60)))) {
      return _access!;
    }
    if (_refresh == null) throw ApiError('Please sign in again.', 401);
    await _grant({'grant_type': 'refresh_token', 'refresh_token': _refresh!});
    return _access!;
  }

  Future<dynamic> call(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$apiBase$path').replace(queryParameters: query);
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _token();
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      };
      final http.Response r;
      try {
        final enc = body == null ? null : jsonEncode(body);
        final f = switch (method) {
          'GET' => http.get(uri, headers: headers),
          'POST' => http.post(uri, headers: headers, body: enc),
          'PATCH' => http.patch(uri, headers: headers, body: enc),
          'DELETE' => http.delete(uri, headers: headers),
          _ => throw ArgumentError(method),
        };
        r = await f.timeout(_wait);
      } on ApiError {
        rethrow;
      } on TimeoutException {
        throw ApiError('The server took too long. Try again.');
      } catch (_) {
        setOffline(true);
        throw ApiError('No connection. Check your internet and try again.');
      }
      setOffline(false);
      if (r.statusCode == 401 && attempt == 0) {
        _expires = DateTime.fromMillisecondsSinceEpoch(0);
        continue;
      }
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return r.body.isEmpty ? null : jsonDecode(r.body);
      }
      throw ApiError(_errorText(r), r.statusCode);
    }
    throw ApiError('Please sign in again.', 401);
  }

  /// Posts text and up to 4 files. [files] are (bytes, mime, filename).
  Future<Map<String, dynamic>> createPost(String body, {List<UploadFile> files = const [], bool reel = false}) async {
    final token = await _token();
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase/posts'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..fields['kind'] = reel ? 'reel' : 'post';
    if (body.isNotEmpty) req.fields['body'] = body;
    for (final f in files) {
      req.files.add(http.MultipartFile.fromBytes('media[]', f.bytes, filename: f.name, contentType: MediaType.parse(f.mime)));
    }
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(_wait));
    } catch (_) {
      throw ApiError('Upload failed. Check your connection and try again.');
    }
    if (r.statusCode != 201 && r.statusCode != 200) throw ApiError(_errorText(r), r.statusCode);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['post'] ?? j) as Map<String, dynamic>;
  }

  /// Multipart POST with one optional file. Returns the decoded JSON object.
  Future<Map<String, dynamic>> upload(String path, {Map<String, String> fields = const {}, String field = 'media', UploadFile? file}) async {
    final token = await _token();
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields);
    if (file != null) {
      req.files.add(http.MultipartFile.fromBytes(field, file.bytes, filename: file.name, contentType: MediaType.parse(file.mime)));
    }
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(_wait));
    } catch (_) {
      throw ApiError('Upload failed. Check your connection and try again.');
    }
    if (r.statusCode != 200 && r.statusCode != 201) throw ApiError(_errorText(r), r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> uploadAvatar(UploadFile f) async {
    final token = await _token();
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase/auth/me/avatar'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..files.add(http.MultipartFile.fromBytes('avatar', f.bytes, filename: f.name, contentType: MediaType.parse(f.mime)));
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(_wait));
    } catch (_) {
      throw ApiError('Upload failed. Check your connection and try again.');
    }
    if (r.statusCode != 200) throw ApiError(_errorText(r), r.statusCode);
    user = {...?user, ...((jsonDecode(r.body) as Map)['user'] as Map).cast<String, dynamic>()};
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final j = await call('PATCH', '/auth/me', body: fields) as Map<String, dynamic>;
    user = {...?user, ...(j['user'] as Map).cast<String, dynamic>()};
    notifyListeners();
  }
}

class UploadFile {
  UploadFile(this.bytes, this.mime, this.name);
  final List<int> bytes;
  final String mime;
  final String name;
}

String mimeFor(String name, {bool video = false}) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.mov')) return 'video/quicktime';
  return video ? 'video/mp4' : 'image/jpeg';
}

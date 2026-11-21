import 'dart:async';
import 'push.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'refresh_store.dart';

const apiBase = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'https://sanjaal-api.onrender.com/api/v1');
const auth0Domain = 'dev-rymtbo3wlo3tzsxv.us.auth0.com';

/// Test builds only: a base URL that answers auth requests instead of Auth0 (the emulator test uses a
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

/// One keep-alive client for every API request, so a screen does not pay a new DNS, TCP and TLS
/// handshake to the far-away host on each call. Flutter tests install their own client per zone through
/// http.runWithClient, so under test the top-level functions are used and nothing is shared.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');
/// Regression tests turn this on to exercise the production keep-alive path.
@visibleForTesting
bool apiKeepAliveInTests = false;
@visibleForTesting
void resetApiKeepAlive() { _sharedHttp?.close(); _sharedHttp = null; }
http.Client? _sharedHttp;
http.Client get _keepAlive => _sharedHttp ??= http.Client();

class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Only the identity provider's explicit rejection of this refresh grant can
/// end a stored session during startup. HTTP status alone is not that proof.
class _RejectedRefresh extends ApiError {
  _RejectedRefresh(super.message, super.status);
}

/// Validate the native browser result before exchanging an authorization code.
/// State and PKCE remain required; an unexpected redirect shape is not a login.
@visibleForTesting
String socialCallbackCode(String result, String expectedState) {
  final Uri back;
  try { back = Uri.parse(result); } catch (_) { throw ApiError('Sign in failed. Try again.'); }
  final redirect = Uri.parse(socialRedirect);
  final fields = back.queryParametersAll;
  if (back.scheme != redirect.scheme || back.host != redirect.host ||
      back.path != redirect.path || back.hasPort || back.userInfo.isNotEmpty ||
      back.hasFragment || fields.values.any((v)=>v.length != 1) ||
      expectedState.isEmpty || fields['state']?.single != expectedState) {
    throw ApiError('Sign in failed. Try again.');
  }
  final error = back.queryParameters['error_description'] ?? back.queryParameters['error'];
  if (error != null) {
    throw ApiError(back.queryParameters['error'] == 'access_denied'
        ? 'Sign in was cancelled.' : 'Sign in failed. Try again.');
  }
  final code = back.queryParameters['code'];
  if (code == null || code.trim().isEmpty) throw ApiError('Sign in failed. Try again.');
  return code;
}

/// Stable per-draft key, never an account credential.
String newUploadIntent() => List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

class UploadError extends ApiError {
  UploadError(String message, {int? status, this.code, this.resourceId, this.uncertain = false}) : super(message, status);
  final String? code;
  final String? resourceId;
  final bool uncertain;
  bool get terminal => code == 'upload_intent_conflict' || code == 'upload_intent_gone' || uncertain;
}

UploadError _uploadFailure(http.Response r, {bool replaySafe = false}) {
  Map<String, dynamic> data = {};
  try { data = (jsonDecode(r.body) as Map).cast<String, dynamic>(); } catch (_) {}
  // Error metadata is untrusted too. A malformed optional field must not
  // throw a TypeError and bypass the uncertainty/terminal retry guard.
  String? text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
  final code = text(data['code']);
  final resourceId = text(data['resource_id']);
  final message = switch(code) {
    'upload_intent_conflict' => 'This draft was already shared with different content.',
    'upload_intent_gone' => 'The original upload was removed or expired.',
    _ => !replaySafe && r.statusCode >= 500 ? 'The upload result is unknown. Check your posts or stories before sharing again.' : _errorText(r),
  };
  return UploadError(message, status: r.statusCode, code: code, resourceId: resourceId, uncertain: !replaySafe && r.statusCode >= 500);
}

UploadError _interruptedUpload(bool replaySafe) => UploadError(
  replaySafe ? 'Upload interrupted. Your draft is kept. Retry to check the original result.' : 'The upload result is unknown. Check your posts or stories before sharing again.', uncertain: !replaySafe,
);

Map<String, dynamic> _uploadResult(http.Response r, String operation, bool replaySafe) {
  try {
    final value = (jsonDecode(r.body) as Map).cast<String, dynamic>();
    if (value[operation] is! Map) throw const FormatException('Missing uploaded resource');
    return value;
  } catch (_) { throw _interruptedUpload(replaySafe); }
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
class _ProgressMultipart extends http.MultipartRequest {
  _ProgressMultipart(super.method, super.url, this.progress);
  final void Function(double?) progress;
  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    progress(0);
    return http.ByteStream(stream.transform(StreamTransformer.fromHandlers(handleData: (List<int> data, EventSink<List<int>> sink) {
      sent += data.length;
      progress(total == 0 ? null : (sent / total).clamp(0.0, 1.0));
      sink.add(data);
    })));
  }
}

class Session extends ChangeNotifier {
  Session({Future<void> Function(Session)? unregisterPush})
      : _unregisterPush = unregisterPush ?? Push.unregister;
  final Future<void> Function(Session) _unregisterPush;
  final uploadProgress = ValueNotifier<double?>(null);
  int _uploadRequest = 0;
  http.MultipartRequest _trackedUpload(String path) {
    final request = ++_uploadRequest;
    final account = user?['public_id'];
    final epoch = _sessionEpoch;
    return _ProgressMultipart('POST', Uri.parse('$apiBase$path'), (value) {
      if (request == _uploadRequest && epoch == _sessionEpoch && account == user?['public_id']) uploadProgress.value = value;
    });
  }
  String? _access;
  String? _refresh;
  Future<void>? _refreshingAccess;
  int _sessionEpoch = 0;
  int get generation => _sessionEpoch;
  Future<void> _credentialWrites = Future<void>.value();
  void _checkSession(int epoch) {
    if (epoch != _sessionEpoch) throw ApiError('Please sign in again.', 401);
  }
  Future<void> _writeCredentials(Future<void> Function() action) {
    final next = _credentialWrites.then((_) => action());
    _credentialWrites = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? user;
  bool pollsEnabled = false;
  bool uploadIntentsEnabled = false;
  bool interactionControlsEnabled = false;
  bool protectedStoriesEnabled = false;
  bool groupMemberRefsEnabled = false;
  bool videoPostersEnabled = false;
  bool loading = true;
  /// Credentials belong to this API, never to a URL's claimed purpose.
  bool supportsPrivateMedia(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && ['http','https'].contains(uri.scheme) && uri.hasAuthority && uri.userInfo.isEmpty && uri.origin == Uri.parse(apiBase).origin;
  }
  Map<String, String> mediaHeadersFor(String url) => {
    if (supportsPrivateMedia(url) && _access != null) 'Authorization': 'Bearer $_access',
  };

  /// Downloads private chat audio without following a redirect or returning an
  /// old member's bytes after a session identity change.
  Future<Uint8List> fetchBytes(String url) async {
    final epoch = _sessionEpoch;
    if (!supportsPrivateMedia(url)) throw ApiError('This private media link is not supported.');
    final account = user?['public_id'];
    final headers = await privateMediaHeaders(url);
    _checkSession(epoch);
    if (account == null || account != user?['public_id']) throw ApiError('Please sign in again.',401);
    final request = http.Request('GET',Uri.parse(url))..followRedirects = false;
    request.headers.addAll(headers);
    final r = await http.Response.fromStream(await request.send().timeout(_wait)).timeout(_wait);
    _checkSession(epoch);
    if (account != user?['public_id']) throw ApiError('Please sign in again.',401);
    if (r.statusCode != 200) throw ApiError('Could not load this file.', r.statusCode);
    return r.bodyBytes;
  }

  /// Protected story routes are same-origin. Never send a sign-in header to a
  /// URL supplied by an unrelated host or through an object-storage redirect.
  Future<Map<String, String>> privateMediaHeaders(String url) async {
    final epoch = _sessionEpoch;
    if (!supportsPrivateMedia(url)) {
      throw ApiError('This private media link is not supported.');
    }
    final token = await _token();
    _checkSession(epoch);
    return {'Authorization': 'Bearer $token'};
  }
  Future<Uint8List> fetchProtectedBytes(String url) async {
    final epoch = _sessionEpoch;
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.Request('GET', Uri.parse(url))..followRedirects = false;
      request.headers.addAll(await privateMediaHeaders(url));
      _checkSession(epoch);
      final result = await http.Response.fromStream(await request.send().timeout(_wait)).timeout(_wait);
      _checkSession(epoch);
      if (result.statusCode == 401 && attempt == 0) { _expires = DateTime.fromMillisecondsSinceEpoch(0); continue; }
      if (result.statusCode != 200) throw ApiError('This story is unavailable. It may have expired or its audience changed.',result.statusCode);
      return result.bodyBytes;
    }
    throw ApiError('Please sign in again.',401);
  }

  /// True after a request failed for lack of a connection; cleared by the next response.
  bool offline = false;
  void setOffline(bool v) {
    if (offline == v) return;
    offline = v;
    notifyListeners();
  }

  /// A cold-start failure is not a sign-out. No cached identity is opened until
  /// both the refresh grant and the account read have succeeded.
  String? restoreError;
  bool _restoring = false;
  Future<void> restore() async {
    if (_restoring) return;
    _restoring = true;
    final epoch = _sessionEpoch;
    loading = true;
    restoreError = null;
    notifyListeners();
    try {
      String? stored;
      await _writeCredentials(() async {
        _checkSession(epoch);
        stored = await RefreshStore.read();
        _checkSession(epoch);
      });
      _refresh = stored;
      if (_refresh == null) return;
      try {
        await _grant({'grant_type': 'refresh_token', 'refresh_token': _refresh!});
      } on _RejectedRefresh {
        _checkSession(epoch);
        await _clear();
        return;
      }
      await _loadMe();
    } catch (_) {
      // Storage, transport, service/configuration errors and a failed /auth/me
      // read must not erase the saved grant or pretend there is no session.
      if (epoch == _sessionEpoch) restoreError = 'Could not restore your sign-in. Try again.';
    } finally {
      _restoring = false;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _grant(Map<String, String> form) async {
    final epoch = _sessionEpoch;
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
    _checkSession(epoch);
    if (r.statusCode != 200) {
      if (form['grant_type'] == 'refresh_token') {
        try {
          if ((jsonDecode(r.body) as Map)['error'] == 'invalid_grant') {
            throw _RejectedRefresh(_errorText(r), r.statusCode);
          }
        } on _RejectedRefresh { rethrow; } catch (_) {}
      }
      String? code;
      try { code = (jsonDecode(r.body) as Map)['error'] as String?; } catch (_) {}
      throw ApiError(
        r.statusCode == 429 ? 'Too many attempts. Wait a moment, then try again.'
            : code == 'invalid_grant' ? 'Wrong email or password.'
            : 'Sign in failed. Try again.', r.statusCode);
    }
    // Validate the whole grant before touching Keychain/Keystore. A malformed
    // HTTP 200 must not clear or replace a previously saved credential.
    final Map<String, dynamic> j;
    final DateTime expires;
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['access_token'] is! String || (j['access_token'] as String).trim().isEmpty ||
          (j['refresh_token'] != null && (j['refresh_token'] is! String || (j['refresh_token'] as String).trim().isEmpty)) ||
          (j['expires_in'] != null && (j['expires_in'] is! num || !(j['expires_in'] as num).isFinite || (j['expires_in'] as num) < 0))) {
        throw const FormatException('Malformed credential response');
      }
      expires = DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    } catch (_) {
      throw ApiError('Sign in failed. Try again.');
    }
    final rt = j['refresh_token'] as String?;
    try {
      await _writeCredentials(() async {
        _checkSession(epoch);
        if (rt != null) {
          await RefreshStore.write(rt);
          _checkSession(epoch);
          _refresh = rt;
        } else if (form['grant_type'] != 'refresh_token') {
          // A new login must never inherit a different account's refresh token.
          await RefreshStore.clear();
          _checkSession(epoch);
          _refresh = null;
        }
      });
    } catch (_) {
      throw ApiError('Could not save your sign-in securely. Try again.');
    }
    _checkSession(epoch);
    _access = j['access_token'] as String;
    _expires = expires;
  }

  Future<void> login(String id, String password) async {
    _sessionEpoch++;
    // Retire account-bound views/capture before waiting for replacement auth.
    notifyListeners();
    _home = null;
    _homeData = null;
    _refreshingAccess = null;
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
    final epoch = ++_sessionEpoch;
    notifyListeners();
    _refreshingAccess = null;
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
    _checkSession(epoch);
    final code = socialCallbackCode(result,state);
    await _grant({
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': socialRedirect,
    });
    await _loadMe();
    notifyListeners();
  }

  int _registrationAttempt = 0;
  Future<void> register(String email, String username, String password) async {
    final epoch = _sessionEpoch;
    final attempt = ++_registrationAttempt;
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
    // Account creation can finish remotely after this view is superseded.
    // Its automatic login must never replace a newer login or registration.
    _checkSession(epoch);
    if (attempt != _registrationAttempt) throw ApiError('Please sign in again.', 401);
    if (r.statusCode != 200) {
      String? code;
      try { code = (jsonDecode(r.body) as Map)['code'] as String?; } catch (_) {}
      throw ApiError(
        r.statusCode == 429 ? 'Too many attempts. Wait a moment, then try again.'
            : code == 'user_exists' || code == 'username_exists'
                ? 'That email or username is already taken.'
            : code == 'invalid_password' || code == 'password_strength_error'
                ? 'Your password does not meet the account security rules. Choose a stronger password.'
            : 'Could not create your account. Try again.', r.statusCode);
    }
    try {
      await login(email, password);
    } catch (_) {
      throw ApiError('Your account was created. Sign in to continue.');
    }
  }

  DateTime? _resetRequestedAt;
  bool _resetPending = false;

  Future<void> requestPasswordReset(String email) async {
    if (_tokenBase.isNotEmpty && _isProductBuild) {
      throw ApiError('This build is not allowed to use a test token endpoint.');
    }
    final clean = email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) {
      throw ApiError('Enter a valid email');
    }
    if (_resetPending || (_resetRequestedAt != null &&
        DateTime.now().difference(_resetRequestedAt!) < const Duration(minutes: 1))) {
      throw ApiError('Wait a minute before requesting another reset link.');
    }
    _resetPending = true;
    _resetRequestedAt = DateTime.now();
    try {
      final response = await http.post(
        _tokenBase.isEmpty
            ? Uri.https(auth0Domain, '/dbconnections/change_password')
            : Uri.parse('$_tokenBase/dbconnections/change_password'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'client_id': auth0ClientId,
          'email': clean,
          'connection': 'Username-Password-Authentication',
        }),
      ).timeout(_wait);
      // The documented not-found response gets the same neutral UI. Never
      // disclose account existence or treat provider response prose as UI copy.
      if (response.statusCode == 200 || response.statusCode == 404) return;
      throw ApiError(response.statusCode == 429
          ? 'Too many attempts. Wait a moment, then try again.'
          : 'Could not send the reset link. Try again.', response.statusCode);
    } on TimeoutException {
      throw ApiError('The server took too long. Try again.');
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('No connection. Check your internet and try again.');
    } finally {
      _resetPending = false;
    }
  }

  Future<void> _loadMe() async {
    final epoch = _sessionEpoch;
    final j = await call('GET', '/auth/me') as Map<String, dynamic>;
    _checkSession(epoch);
    user = (j['user'] ?? j) as Map<String, dynamic>;
    pollsEnabled = (j['features'] as Map?)?['polls'] == true;
    uploadIntentsEnabled = (j['features'] as Map?)?['upload_intents'] == true;
    interactionControlsEnabled = (j['features'] as Map?)?['interaction_controls'] == true;
    protectedStoriesEnabled = (j['features'] as Map?)?['protected_stories'] == true;
    groupMemberRefsEnabled = (j['features'] as Map?)?['group_member_refs'] == true;
    videoPostersEnabled = (j['features'] as Map?)?['video_posters'] == true;
    unawaited(Push.register(this));
  }

  /// Capture only the fixed device-removal request before local sign-out. The
  /// callback never refreshes credentials, reads a replacement session, follows
  /// redirects or updates local identity. Local FCM invalidation still runs if
  /// this old access token is expired or removal fails offline.
  Future<void> Function(String) capturePushRemoval() {
    final access = _access;
    final owner = user?['public_id'];
    return (String token) async {
      if (owner == null || access == null) throw ApiError('Please sign in again.', 401);
      final request = http.Request('POST', Uri.parse('$apiBase/devices/remove'))
        ..followRedirects = false
        ..headers.addAll({'Authorization': 'Bearer $access', 'Content-Type': 'application/json'})
        ..body = jsonEncode({'token': token});
      final result = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 10)))
          .timeout(const Duration(seconds: 10));
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw ApiError('Notification token cleanup could not be confirmed.', result.statusCode);
      }
    };
  }

  Future<void> logout() async {
    // Stop push registration synchronously, then invalidate local work before
    // waiting for network/device cleanup. No late cleanup may clear a new login.
    final cleanup = _unregisterPush(this);
    final clearing = _clear();
    notifyListeners();
    await Future.wait([clearing, cleanup]);
  }

  Future<void> _clear() async {
    _sessionEpoch++;
    _home = null;
    _homeData = null;
    _refreshingAccess = null;
    _uploadRequest++;
    _access = null;
    _refresh = null;
    user = null;
    pollsEnabled = false;
    uploadIntentsEnabled = false;
    interactionControlsEnabled = false;
    protectedStoriesEnabled = false;
    groupMemberRefsEnabled = false;
    videoPostersEnabled = false;
    await _writeCredentials(RefreshStore.clear);
  }

  Future<String> _token() async {
    if (_access != null && DateTime.now().isBefore(_expires.subtract(const Duration(seconds: 60)))) {
      return _access!;
    }
    final epoch = _sessionEpoch;
    if (_refresh == null) throw ApiError('Please sign in again.', 401);
    // Home, stories and polling can all need the same expired token. Share one
    // exchange instead of concurrently reusing the same refresh credential.
    final pending = _refreshingAccess;
    if (pending != null) {
      await pending;
    } else {
      final exchange = _grant({'grant_type': 'refresh_token', 'refresh_token': _refresh!});
      _refreshingAccess = exchange;
      try {
        await exchange;
      } finally {
        if (identical(_refreshingAccess, exchange)) _refreshingAccess = null;
      }
    }
    _checkSession(epoch);
    return _access!;
  }

  /// Home opens with one request for feed, stories and unread. Each part is handed over once, only
  /// within seconds of being fetched and only to the session epoch that asked. Any failure falls back to
  /// the screens' own requests. Tests turn this off unless they exercise it.
  @visibleForTesting
  bool homeBundleEnabled = !_underTest;
  Future<Map<String, dynamic>?>? _home;
  Map<String, dynamic>? _homeData;
  int _homeEpoch = -1;
  DateTime _homeAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get homePending => _home != null;

  void prefetchHome() {
    if (!homeBundleEnabled) return;
    final epoch = _sessionEpoch;
    _homeEpoch = epoch;
    _homeData = null;
    _homeAt = DateTime.now();
    _home = call('GET', '/home').then<Map<String, dynamic>?>((v) {
      if (epoch != _sessionEpoch || v is! Map) return null;
      // Freshness runs from when the reply arrived, not when it was asked for: a slow or cold
      // request must not expire its own answer and trigger duplicate requests.
      _homeAt = DateTime.now();
      return v.cast<String, dynamic>();
    }).catchError((Object _) => null);
  }

  /// Returns the named part of the Home bundle once, or null so the caller makes its own request.
  Future<dynamic> takeHome(String key) async {
    final pending = _home;
    if (pending == null) return null;
    final epoch = _homeEpoch;
    final received = await pending;
    // An old completion must not write or clear a replacement account/request's bundle.
    if (epoch != _sessionEpoch || !identical(pending, _home)) return null;
    _homeData ??= received;
    final data = _homeData;
    if (data == null || DateTime.now().difference(_homeAt) > const Duration(seconds: 5)) {
      _home = null;
      _homeData = null;
      return null;
    }
    return data.remove(key);
  }

  Future<dynamic> call(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final epoch = _sessionEpoch;
    final uri = Uri.parse('$apiBase$path').replace(queryParameters: query);
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _token();
      _checkSession(epoch);
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      };
      final http.Response r;
      try {
        final enc = body == null ? null : jsonEncode(body);
        final c = _underTest && !apiKeepAliveInTests ? null : _keepAlive;
        final f = switch (method) {
          'GET' => c?.get(uri, headers: headers) ?? http.get(uri, headers: headers),
          'POST' => c?.post(uri, headers: headers, body: enc) ?? http.post(uri, headers: headers, body: enc),
          'PATCH' => c?.patch(uri, headers: headers, body: enc) ?? http.patch(uri, headers: headers, body: enc),
          'PUT' => c?.put(uri, headers: headers, body: enc) ?? http.put(uri, headers: headers, body: enc),
          'DELETE' => c?.delete(uri, headers: headers) ?? http.delete(uri, headers: headers),
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
      _checkSession(epoch);
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
  Future<Map<String, dynamic>> createPost(String body, {List<UploadFile> files = const [], bool reel = false, List<String>? pollOptions, String? intent}) async {
    final epoch = _sessionEpoch;
    final replaySafe = uploadIntentsEnabled && intent != null;
    final account = user?['public_id'];
    final token = await _token();
    _checkSession(epoch);
    if (account == null || account != user?['public_id']) throw ApiError('Please sign in again.', 401);
    final req = _trackedUpload('/posts')
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..fields['kind'] = reel ? 'reel' : 'post';
    if (replaySafe) req.fields['upload_intent'] = intent;
    if (body.isNotEmpty) req.fields['body'] = body;
    if (pollOptions != null) {
      for (var i = 0; i < pollOptions.length; i++) {
        req.fields['poll_options[$i]'] = pollOptions[i];
      }
    }
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      req.files.add(http.MultipartFile.fromBytes('media[]', f.bytes, filename: f.name, contentType: MediaType.parse(f.mime)));
      if (videoPostersEnabled && f.mime.startsWith('video/') && f.poster != null) {
        req.files.add(http.MultipartFile.fromBytes('posters[$i]', f.poster!, filename: 'poster.jpg', contentType: MediaType('image', 'jpeg')));
      }
    }
    final http.Response r;
    try {
      r = await req.send().then(http.Response.fromStream).timeout(_wait);
    } catch (_) {
      throw _interruptedUpload(replaySafe);
    }
    _checkSession(epoch);
    if (r.statusCode != 201 && r.statusCode != 200) throw _uploadFailure(r, replaySafe: replaySafe);
    final j = _uploadResult(r, 'post', replaySafe);
    return (j['post'] as Map).cast<String, dynamic>();
  }

  /// Multipart POST with one optional file. Returns the decoded JSON object.
  Future<Map<String, dynamic>> upload(String path, {Map<String, String> fields = const {}, String field = 'media', UploadFile? file, String? intent}) async {
    final epoch = _sessionEpoch;
    final replaySafe = uploadIntentsEnabled && intent != null;
    final account = user?['public_id'];
    final token = await _token();
    _checkSession(epoch);
    if (account == null || account != user?['public_id']) throw ApiError('Please sign in again.', 401);
    final req = (path == '/stories' ? _trackedUpload(path) : http.MultipartRequest('POST', Uri.parse('$apiBase$path')))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields);
    if (path == '/stories' && replaySafe) req.fields['upload_intent'] = intent;
    if (file != null) {
      req.files.add(http.MultipartFile.fromBytes(field, file.bytes, filename: file.name, contentType: MediaType.parse(file.mime)));
    }
    final http.Response r;
    try {
      r = await req.send().then(http.Response.fromStream).timeout(_wait);
    } catch (_) {
      if (path != '/stories') throw ApiError('Upload failed. Check your connection and try again.');
      throw _interruptedUpload(replaySafe);
    }
    _checkSession(epoch);
    if (r.statusCode != 200 && r.statusCode != 201) throw path == '/stories' ? _uploadFailure(r, replaySafe: replaySafe) : ApiError(_errorText(r), r.statusCode);
    return path == '/stories' ? _uploadResult(r, 'story', replaySafe) : jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> uploadAvatar(UploadFile f) async {
    final epoch = _sessionEpoch;
    final token = await _token();
    _checkSession(epoch);
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase/auth/me/avatar'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..files.add(http.MultipartFile.fromBytes('avatar', f.bytes, filename: f.name, contentType: MediaType.parse(f.mime)));
    final http.Response r;
    try {
      r = await req.send().then(http.Response.fromStream).timeout(_wait);
    } catch (_) {
      throw ApiError('Upload failed. Check your connection and try again.');
    }
    _checkSession(epoch);
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
  UploadFile(this.bytes, this.mime, this.name, {this.poster});
  final List<int> bytes;
  final String mime;
  final String name;
  final List<int>? poster;
}

String mimeFor(String name, {bool video = false}) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.mov')) return 'video/quicktime';
  return video ? 'video/mp4' : 'image/jpeg';
}

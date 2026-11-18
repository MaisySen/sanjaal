// Local contract fixtures, not native decoder/device evidence.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/video_poster.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(()=>messenger.setMockMethodCallHandler(VideoPoster.channel,null));
  test('extracts one bounded local poster and freezes its bytes',() async {
    final source=Uint8List.fromList([255,216,255,217]);
    messenger.setMockMethodCallHandler(VideoPoster.channel,(call) async { expect(call.method,'extract');expect(call.arguments,{'path':'/cache/clip.mp4'});return source; });
    final poster=await VideoPoster.fromPath('/cache/clip.mp4');expect(poster,source);expect(()=>poster![0]=0,throwsUnsupportedError);
  });
  test('remote paths and blank paths never reach the native channel',() async {
    messenger.setMockMethodCallHandler(VideoPoster.channel,(_) async=>throw StateError('No native call expected'));
    expect(await VideoPoster.fromPath(''),isNull);expect(await VideoPoster.fromPath('https://invalid.test/clip.mp4'),isNull);
  });
  test('native failure unsupported or oversize poster leaves original upload possible',() async {
    messenger.setMockMethodCallHandler(VideoPoster.channel,(_) async=>throw PlatformException(code:'fixture'));
    expect(await VideoPoster.fromPath('/cache/clip.mp4'),isNull);
    messenger.setMockMethodCallHandler(VideoPoster.channel,(_) async=>Uint8List(256*1024+1));
    expect(await VideoPoster.fromPath('/cache/clip.mp4'),isNull);
  });
  test('concurrent extracts do not decode a grid full of videos',() async {
    final pending=Completer<Uint8List>();var calls=0;
    messenger.setMockMethodCallHandler(VideoPoster.channel,(_) async {calls++;return pending.future;});
    final first=VideoPoster.fromPath('/cache/one.mp4');await Future<void>.delayed(Duration.zero);
    expect(await VideoPoster.fromPath('/cache/two.mp4'),isNull);expect(calls,1);
    pending.complete(Uint8List.fromList([1]));await first;
  });
  for(final supported in [false,true]) {
    test('multipart poster follows server capability $supported and media index',() async {
      SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});
      final requests=<http.BaseRequest>[];
      final client=MockClient.streaming((request,stream) async {
        final body=await stream.bytesToString();requests.add(request);
        if(request.url.path.endsWith('/oauth/token'))return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'access_token':'fixture','expires_in':3600}))),200);
        if(request.url.path.endsWith('/auth/me'))return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'features':{'video_posters':supported},'user':{'public_id':'fixture'}}))),200);
        expect(body.contains('name="posters[1]"'),supported);expect(body.contains('name="posters[0]"'),isFalse);
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'post':{'public_id':'fixture-post'}}))),201);
      });
      await http.runWithClient(() async {
        final s=Session();await s.login('fixture','fixture');expect(s.videoPostersEnabled,supported);
        await s.createPost('',files:[UploadFile([1],'image/jpeg','one.jpg'),UploadFile([2],'video/mp4','two.mp4',poster:[3])]);
      },()=>client);
      expect(requests.length,3);
    });
  }
}

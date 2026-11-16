// Synthetic multipart/private in-memory retry checks. No live upload/device evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/voice.dart';
import 'chat_retry_test.dart' as base;
import 'profile_journey_test.dart' as journey;
import 'package:sanjaal/chat_pages.dart';

class Picker extends ImagePickerPlatform {
 final Completer<XFile?>? held;
 Picker([this.held]);
 @override Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options=const ImagePickerOptions()})async => held==null?XFile.fromData(File('test/fixtures/ridge.png').readAsBytesSync(),name:'private.png',mimeType:'image/png'):held!.future;
}
String field(http.Request r,String name)=>RegExp('name="$name"\\r\\n\\r\\n([^\\r]*)').firstMatch(latin1.decode(r.bodyBytes))!.group(1)!;
Map<String,dynamic> server(String cid,{String kind='image'})=>{...base.message('delivered','',cid:cid),'kind':kind,'media_url':null};
Future<void> pick(WidgetTester t)async{await t.tap(find.byTooltip('Attach photo'));await base.flush(t);}
void main(){
 setUpAll(()async{for(final x in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(x.$1)..addFont(Future.value(ByteData.sublistView(File(x.$2).readAsBytesSync())));await l.load();}});
 setUp((){final old=ImagePickerPlatform.instance;ImagePickerPlatform.instance=Picker();addTearDown(()=>ImagePickerPlatform.instance=old);});
 for(final failure in ['rejected','lost','malformed']){
 testWidgets('$failure photo retry preserves bytes id reply and newer editor',(t)async{
  final held=Completer<http.Response>();final requests=<http.Request>[];var reads=0;
  await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[base.message('root','Question')]}):held.future;requests.add(r);if(requests.length==1){if(failure=='lost')throw const SocketException('Fixture loss');return failure=='malformed'?base.json({'message':{}}):base.json({'message':'Fixture failure'},503);}return base.json({'message':server(field(r,'client_id'))});},()async{
   await t.longPress(find.text('Question'));await base.flush(t);await t.tap(find.text('Reply'));await base.flush(t);await pick(t);expect(find.text('Photo'),findsOneWidget);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsOneWidget);
   await t.longPress(find.text('Question').first);await base.flush(t);await t.tap(find.text('Reply'));await base.flush(t);await t.enterText(find.byType(TextField),'New draft');
   await t.tap(find.text('Delivery unconfirmed. Tap to retry.'));await base.flush(t);expect(requests.length,2);expect(field(requests[1],'client_id'),field(requests[0],'client_id'));expect(field(requests[1],'reply_to'),'root');
   String normalized(http.Request r)=>latin1.decode(r.bodyBytes).replaceAll(RegExp(r'dart-http-boundary-[A-Za-z0-9_+./=-]+'),'BOUNDARY');expect(normalized(requests[1]),normalized(requests[0]));expect(find.text('New draft'),findsOneWidget);expect(find.textContaining('Replying to @fixture:'),findsOneWidget);expect(find.text('Remove retry copy'),findsNothing);held.complete(base.json({'data':[]}));
  });
 });}
 testWidgets('pending upload is visible and cannot stack media or retry taps',(t)async{
  final send=Completer<http.Response>(),held=Completer<http.Response>();var reads=0,writes=0;String? cid;
  await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;writes++;cid=field(r,'client_id');return send.future;},()async{
   await pick(t);expect(find.text('Sending'),findsOneWidget);expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Attach photo')).onPressed,isNull);expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Voice message')).onPressed,isNull);await t.tap(find.text('Photo'));await base.flush(t);expect(writes,1);send.complete(base.json({'message':server(cid!)}));await base.flush(t);expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Attach photo')).onPressed,isNotNull);held.complete(base.json({'data':[]}));
  });
 });
 testWidgets('poll before lost upload response replaces local bytes and cannot downgrade',(t)async{
  final poll=Completer<http.Response>(),send=Completer<http.Response>(),held=Completer<http.Response>();var reads=0,writes=0;String? cid;
  await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):reads==2?poll.future:held.future;writes++;cid=field(r,'client_id');return send.future;},()async{
   await pick(t);await t.enterText(find.byType(TextField),'Keep me');poll.complete(base.json({'data':[server(cid!)]}));await base.flush(t);send.completeError(const SocketException('Lost after confirmation'));await base.flush(t);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsNothing);expect(find.text('Remove retry copy'),findsNothing);expect(find.text('Keep me'),findsOneWidget);expect(writes,1);expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Attach photo')).onPressed,isNotNull);held.complete(base.json({'data':[]}));
  });
 });
 testWidgets('voice retry keeps original audio bytes and key without recording again',(t)async{
  final never=Completer<bool>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'),(c)async{if(c.method=='hasPermission')return never.future;return null;});
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'),null));
  final held=Completer<http.Response>();final sent=<http.Request>[];var reads=0;
  await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;sent.add(r);return sent.length==1?base.json({'message':'Fixture failure'},503):base.json({'message':server(field(r,'client_id'),kind:'voice')});},()async{
   await t.tap(find.byTooltip('Voice message'));await t.pump();final voice=t.widget<VoiceRecorderBar>(find.byType(VoiceRecorderBar));voice.onDone([1,2,3,4]);await base.flush(t);expect(find.text('Voice message'),findsOneWidget);await t.tap(find.text('Delivery unconfirmed. Tap to retry.'));await base.flush(t);expect(sent.length,2);expect(field(sent[1],'client_id'),field(sent[0],'client_id'));expect(latin1.decode(sent[1].bodyBytes),contains('filename="voice.m4a"'));expect(latin1.decode(sent[1].bodyBytes),contains(String.fromCharCodes([1,2,3,4])));held.complete(base.json({'data':[]}));
  });
 });
 testWidgets('terminal original cannot retry and explicit removal keeps newer draft',(t)async{
  final held=Completer<http.Response>();var reads=0,writes=0;await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;writes++;return base.json({'message':'Gone'},410);},()async{
   await pick(t);expect(find.text('Original message unavailable.'),findsOneWidget);await t.enterText(find.byType(TextField),'Next draft');await t.tap(find.text('Photo'));await base.flush(t);expect(writes,1);await t.tap(find.text('Remove retry copy'));await base.flush(t);expect(find.textContaining('does not delete a message'),findsOneWidget);await t.tap(find.text('Remove retry copy').last);await base.flush(t);expect(find.text('Photo'),findsNothing);expect(find.text('Next draft'),findsOneWidget);held.complete(base.json({'data':[]}));
  });
 });
 testWidgets('late upload after disposal cannot restore private retry copy',(t)async{
  final held=Completer<http.Response>(),send=Completer<http.Response>();var reads=0;String? cid;await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;cid=field(r,'client_id');return send.future;},()async{
   await pick(t);await t.pumpWidget(const SizedBox());send.complete(base.json({'message':server(cid!)}));held.complete(base.json({'data':[]}));await base.flush(t);expect(t.takeException(),isNull);
  });
 });
 testWidgets('back waits for pending media then explicitly confirms discarding retry bytes',(t)async{
  final send=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;
  await journey.fixture(t,(s)=>ChatPage(session:s,convo:{'public_id':'chat','type':'direct','title':'Asha'}),()async{
   await pick(t);await t.pageBack();await base.flush(t);expect(find.byType(ChatPage),findsOneWidget);expect(find.text('Leave chat?'),findsNothing);
   send.complete(base.json({'message':'Fixture failure'},503));await base.flush(t);await t.pageBack();await base.flush(t);expect(find.text('Leave chat?'),findsOneWidget);expect(find.textContaining('not messages that may have'),findsOneWidget);await t.tap(find.text('Stay here'));await base.flush(t);expect(find.text('Photo'),findsOneWidget);await t.pageBack();await base.flush(t);await t.tap(find.text('Leave').last);await t.pumpAndSettle();expect(find.byType(ChatPage),findsNothing);held.complete(base.json({'data':[]}));
  },respond:(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;return send.future;});
 });
 testWidgets('picker completion after disposal does not read or upload a selection',(t)async{
  final picker=Completer<XFile?>();ImagePickerPlatform.instance=Picker(picker);final held=Completer<http.Response>();var reads=0,writes=0;
  await base.fixture(t,(r)async{if(r.method=='GET')return ++reads==1?base.json({'data':[]}):held.future;writes++;return base.json({});},()async{
   await pick(t);await t.pumpWidget(const SizedBox());picker.complete(XFile.fromData(Uint8List.fromList([1,2,3]),name:'private.png'));held.complete(base.json({'data':[]}));await base.flush(t);expect(writes,0);expect(t.takeException(),isNull);
  });
 });
 for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
 testWidgets('leaving retained media large-text confirmation $lang ${b.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);var reads=0;final held=Completer<http.Response>();
  await journey.fixture(t,(s)=>ChatPage(session:s,convo:{'public_id':'chat','type':'direct','title':'Asha'}),()async{
   await t.tap(find.byTooltip(lang=='ne'?'तस्बिर संलग्न गर्नुहोस्':'Attach photo'));await base.flush(t);await t.pageBack();await base.flush(t);expect(t.takeException(),isNull);expect(find.text(lang=='ne'?'बाहिरिनुहोस्':'Leave'),findsOneWidget);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('review')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_media_exit_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});await t.pumpWidget(const SizedBox());held.complete(base.json({'data':[]}));
  },language:lang,brightness:b,scale:1.8,respond:(r)async=>r.method=='GET'?(++reads==1?base.json({'data':[]}):held.future):base.json({'message':'Fixture unavailable'},503));
 });
 testWidgets('media retained retry small large-text $lang ${b.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);var reads=0;final held=Completer<http.Response>();
  await base.fixture(t,(r)async=>r.method=='GET'?(++reads==1?base.json({'data':[]}):held.future):base.json({'message':'Fixture unavailable'},503),()async{
   await t.tap(find.byTooltip(lang=='ne'?'तस्बिर संलग्न गर्नुहोस्':'Attach photo'));await base.flush(t);await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('chat-retry-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_media_notice_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});ScaffoldMessenger.of(t.element(find.byType(ChatPage))).removeCurrentSnackBar();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pump(const Duration(seconds:5));await t.pump();expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('chat-retry-shot')));final im=await boundary.toImage(pixelRatio:2);final bytes=await im.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_media_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});held.complete(base.json({'data':[]}));
  },language:lang,brightness:b,scale:1.8);
 });}}
}

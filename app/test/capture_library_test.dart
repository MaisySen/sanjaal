// Fake native devices/library only. These tests do not establish camera,
// microphone, codec, device-permission or local-gallery behavior on a phone.
import 'dart:async';
import 'package:camera/camera.dart' as camera;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart' as picker;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/capture_page.dart';
import 'package:sanjaal/media_library_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart';
import 'package:sanjaal/api.dart' show mimeFor;

late Uint8List imageBytes;
class FakeCamera implements CaptureDevice {
  @override bool get canSwitch => true;
  final calls=<String>[];
  Completer<void>? initPending,startPending;
  Completer<XFile>? photoPending,stopPending;
  bool failed=false;Object? failure;
  Color previewColor=const Color(0xFF2C656C);
  @override Future<void> initialize()async{calls.add('init');if(initPending!=null)await initPending!.future;if(failure!=null)throw failure!;if(failed)throw StateError('fixture camera failed');}
  @override Widget preview()=>ColoredBox(key:const ValueKey('live-fixture-preview'),color:previewColor);
  @override Future<XFile> photo()async{calls.add('photo');return photoPending?.future??XFile.fromData(imageBytes,name:'fixture.png');}
  @override Future<void> start()async{calls.add('start');if(startPending!=null)await startPending!.future;}
  @override Future<XFile> stop()async{calls.add('stop');return stopPending?.future??XFile.fromData(Uint8List.fromList([1,2,3]),name:'fixture.mp4',path:'/fixture.mp4');}
  @override Future<void> flash(bool value)async{calls.add('flash:$value');}
  @override Future<double> zoom(double value)async{calls.add('zoom:$value');return value;}
  @override Future<void> dispose()async{calls.add('dispose');}
}
class FakeLibrary implements MediaLibrary {
  LibraryAccess access=LibraryAccess.full;
  int requests=0,thumbs=0,fileReads=0,manages=0,settingsCalls=0;
  bool failAlbums=false,failPage=false,failFile=false,failSettings=false;
  Completer<List<LibraryAsset>>? delayedPage;
  Completer<XFile?>? delayedFile;
  final reads=<(String,int)>[];
  final filters=<(bool,bool)>[];
  final rows=<LibraryAsset>[for(var i=0;i<55;i++)LibraryAsset('a$i',video:i%4==0,seconds:12)];
  @override Future<LibraryAccess> request()async{requests++;return access;}
  @override Future<LibraryAccess> status()async{return access;}
  @override Future<List<LibraryAlbum>> albums({required bool videos,required bool images})async{filters.add((videos,images));if(failAlbums)throw StateError('fixture albums failed');return const [LibraryAlbum('recent','Recents',recent:true),LibraryAlbum('album','Fixture album')];}
  @override Future<List<LibraryAsset>> page(String album,int index)async{reads.add((album,index));if(failPage)throw StateError('fixture page failed');if(delayedPage!=null)return delayedPage!.future;return rows.skip(index*24).take(24).toList();}
  @override Future<Uint8List?> thumbnail(LibraryAsset asset)async{thumbs++;return imageBytes;}
  @override Future<XFile?> file(LibraryAsset asset)async{fileReads++;if(failFile)return null;return delayedFile?.future??XFile.fromData(imageBytes,name:'fixture.png');}
  @override Future<void> manage()async{manages++;}
  @override Future<void> settings()async{settingsCalls++;if(failSettings)throw StateError('settings unavailable');}
}
class PendingPicker extends picker.ImagePickerPlatform {
  int calls=0;
  final pending=Completer<picker.XFile?>();
  @override Future<picker.XFile?> getVideo({required picker.ImageSource source,picker.CameraDevice preferredCameraDevice=picker.CameraDevice.rear,Duration? maxDuration})async{calls++;return pending.future;}
}
Future<void> flush(WidgetTester t)async{for(var i=0;i<3;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await t.pump(const Duration(milliseconds:150));}}
Future<void> start(WidgetTester t,Widget page,{void Function(dynamic)? result,double scale=1,String language='en'})async{
 prefs.lang=language;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
 await t.pumpWidget(RepaintBoundary(key:const ValueKey('capture-library-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale),padding:const EdgeInsets.only(top:24,bottom:24)),child:w!),home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()async{final value=await Navigator.of(c).push(MaterialPageRoute(builder:(_)=>page));result?.call(value);},child:const Text('Open fixture')))))));
 await t.tap(find.text('Open fixture'));await flush(t);
}
Future<void> tapShutter(WidgetTester t,String label)async{await t.tap(find.bySemanticsLabel(label));await flush(t);}
Future<void> shot(WidgetTester t,String name)async{await flush(t);await flush(t);await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture-library-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/creator_$name.png').writeAsBytesSync(data!.buffer.asUint8List());});}
void background(WidgetTester t){for(final state in [AppLifecycleState.inactive,AppLifecycleState.hidden,AppLifecycleState.paused]){t.binding.handleAppLifecycleStateChanged(state);}}
void foreground(WidgetTester t){for(final state in [AppLifecycleState.hidden,AppLifecycleState.inactive,AppLifecycleState.resumed]){t.binding.handleAppLifecycleStateChanged(state);}}
void main(){
 for(final language in ['en','ne']){for(final scale in [1.0,1.8]){
 testWidgets('selected media order stays readable and permission failure is recoverable $language $scale',(t)async{
  final library=FakeLibrary()..failSettings=true;await start(t,MediaLibraryPage(kind:CreatorKind.post,library:library),language:language,scale:scale);
  await t.tap(find.text(t_('Select')));await flush(t);await t.tap(find.byKey(const ValueKey('a1')));await flush(t);expect(find.text('1'),findsOneWidget);expect(t.widget<Text>(find.text('1')).style?.color,Colors.black);await shot(t,'gallery_selected_${language}_$scale');
  await t.tap(find.byTooltip(t_('Photo permissions')));await flush(t);expect(find.text(t_('Photo permissions could not be opened. Try again.')),findsOneWidget);expect(t.takeException(),isNull);await shot(t,'gallery_permission_error_${language}_$scale');expect(library.fileReads,0);
 });}}

 for(final code in ['CameraAccessDeniedWithoutPrompt','AudioAccessDeniedWithoutPrompt']) {
 testWidgets('denied native permission opens settings and recovers only on foreground $code',(t)async{
  var opens=0;final broken=FakeCamera()..failure=camera.CameraException(code,'fixture');final working=FakeCamera();var boots=0;CreatorMedia? result;
  await start(t,CapturePage(deviceFactory:(_,_)=>boots++==0?broken:working,openSettings:()async{opens++;}),result:(v)=>result=v as CreatorMedia?);
  expect(find.text('Open device settings'),findsOneWidget);expect(result,isNull);
  await t.tap(find.text('Open device settings'));await flush(t);expect(opens,1);expect(boots,1);
  background(t);await flush(t);foreground(t);await flush(t);
  expect(find.byKey(const ValueKey('live-fixture-preview')),findsOneWidget);expect(boots,2);expect(result,isNull);expect(working.calls,isNot(contains('photo')));expect(working.calls,isNot(contains('start')));
 });
 }
 for(final code in ['CameraAccessRestricted','AudioAccessRestricted']) {
 for(final language in ['en','ne']) {
 testWidgets('restricted device does not promise settings can grant access $code $language',(t)async{
  final device=FakeCamera()..failure=camera.CameraException(code,'fixture');
  await start(t,CapturePage(deviceFactory:(_,_)=>device),scale:1.8,language:language);
  expect(find.text(t_('Open device settings')),findsNothing);expect(find.text(t_('Try again')),findsNothing);
  expect(find.text(t_('Camera or microphone access is restricted on this device. You may need help from the person who manages it. You can still choose media from your library.')),findsOneWidget);
  expect(t.takeException(),isNull);await shot(t,'restricted_${code}_$language');
  await t.tap(find.widgetWithText(TextButton,t_('Close camera')));await flush(t);await t.pumpAndSettle();expect(find.byType(CapturePage),findsNothing);
 });
 }}
 for(final language in ['en','ne']) {
 testWidgets('denied permission settings action stays readable $language',(t)async{
  final device=FakeCamera()..failure=camera.CameraException('CameraAccessDeniedWithoutPrompt','fixture');
  await start(t,CapturePage(deviceFactory:(_,_)=>device,openSettings:()async{}),scale:1.8,language:language);
  expect(find.bySemanticsLabel(t_('Take a photo')),findsNothing);
  final action=find.widgetWithText(FilledButton,t_('Open device settings'));
  await t.ensureVisible(action);await t.pumpAndSettle();expect(action.hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
  await shot(t,'denied_settings_$language');
 });
 }
 testWidgets('failed settings launch keeps camera recovery available',(t)async{
  final device=FakeCamera()..failure=camera.CameraException('CameraAccessDeniedWithoutPrompt','fixture');
  await start(t,CapturePage(deviceFactory:(_,_)=>device,openSettings:()async{throw StateError('fixture');}));
  await t.tap(find.text('Open device settings'));await flush(t);
  expect(find.text('Device settings could not be opened. Open Settings manually, then return to Sanjaal.'),findsOneWidget);expect(find.widgetWithText(FilledButton,'Open device settings'),findsOneWidget);expect(t.takeException(),isNull);
 });
 testWidgets('camera launch double taps open one review route and cancel unlocks gallery',(t)async{
  final library=FakeLibrary();var builds=0;
  await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library,captureBuilder:(_,_)=>Builder(builder:(context){builds++;return Scaffold(body:TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel fixture camera')));})));final button=t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Camera')).onPressed!;button();button();await flush(t);expect(find.text('Cancel fixture camera'),findsOneWidget);expect(builds,1);expect(library.fileReads,0);
  await t.tap(find.text('Cancel fixture camera'));await flush(t);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Camera')).onPressed,isNotNull);expect(find.byType(MediaLibraryPage),findsOneWidget);expect(t.takeException(),isNull);
 });
 testWidgets('native picker double taps make one request and cancellation preserves gallery',(t)async{
  final old=picker.ImagePickerPlatform.instance;final fake=PendingPicker();picker.ImagePickerPlatform.instance=fake;addTearDown(()=>picker.ImagePickerPlatform.instance=old);
  final library=FakeLibrary();await start(t,MediaLibraryPage(kind:CreatorKind.reel,library:library));final button=t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Device picker')).onPressed!;button();button();await flush(t);expect(fake.calls,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Camera')).onPressed,isNull);expect(library.fileReads,0);
  fake.pending.complete(null);await flush(t);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Device picker')).onPressed,isNotNull);expect(find.byType(MediaLibraryPage),findsOneWidget);expect(t.takeException(),isNull);
 });
 testWidgets('failed device permission settings opens a recoverable notice and gallery stays usable',(t)async{
  final library=FakeLibrary()..failSettings=true;await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library));await t.tap(find.byTooltip('Photo permissions'));await flush(t);expect(library.settingsCalls,1);expect(find.text('Photo permissions could not be opened. Try again.'),findsOneWidget);expect(find.byType(MediaLibraryPage),findsOneWidget);expect(t.takeException(),isNull);
  library.failSettings=false;await t.tap(find.byTooltip('Photo permissions'));await flush(t);expect(library.settingsCalls,2);expect(library.fileReads,0);expect(t.takeException(),isNull);
 });

 setUpAll(()async{Directory('test/renders').createSync(recursive:true);
 for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final file=File(f.$2);if(file.existsSync()){final loader=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));await loader.load();}}
 final recorder=ui.PictureRecorder();final canvas=Canvas(recorder);canvas.drawRect(const Rect.fromLTWH(0,0,300,500),Paint()..shader=ui.Gradient.linear(Offset.zero,const Offset(300,500),const [Color(0xFF1F8784),Color(0xFFDAB487)]));final image=await recorder.endRecording().toImage(300,500);imageBytes=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();
 });
 testWidgets('actual photo normalizer keeps PNG bytes and a nonempty IO multipart filename',(t)async{
 final selected=await t.runAsync(()=>normalizeLibraryPhoto(imageBytes));
 expect(selected,isNotNull);expect(selected!.name,'selected-photo.png');expect(selected.mimeType,'image/png');expect(mimeFor(selected.name),'image/png');
 final bytes=await t.runAsync(()=>selected.readAsBytes());expect(bytes!.take(8).toList(),[137,80,78,71,13,10,26,10]);
 await t.runAsync(()async{final codec=await ui.instantiateImageCodec(bytes);final frame=await codec.getNextFrame();expect((frame.image.width,frame.image.height),(300,500));frame.image.dispose();codec.dispose();});
 });
 testWidgets('photo waits for initialization and explicit shutter then returns for review without publishing',(t)async{
 final device=FakeCamera()..initPending=Completer<void>();CreatorMedia? result;
 await start(t,CapturePage(deviceFactory:(_,_)=>device),result:(v)=>result=v as CreatorMedia?);
 expect(find.byKey(const ValueKey('live-fixture-preview')),findsNothing);await tapShutter(t,'Take a photo');expect(device.calls,['init']);device.initPending!.complete();await flush(t);
 expect(find.byKey(const ValueKey('live-fixture-preview')),findsOneWidget);await tapShutter(t,'Take a photo');expect(result?.isVideo,isFalse);expect(device.calls,contains('dispose'));expect(t.takeException(),isNull);
 });
 testWidgets('video needs a start and stop and mode, zoom and flip freeze during recording',(t)async{
 final device=FakeCamera();CreatorMedia? result;await start(t,CapturePage(startVideo:true,deviceFactory:(_,_)=>device),result:(v)=>result=v as CreatorMedia?);
 await tapShutter(t,'Start recording');expect(result,isNull);expect(device.calls,contains('start'));expect(t.widget<IconButton>(find.ancestor(of:find.byTooltip('Switch camera'),matching:find.byType(IconButton)).first).onPressed,isNull);
 expect(t.widget<TextButton>(find.widgetWithText(TextButton,'Photo')).onPressed,isNull);await tapShutter(t,'Stop recording');expect(result?.isVideo,isTrue);expect(device.calls.where((v)=>v=='stop').length,1);
 });
 testWidgets('recording stops at the configured timer bound',(t)async{
 final device=FakeCamera();CreatorMedia? result;await start(t,CapturePage(startVideo:true,maxSeconds:2,deviceFactory:(_,_)=>device),result:(v)=>result=v as CreatorMedia?);await tapShutter(t,'Start recording');await t.pump(const Duration(seconds:3));await flush(t);expect(result?.isVideo,isTrue);expect(device.calls.where((v)=>v=='stop').length,1);
 });
 testWidgets('background recording stops, keeps its result for explicit review, and cannot auto-post',(t)async{
 final device=FakeCamera();CreatorMedia? result;await start(t,CapturePage(startVideo:true,deviceFactory:(_,_)=>device),result:(v)=>result=v as CreatorMedia?);await tapShutter(t,'Start recording');background(t);await flush(t);expect(device.calls,contains('stop'));expect(device.calls,contains('dispose'));expect(result,isNull);foreground(t);await flush(t);expect(find.text('Review capture'),findsOneWidget);await t.tap(find.text('Review capture'));await flush(t);expect(result?.isVideo,isTrue);
 });
 testWidgets('start completing after background is stopped and recovered, never left recording',(t)async{
 final device=FakeCamera()..startPending=Completer<void>();await start(t,CapturePage(startVideo:true,deviceFactory:(_,_)=>device));await tapShutter(t,'Start recording');background(t);device.startPending!.complete();await flush(t);expect(device.calls.where((v)=>v=='stop').length,1);expect(device.calls,contains('dispose'));foreground(t);await flush(t);expect(find.text('Review capture'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('late photo after suspension is retained for explicit review',(t)async{
 final device=FakeCamera()..photoPending=Completer<XFile>();CreatorMedia? result;await start(t,CapturePage(deviceFactory:(_,_)=>device),result:(v)=>result=v as CreatorMedia?);await tapShutter(t,'Take a photo');background(t);device.photoPending!.complete(XFile.fromData(imageBytes,name:'fixture.png'));await flush(t);foreground(t);await flush(t);expect(result,isNull);expect(find.text('Review capture'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('discard recording needs confirmation, cancellation retains recording',(t)async{
 final device=FakeCamera();await start(t,CapturePage(startVideo:true,deviceFactory:(_,_)=>device));await tapShutter(t,'Start recording');await t.tap(find.byTooltip('Close camera'));await flush(t);await t.tap(find.text('Keep editing'));await flush(t);expect(find.byType(CapturePage),findsOneWidget);expect(device.calls, isNot(contains('stop')));await t.tap(find.byTooltip('Close camera'));await flush(t);await t.tap(find.text('Discard'));await flush(t);await flush(t);expect(find.byType(CapturePage),findsNothing);expect(device.calls,contains('stop'));
 });
 testWidgets('camera controls call the native boundary and switching mode releases old device',(t)async{
 final devices=<FakeCamera>[];await start(t,CapturePage(deviceFactory:(_,_) { final d=FakeCamera();devices.add(d);return d; }));await t.tap(find.byTooltip('Flash off'));await flush(t);expect(devices.first.calls,contains('flash:true'));await t.tap(find.text('1x'));await flush(t);expect(devices.first.calls,contains('zoom:2.0'));await t.tap(find.text('Video'));await flush(t);expect(devices.first.calls,contains('dispose'));expect(devices.length,2);await t.tap(find.byTooltip('Switch camera'));await flush(t);expect(devices[1].calls,contains('dispose'));expect(devices.length,3);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('failed camera offers retry and late initialization after exit cannot show preview',(t)async{
 final first=FakeCamera()..failed=true;final second=FakeCamera()..initPending=Completer<void>();var calls=0;await start(t,CapturePage(deviceFactory:(_,_)=>calls++==0?first:second));expect(find.text('Try again'),findsOneWidget);await t.tap(find.text('Try again'));await flush(t);await t.tap(find.byTooltip('Close camera'));await flush(t);second.initPending!.complete();await flush(t);expect(find.byType(CapturePage),findsNothing);expect(second.calls,contains('dispose'));expect(t.takeException(),isNull);
 });
 testWidgets('gallery lazily reads pages, deduplicates and only materializes explicitly chosen media',(t)async{
 final library=FakeLibrary();List<CreatorMedia>? result;await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library),result:(v)=>result=(v as List?)?.cast<CreatorMedia>());expect(library.reads,[('recent',0)]);expect(library.fileReads,0);expect(library.thumbs,lessThan(24));await t.tap(find.byKey(const ValueKey('a1')));await flush(t);expect(library.fileReads,1);expect(result?.length,1);expect(result?.single.isVideo,isFalse);
 });
 testWidgets('denied permission never reads albums/thumbnails and does not remove native-picker escape',(t)async{
 final library=FakeLibrary()..access=LibraryAccess.denied;await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library));expect(library.filters,isEmpty);expect(library.reads,isEmpty);expect(library.fileReads,0);expect(find.text('Device picker'),findsWidgets);expect(find.text('Choose photos with the device picker, or allow library access to see your Recents here.'),findsOneWidget);await shot(t,'denied');
 });
 testWidgets('limited grant provides reselection and never fabricates unseen thumbnails',(t)async{
 final library=FakeLibrary()..access=LibraryAccess.limited;library.rows.clear();await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library));expect(find.text('Choose more'),findsOneWidget);expect(library.thumbs,0);await t.tap(find.text('Choose more'));await flush(t);expect(library.manages,1);expect(library.requests,2);
 });
 testWidgets('permission revoked while away clears the gallery on resume without asking again',(t)async{
 final library=FakeLibrary();await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library));expect(find.byKey(const ValueKey('a1')),findsOneWidget);expect(library.requests,1);background(t);library.access=LibraryAccess.denied;foreground(t);await flush(t);expect(library.requests,1);expect(find.byKey(const ValueKey('a1')),findsNothing);expect(find.text('Device picker'),findsWidgets);
 });
 testWidgets('album-list and page failures are independently retryable',(t)async{
 final library=FakeLibrary()..failAlbums=true;await start(t,MediaLibraryPage(kind:CreatorKind.post,library:library));expect(find.text('Try again'),findsOneWidget);library.failAlbums=false;library.failPage=true;await t.tap(find.text('Try again'));await flush(t);expect(library.requests,2);library.failPage=false;await t.tap(find.text('Try again'));await flush(t);expect(find.byKey(const ValueKey('a1')),findsOneWidget);expect(library.requests,2);
 });
 testWidgets('unavailable selected file shows error and never returns invented media',(t)async{
 final library=FakeLibrary()..failFile=true;dynamic result;await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library),result:(v)=>result=v);await t.tap(find.byKey(const ValueKey('a1')));await flush(t);expect(result,isNull);expect(find.text('That item is unavailable. Check your connection or choose another.'),findsOneWidget);
 });
 testWidgets('post multi-select preserves order and respects four-file cap before explicit Next',(t)async{
 final library=FakeLibrary();List<CreatorMedia>? result;await start(t,MediaLibraryPage(kind:CreatorKind.post,library:library),result:(v)=>result=(v as List?)?.cast<CreatorMedia>());await t.tap(find.text('Select'));await flush(t);for(final label in ['Photo a1','Photo a2','Photo a3','Photo a5','Photo a6']){await t.ensureVisible(find.byKey(ValueKey(label.split(' ').last)));await t.tap(find.byKey(ValueKey(label.split(' ').last)));await flush(t);}expect(library.fileReads,0);await t.drag(find.byType(CustomScrollView),const Offset(0,1400));await flush(t);expect(find.text('Next (4/4)'),findsOneWidget);await t.ensureVisible(find.text('Next (4/4)'));await t.tap(find.text('Next (4/4)'));await flush(t);expect(library.fileReads,4);expect(result?.length,4);
 });
 testWidgets('long story videos cannot resolve and cancelling a pending file pick ignores its late result',(t)async{
 final library=FakeLibrary();library.rows[0]=const LibraryAsset('a0',video:true,seconds:45);await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library));await t.tap(find.byKey(const ValueKey('a0')));await flush(t);expect(library.fileReads,0);library.delayedFile=Completer<XFile?>();await t.tap(find.byKey(const ValueKey('a1')));await flush(t);await t.tap(find.byTooltip('Close'));await flush(t);await flush(t);expect(find.byType(MediaLibraryPage),findsNothing);library.delayedFile!.complete(XFile.fromData(imageBytes,name:'fixture.png'));await flush(t);await flush(t);expect(find.byType(MediaLibraryPage),findsNothing);
 });
 for(final color in [Colors.white,Colors.black])testWidgets('camera controls retain contrast on ${color==Colors.white?'bright':'dark'} scene',(t)async{
 final device=FakeCamera()..previewColor=color;await start(t,CapturePage(deviceFactory:(_,_)=>device));
 expect(find.byKey(const ValueKey('camera-header-contrast')),findsOneWidget);expect(find.byTooltip('Close camera').hitTestable(),findsOneWidget);expect(find.byTooltip('Flash off').hitTestable(),findsOneWidget);expect(find.text('1x').hitTestable(),findsOneWidget);expect(find.bySemanticsLabel('Take a photo').hitTestable(),findsOneWidget);
 await shot(t,'camera_contrast_${color==Colors.white?'bright':'dark'}');await t.tap(find.byTooltip('Flash off'));await flush(t);expect(device.calls,contains('flash:true'));await t.pumpWidget(const SizedBox());await flush(t);
 });
 for(final lang in ['en','ne'])for(final scale in [1.0,1.8])testWidgets('screenshot-led gallery and real-preview fixture geometry $lang $scale',(t)async{
 final library=FakeLibrary()..access=scale==1?LibraryAccess.full:LibraryAccess.limited;await start(t,MediaLibraryPage(kind:CreatorKind.story,library:library),language:lang,scale:scale);expect(t.takeException(),isNull);await shot(t,'gallery_${lang}_$scale');await t.pumpWidget(const SizedBox());await flush(t);final device=FakeCamera();await start(t,CapturePage(startVideo:true,deviceFactory:(_,_)=>device),language:lang,scale:scale);await shot(t,'camera_${lang}_$scale');expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());await flush(t);
 });
}

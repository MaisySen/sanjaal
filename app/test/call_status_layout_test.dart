// Actual offline CallView layout. No call, device, account or native capture.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;

void main(){
 setUpAll(()async{
  for(final font in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
   final file=File(font.$2);if(file.existsSync())await (FontLoader(font.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
  }
 });
 for(final lang in ['en','ne']){for(final landscape in [false,true]){for(final mode in [Brightness.light,Brightness.dark]){
  testWidgets('long call error retains reachable End $lang landscape=$landscape ${mode.name}',(t)async{
   t.view.physicalSize=landscape?const Size(640,320):const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   final key=GlobalKey();var ends=0,mutes=0,cameras=0;
   final sentence=lang=='en'?'Could not start the call. Check your connection and microphone permission. ':'कल सुरु गर्न सकिएन। आफ्नो जडान र माइक्रोफोन अनुमति जाँच्नुहोस्। ';
   final status='${List.filled(8,sentence).join()}${lang=='en'?'End of error.':'त्रुटि विवरण समाप्त।'}';
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.8)),child:w!),home:CallView(title:'Synthetic member',status:status,failed:true,video:true,muted:true,camOn:false,tiles:const [],onMute:()=>mutes++,onCamera:()=>cameras++,onEnd:()=>ends++))));
   await t.pumpAndSettle();expect(t.takeException(),isNull);
   final end=find.byTooltip('End call');final screen=t.view.physicalSize/t.view.devicePixelRatio;
   expect(t.getTopLeft(end).dy,greaterThanOrEqualTo(0));expect(t.getBottomRight(end).dy,lessThanOrEqualTo(screen.height));
   expect(t.getTopLeft(end).dx,greaterThanOrEqualTo(0));expect(t.getBottomRight(end).dx,lessThanOrEqualTo(screen.width));
   for(final tooltip in ['Unmute microphone','Turn camera on']){
    final button=t.widget<IconButton>(find.byTooltip(tooltip));
    expect(button.onPressed,isNull);
    expect(button.style!.foregroundColor!.resolve({WidgetState.disabled}),Colors.white54,reason:'disabled capture controls remain visible on the dark call bar');
   }
   await t.tap(find.byTooltip('Unmute microphone'));await t.tap(find.byTooltip('Turn camera on'));expect(mutes,0);expect(cameras,0);
   await t.tap(end);expect(ends,1);
   final statusView=find.byKey(const ValueKey('call-status-scroll'));
   final scroll=t.state<ScrollableState>(find.descendant(of:statusView,matching:find.byType(Scrollable)));
   expect(scroll.position.maxScrollExtent,greaterThan(0));
   scroll.position.jumpTo(scroll.position.maxScrollExtent);await t.pumpAndSettle();
   expect(scroll.position.extentAfter,lessThan(1));
   expect(t.getBottomRight(find.text(status)).dy,lessThanOrEqualTo(t.getBottomRight(statusView).dy));
   expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/call_status_${lang}_${landscape?'landscape':'portrait'}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();});
  });
 }}}
}

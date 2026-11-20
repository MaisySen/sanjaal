// Actual app-language warning views. No native media, call, room or network.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart';

const callWarning='Media controls failed. Leave this call. Microphone or camera state could not be confirmed.';
const roomWarning='Microphone state could not be confirmed. Leave this room.';
const callNepali='मिडिया नियन्त्रणमा समस्या आयो। यो कलबाट बाहिर निस्कनुहोस्। माइक्रोफोन वा क्यामेराको अवस्था पुष्टि गर्न सकिएन।';
const roomNepali='माइक्रोफोनको अवस्था पुष्टि गर्न सकिएन। यो कोठाबाट बाहिर निस्कनुहोस्।';

void main(){
 setUpAll(()async{
  for(final font in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
   final file=File(font.$2);if(file.existsSync())await (FontLoader(font.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
  }
 });
 tearDown(()=>prefs.lang='en');
 test('known safety translations preserve unknown service text',(){
  prefs.lang='ne';expect(t_(callWarning),callNepali);expect(t_(roomWarning),roomNepali);
  for(final label in ['Unmute microphone','Mute microphone','Turn camera off','Turn camera on','Your camera preview','Connecting...','Reconnecting...','Connected','Disconnected','Waiting for others to join']){
   expect(t_(label),isNot(label));expect(RegExp(r'[\u0900-\u097f]').hasMatch(t_(label)),isTrue);
  }
  expect(t_('Synthetic service detail 709'), 'Synthetic service detail 709');
 });
 for(final kind in ['call','room']){for(final language in ['en','ne']){for(final landscape in [false,true]){for(final mode in [Brightness.light,Brightness.dark]){
  testWidgets('safety warning $kind $language landscape=$landscape ${mode.name}',(t)async{
   prefs.lang=language;
   t.view.physicalSize=landscape?const Size(640,320):const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   final key=GlobalKey();final chat=TextEditingController();addTearDown(chat.dispose);var ended=0,toggles=0;
   final nav=GlobalKey<NavigatorState>();
   final source=kind=='call'?callWarning:roomWarning;
   final expected=language=='en'?source:(kind=='call'?callNepali:roomNepali);
   await t.pumpWidget(MaterialApp(navigatorKey:nav,debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.8)),child:w!),home:const Scaffold(body:Text('Conversation fixture'))));
   nav.currentState!.push(MaterialPageRoute<void>(builder:(_)=>RepaintBoundary(key:key,child:kind=='call'
    ?CallView(title:'Synthetic member',status:source,failed:true,video:true,muted:true,camOn:false,tiles:const [],onMute:()=>toggles++,onCamera:()=>toggles++,onEnd:(){ended++;nav.currentState!.pop();})
    :RoomView(title:'Synthetic room',status:source,failed:true,isHost:false,speaker:true,muted:false,handUp:false,inRoom:2,hands:const {},stage:const [],messages:const [],chat:chat,onEnd:(){},onToggleMic:()=>toggles++,onRaise:(){},onGift:(){},onAllow:(_,__) {},onDismissHand:(_){},onSend:(){}))));
   await t.pumpAndSettle();expect(t.takeException(),isNull);expect(find.text(expected),findsOneWidget);
   if(language=='ne')expect(find.text(source),findsNothing);
   final exit=kind=='call'?find.byTooltip(t_('End call')):find.widgetWithText(FilledButton,t_('Back'));
   final screen=t.view.physicalSize/t.view.devicePixelRatio;
   expect(t.getTopLeft(exit).dy,greaterThanOrEqualTo(0));expect(t.getBottomRight(exit).dy,lessThanOrEqualTo(screen.height));
   if(kind=='call'){
    for(final label in ['Unmute microphone','Turn camera on']){
     final button=t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip==t_(label)));
     expect(button.onPressed,isNull);expect(button.style!.foregroundColor!.resolve({WidgetState.disabled}),Colors.white54);
    }
   }else{expect(find.byTooltip(t_('Mute')),findsNothing);expect(find.byTooltip(t_('Unmute')),findsNothing);}
   final scrollView=find.byKey(ValueKey(kind=='call'?'call-status-scroll':'room-failure-scroll'));
   final scroll=t.state<ScrollableState>(find.descendant(of:scrollView,matching:find.byType(Scrollable)));
   scroll.position.jumpTo(scroll.position.maxScrollExtent);await t.pumpAndSettle();
   expect(t.getBottomRight(find.text(expected)).dy,lessThanOrEqualTo(t.getBottomRight(scrollView).dy));expect(t.takeException(),isNull);expect(toggles,0);
   await t.runAsync(()async{final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/media_safety_${kind}_${language}_${landscape?'landscape':'portrait'}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();});
   await t.tap(exit);await t.pumpAndSettle();expect(find.text('Conversation fixture'),findsOneWidget);if(kind=='call')expect(ended,1);expect(toggles,0);
  });
 }}}}
}

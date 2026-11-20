// Offline RoomView failure/exit. No native microphone, room or network.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;

void main(){
 setUpAll(()async{
  for(final font in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
   final file=File(font.$2);if(file.existsSync())await (FontLoader(font.$1)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
  }
 });
 for(final landscape in [false,true]){for(final mode in [Brightness.light,Brightness.dark]){
  testWidgets('uncertain room microphone keeps exit reachable landscape=$landscape ${mode.name}',(t)async{
   t.view.physicalSize=landscape?const Size(640,320):const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   final key=GlobalKey();final chat=TextEditingController();addTearDown(chat.dispose);var toggles=0;
   final status='Microphone state could not be confirmed. Leave this room. ${List.filled(7,'Native stop result is unknown. ').join()}End of warning.';
   final nav=GlobalKey<NavigatorState>();
   await t.pumpWidget(MaterialApp(navigatorKey:nav,debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.8)),child:w!),home:const Scaffold(body:Text('Room list fixture'))));
   nav.currentState!.push(MaterialPageRoute<void>(builder:(_)=>RepaintBoundary(key:key,child:RoomView(title:'Synthetic room',status:status,failed:true,isHost:false,speaker:true,muted:false,handUp:false,inRoom:2,hands:const {},stage:const [],messages:const [],chat:chat,onEnd:(){},onToggleMic:()=>toggles++,onRaise:(){},onGift:(){},onAllow:(_,__) {},onDismissHand:(_){},onSend:(){}))));
   await t.pumpAndSettle();expect(t.takeException(),isNull);
   final back=find.widgetWithText(FilledButton,'Back');final screen=t.view.physicalSize/t.view.devicePixelRatio;
   expect(t.getTopLeft(back).dy,greaterThanOrEqualTo(0));expect(t.getBottomRight(back).dy,lessThanOrEqualTo(screen.height));
   expect(find.byTooltip('Unmute'),findsNothing);expect(find.byTooltip('Mute'),findsNothing);expect(toggles,0);
   final warningScroll=find.byKey(const ValueKey('room-failure-scroll'));
   final scroll=t.state<ScrollableState>(find.descendant(of:warningScroll,matching:find.byType(Scrollable)));
   expect(scroll.position.maxScrollExtent,greaterThan(0));scroll.position.jumpTo(scroll.position.maxScrollExtent);await t.pumpAndSettle();
   expect(t.getBottomRight(find.text(status)).dy,lessThanOrEqualTo(t.getTopLeft(back).dy));expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/room_failure_${landscape?'landscape':'portrait'}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();});
   await t.tap(back);await t.pumpAndSettle();expect(find.text('Room list fixture'),findsOneWidget);expect(find.byType(RoomView),findsNothing);expect(toggles,0);
  });
 }}
}

// Offline sign-in form only. No real credentials, signup or social callback.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:400));await t.pump();}
Future<void> setup(WidgetTester t,Future<void> Function() body,{Future<http.Response> Function(http.Request)? response,bool register=false,String lang='en',Brightness mode=Brightness.light,double scale=1,double keyboard=0})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=lang;addTearDown(()=>prefs.lang='en');
 await http.runWithClient(()async{
  await t.pumpWidget(RepaintBoundary(key:const ValueKey('auth-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale),viewInsets:EdgeInsets.only(bottom:keyboard)),child:w!),home:AuthPage(session:Session(),initialRegister:register))));await flush(t);await body();await t.pumpWidget(const SizedBox());await flush(t);
 },()=>MockClient(response??(_){throw StateError('No request expected');}));
}
Future<void> tap(WidgetTester t,Finder f)async{await t.ensureVisible(f);await t.pumpAndSettle();await t.tap(f);await flush(t);}
void main(){
 setUpAll(()async{for(final x in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(x.$1)..addFont(Future.value(ByteData.sublistView(File(x.$2).readAsBytesSync())));await l.load();}});
 testWidgets('invalid registration does not call the network and labels are localized',(t)async{
  await setup(t,()async{await tap(t,find.widgetWithText(FilledButton,'खाता बनाउनुहोस्'));expect(find.text('आवश्यक छ'),findsOneWidget);expect(find.text('कम्तीमा ८ अक्षर'),findsOneWidget);expect(find.text('इमेल'),findsWidgets);expect(t.takeException(),isNull);},register:true,lang:'ne');
 });
 testWidgets('pending login freezes fields toggle and social; double submit makes one request',(t)async{
  final pending=Completer<http.Response>();var requests=0;await setup(t,()async{
   await t.enterText(find.byType(TextFormField).first,'fixture');await t.enterText(find.byType(TextFormField).last,'fixture-value');await tap(t,find.widgetWithText(FilledButton,'Sign in'));
   expect(requests,1);expect(t.widgetList<TextFormField>(find.byType(TextFormField)).every((w)=>w.enabled==false),isTrue);expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
   t.widget<EditableText>(find.byType(EditableText).last).onSubmitted!('');await flush(t);expect(requests,1);expect(t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,isNull);
   pending.complete(http.Response(jsonEncode({'error_description':'Fixture rejected'}),400));await flush(t);expect(find.text('Fixture rejected'),findsOneWidget);expect(t.widgetList<TextFormField>(find.byType(TextFormField)).every((w)=>w.enabled==true),isTrue);
  },response:(r)async{requests++;expect(Uri.splitQueryString(r.body)['username'],'fixture');return pending.future;});
 });
 testWidgets('password visibility is explicit and hides again after switching forms',(t)async{
  await setup(t,()async{expect(t.widget<EditableText>(find.byType(EditableText).last).obscureText,isTrue);await tap(t,find.byTooltip('Show password'));expect(t.widget<EditableText>(find.byType(EditableText).last).obscureText,isFalse);await tap(t,find.text('Create an account'));expect(t.widget<EditableText>(find.byType(EditableText).last).obscureText,isTrue);expect(t.widget<EditableText>(find.byType(EditableText).last).autofillHints,contains(AutofillHints.newPassword));});
 });
 testWidgets('malformed sign-in response restores the form with an error',(t)async{
  await setup(t,()async{await t.enterText(find.byType(TextFormField).first,'fixture');await t.enterText(find.byType(TextFormField).last,'fixture-value');await tap(t,find.byType(FilledButton));expect(find.text('Sign in failed. Try again.'),findsOneWidget);expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);expect(t.takeException(),isNull);},response:(_)async=>http.Response('bad json',200));
 });
 testWidgets('malformed response has recoverable error and disposal suppresses late UI',(t)async{
  final pending=Completer<http.Response>();await setup(t,()async{await t.enterText(find.byType(TextFormField).first,'fixture');await t.enterText(find.byType(TextFormField).last,'fixture-value');await tap(t,find.widgetWithText(FilledButton,'Sign in'));await t.pumpWidget(const SizedBox());pending.complete(http.Response('bad json',200));await flush(t);expect(t.takeException(),isNull);},response:(_)async=>pending.future);
 });
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){for(final register in [false,true]){
 testWidgets('auth localized large text ${register?'register':'signin'} ${mode.name} $lang',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await setup(t,()async{
   await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('auth-shot')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/auth_top_${register?'register':'signin'}_${lang}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   final fields=find.byType(TextFormField);
   for(var i=0;i<fields.evaluate().length;i++){
     final field=fields.at(i);await t.ensureVisible(field,alignment:0.25);await t.pumpAndSettle();
     await t.tap(field);await t.pumpAndSettle();
     await t.ensureVisible(field,alignment:0.25);await t.pumpAndSettle();
     expect(field.hitTestable(),findsOneWidget);
     expect(t.getRect(field).top,greaterThanOrEqualTo(16),reason:'floating field label must have room above the input');
     expect(t.getRect(field).bottom,lessThanOrEqualTo(400),reason:'field must remain above keyboard');
     await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('auth-shot')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/auth_field_${i}_${register?'register':'signin'}_${lang}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   }
   final action=find.byType(FilledButton);await t.ensureVisible(action);await t.pumpAndSettle();expect(t.getBottomRight(action).dy,lessThanOrEqualTo(400));expect(t.takeException(),isNull);
   await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('auth-shot')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/auth_entry_${register?'register':'signin'}_${lang}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  },register:register,lang:lang,mode:mode,scale:1.8,keyboard:240);
 });
 }}}
}

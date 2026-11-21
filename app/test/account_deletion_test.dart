// Synthetic account/API only. No deletion, deployment or live identity calls.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/account_deletion_page.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'upload_center_test.dart' as helpers;

const policy = {'policy_version':'fixture-v1','completion_notice':'Synthetic review notice: processing time is not production policy.','retention_notice':'Synthetic review notice: retention terms are not production policy.'};
Map<String,dynamic> recorded() => {'public_id':'request-fixture','status':'requested',...policy};
void main() {
 setUpAll(()async {
  Directory('test/renders').createSync(recursive:true);
  for(final item in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]) {
   final f=File(item.$2);if(f.existsSync()){final loader=FontLoader(item.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}
  }
 });
 testWidgets('disabled does not allow request or claim deletion',(t)async{
  var writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);
   expect(find.text('Account deletion is not available yet'),findsOneWidget);expect(find.text('Request deletion'),findsNothing);expect(writes,0);
  },respond:(r)async{if(r.method!='GET')writes++;return helpers.json({'available':false,'policy':null,'request':null});});
 });
 testWidgets('explicit confirmation and one pending write required',(t)async{
  var writes=0;final reply=Completer<http.Response>();
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Request deletion')).onPressed,isNull);
   await t.tap(find.byType(Checkbox));await t.pump();await t.ensureVisible(find.text('Request deletion'));await t.tap(find.text('Request deletion'));await helpers.flush(t);
   expect(writes,1);expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Check status')).onPressed,isNull);
   reply.complete(helpers.json({'request':recorded()},201));await helpers.flush(t);
   expect(find.text('Deletion requested'),findsOneWidget);expect(find.text('Your request has been recorded. Your account and data have not been deleted yet.'),findsOneWidget);expect(find.text('Request deletion'),findsNothing);
  },respond:(r)async{if(r.method=='POST'){writes++;expect(r.body,contains('fixture-v1'));return reply.future;}return helpers.json({'available':true,'policy':policy,'request':null});});
 });
 testWidgets('unknown write result requires status check before another submit',(t)async{
  var reads=0,writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);await t.tap(find.byType(Checkbox));await t.pump();await t.ensureVisible(find.text('Request deletion'));await t.tap(find.text('Request deletion'));await helpers.flush(t);
   expect(writes,1);expect(find.text('Request deletion'),findsNothing);await t.ensureVisible(find.text('Check status'));await t.tap(find.text('Check status'));await helpers.flush(t);expect(find.text('Deletion requested'),findsOneWidget);expect(writes,1);
  },respond:(r)async{if(r.method=='POST'){writes++;throw const SocketException('Synthetic unknown response');}reads++;return helpers.json({'available':true,'policy':policy,'request':reads>1?recorded():null});});
 });
 testWidgets('retired account suppresses delayed private status',(t)async{
  final reply=Completer<http.Response>();
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);s.user={'public_id':'different','username':'other'};s.notifyListeners();await t.pump();reply.complete(helpers.json({'available':true,'policy':policy,'request':recorded()}));await helpers.flush(t);
   expect(find.text('Deletion requested'),findsNothing);expect(find.text(policy['retention_notice']!),findsNothing);expect(t.takeException(),isNull);
  },respond:(_)async=>reply.future);
 });
 testWidgets('settings opens in-app deletion without sending a request',(t)async{
  var writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:SettingsPage(session:s)));await helpers.flush(t);
   await t.enterText(find.byType(TextField),'delete');await t.pump();await t.tap(find.text('Delete my account'));await t.pumpAndSettle();await helpers.flush(t);
   expect(find.byType(AccountDeletionPage),findsOneWidget);expect(writes,0);expect(find.text('Account deletion is not available yet'),findsOneWidget);
  },respond:(r)async{if(r.method!='GET')writes++;return helpers.json({'available':false,'policy':null,'request':null});});
 });
 testWidgets('same-member reauthentication retires pending deletion screen',(t)async{
  final reply=Completer<http.Response>();
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);await s.login('fixture','not-a-password');s.notifyListeners();await t.pump();reply.complete(helpers.json({'available':true,'policy':policy,'request':recorded()}));await helpers.flush(t);
   expect(find.text('Deletion requested'),findsNothing);expect(find.text('This account session has ended.'),findsOneWidget);
  },respond:(_)async=>reply.future);
 });
 testWidgets('blank policy notice does not offer confirmation',(t)async{
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);
   expect(find.byType(Checkbox),findsNothing);expect(find.text('Request deletion'),findsNothing);
  },respond:(_)async=>helpers.json({'available':true,'policy':{...policy,'retention_notice':' '},'request':null}));
 });
 testWidgets('unknown status is not reported as requested or completed',(t)async{
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:AccountDeletionPage(session:s)));await helpers.flush(t);
   expect(find.text('Deletion requested'),findsNothing);expect(find.text('Request deletion'),findsNothing);expect(find.text('Request status could not be verified. Check its status again.'),findsOneWidget);
  },respond:(_)async=>helpers.json({'available':true,'policy':policy,'request':{...recorded(),'status':'unexpected'}}));
 });
 for(final language in ['en','ne']){for(final status in ['confirmation','requested']){for(final brightness in [Brightness.light,Brightness.dark]){
 testWidgets('render $status ${brightness.name} $language narrow large text',(t)async{
  prefs.lang=language;addTearDown(()=>prefs.lang='en');
  t.view.physicalSize=const Size(320,760);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('deletion-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.5)),child:w!),onGenerateRoute:(_)=>MaterialPageRoute(builder:(_)=>const Scaffold()),onGenerateInitialRoutes:(_)=>[MaterialPageRoute(builder:(_)=>const Scaffold()),MaterialPageRoute(builder:(_)=>AccountDeletionPage(session:s))])));await helpers.flush(t);expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('deletion-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/account_deletion_${status}_${brightness.name}_$language.png').writeAsBytesSync(data!.buffer.asUint8List());});
  },respond:(_)async=>helpers.json({'available':true,'policy':policy,'request':status=='requested'?recorded():null}));
 });}}}
}

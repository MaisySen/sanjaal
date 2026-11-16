// Synthetic comments, pending HTTP and layout fixtures. No device/network proof.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type':'application/json; charset=utf-8'});
Map<String,dynamic> comment(String id, {String? parent, String? body, String author = 'me'}) => {'public_id':id,'body':body ?? 'Comment $id','parent_id':parent,'author':{'public_id':author,'username':author,'name':author},'created_at':'2026-11-17T00:00:00Z'};
Future<void> flush(WidgetTester t) async { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20))); await t.pump(); await t.pump(const Duration(milliseconds: 400)); }
Future<void> fixture(WidgetTester t, Future<http.Response> Function(http.Request) respond, Future<void> Function() run, {Brightness brightness = Brightness.light, double scale = 1, String language = 'en', double keyboard = 0, void Function(int?)? closed}) async {
  SharedPreferences.setMockInitialValues({}); prefs.lang=language; addTearDown(()=>prefs.lang='en');
  await http.runWithClient(() async {
    final s=Session(); await s.login('fixture','not-a-password');
    await t.pumpWidget(RepaintBoundary(key:const ValueKey('comments-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']), builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale),viewInsets:EdgeInsets.only(bottom:keyboard)),child:w!),home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:() async {
      final value=await showModalBottomSheet<int>(context:c,isScrollControlled:true,isDismissible:false,enableDrag:false,builder:(_)=>CommentsSheet(session:s,postId:'post',postAuthorId:'me'));
      closed?.call(value);
    },child:const Text('Open fixture')))))));
    await t.tap(find.text('Open fixture')); await flush(t); await run();
    await t.pumpWidget(const SizedBox()); await t.pump(const Duration(seconds:1));
  },()=>MockClient((r) async {
    if(r.url.path.endsWith('/oauth/token')) return json({'access_token':'fixture','expires_in':3600});
    if(r.url.path.endsWith('/auth/me')) return json({'user':{'public_id':'me','username':'me'}});
    return respond(r);
  }));
}
Future<void> tap(WidgetTester t,String text) async { await t.ensureVisible(find.text(text).first); await t.tap(find.text(text).first); await flush(t); }
IconButton button(WidgetTester t, String label) => t.widget<IconButton>(find.ancestor(of:find.byTooltip(label),matching:find.byType(IconButton)).first);
Future<void> send(WidgetTester t) async { await t.tap(find.byTooltip('Send comment')); await flush(t); }
void main(){
  setUpAll(() async {
    for(final pair in [('Roboto','${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
      final f=File(pair.$2); if(f.existsSync()){final l=FontLoader(pair.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}
    }
  });
  testWidgets('limited comments remain readable and deletable without allowing a new send or reply',(t)async{
    var writes=0;var deletes=0;
    await fixture(t,(r)async{
      if(r.method=='POST')writes++;
      if(r.method=='DELETE'){deletes++;return json({'deleted':true,'removed_count':1});}
      return json({'data':[comment('a')],'next_cursor':null,'can_comment':false});
    },()async{
      expect(find.text('Comment a'),findsOneWidget);
      expect(find.text('Comments are limited by this member.'),findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).enabled,isFalse);
      expect(button(t,'Send comment').onPressed,isNull);
      expect(t.widget<TextButton>(find.widgetWithText(TextButton,'Reply')).onPressed,isNull);
      expect(button(t,'Delete').onPressed,isNotNull);
      await t.tap(find.byTooltip('Delete'));await flush(t);
      expect(writes,0);expect(deletes,1);expect(find.text('Comment a'),findsNothing);
    });
  });
  testWidgets('one page only, recoverable cursor failure, dedupe and lazy next page', (t) async {
    final cursors=<String?>[]; var fail=true;
    await fixture(t,(r) async {
      cursors.add(r.url.queryParameters['cursor']);
      if(cursors.last=='page2' && fail){fail=false;return json({'message':'Fixture read failed'},503);}
      return cursors.last==null?json({'data':[comment('a')],'next_cursor':'page2'}):json({'data':[comment('a'),comment('b')],'next_cursor':null});
    },() async {
      expect(cursors,[null]); expect(find.text('Comment a'),findsOneWidget);
      await tap(t,'Load more comments'); expect(find.text('Comment a'),findsOneWidget);expect(find.text('Fixture read failed'),findsOneWidget);
      await tap(t,'Try again');expect(cursors,[null,'page2','page2']);expect(find.text('Comment a'),findsOneWidget);expect(find.text('Comment b'),findsOneWidget);expect(find.text('Load more comments'),findsNothing);
    });
  });
  testWidgets('initial failure can retry without dismissing or losing draft', (t) async {
    var reads=0;await fixture(t,(r)async=>++reads==1?json({'message':'Fixture offline'},503):json({'data':[comment('a')],'next_cursor':null}),()async{
      await t.enterText(find.byType(TextField),'Keep me');await tap(t,'Try again');expect(find.text('Keep me'),findsOneWidget);expect(find.text('Comment a'),findsOneWidget);
    });
  });
  testWidgets('sending freezes draft and reply, blocks repeated send and route close', (t)async{
    final pending=Completer<http.Response>();var writes=0;String? request;
    await fixture(t,(r)async{if(r.method=='POST'){writes++;request=r.body;return pending.future;}return json({'data':[comment('a',author:'asha')],'next_cursor':null});},()async{
      await t.tap(find.widgetWithText(TextButton,'Reply').first);await flush(t);await t.enterText(find.byType(TextField),'Thoughtful reply');await send(t);
      expect(t.widget<TextField>(find.byType(TextField)).enabled,isFalse);expect(button(t,'Cancel reply').onPressed,isNull);expect(t.widget<TextButton>(find.widgetWithText(TextButton,'Reply').first).onPressed,isNull);
      await t.tap(find.byTooltip('Send comment'),warnIfMissed:false);await t.tap(find.byTooltip('Close comments'));await flush(t);expect(find.byType(CommentsSheet),findsOneWidget);expect(writes,1);
      pending.complete(json({'comment':comment('new',parent:'a',body:'Thoughtful reply')},201));await flush(t);
      expect(jsonDecode(request!)['parent_id'],'a');expect(t.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);expect(find.text('Thoughtful reply'),findsOneWidget);
    });
  });
  testWidgets('rejected send retains reply and text for explicit retry', (t)async{
    var writes=0;await fixture(t,(r)async{if(r.method=='POST')return ++writes==1?json({'message':'Fixture rejected'},422):json({'comment':comment('new',parent:'a',body:'Retained reply')},201);return json({'data':[comment('a')],'next_cursor':null});},()async{
      await t.tap(find.widgetWithText(TextButton,'Reply').first);await flush(t);await t.enterText(find.byType(TextField),'Retained reply');await send(t);expect(find.text('Retained reply'),findsOneWidget);expect(find.text('Replying to @me'),findsOneWidget);await send(t);expect(writes,2);expect(find.text('Replying to @me'),findsNothing);
    });
  });
  testWidgets('late page preserves sent item and inserts old rows before it without duplicates',(t)async{
    final page=Completer<http.Response>();var reads=0;
    await fixture(t,(r)async{if(r.method=='POST')return json({'comment':comment('new')},201);return ++reads==1?json({'data':[comment('a')],'next_cursor':'page2'}):page.future;},()async{
      await tap(t,'Load more comments');await t.enterText(find.byType(TextField),'Hello');await send(t);page.complete(json({'data':[comment('b'),comment('new')],'next_cursor':null}));await flush(t);
      expect(find.text('Comment new'),findsOneWidget);expect(t.getTopLeft(find.text('Comment b')).dy,lessThan(t.getTopLeft(find.text('Comment new')).dy));
    });
  });
  for(final malformed in [false,true]){
    testWidgets('${malformed?'malformed success':'transport loss'} blocks blind retry and preserves draft during review', (t)async{
      var writes=0;var reads=0;
      await fixture(t,(r)async{if(r.method=='POST'){writes++;if(malformed)return json({'comment':{}});throw const SocketException('Fixture lost response');}reads++;return json({'data':[comment('a')],'next_cursor':null});},()async{
        await t.enterText(find.byType(TextField),'Possibly sent');await send(t);expect(writes,1);expect(button(t,'Send comment').onPressed,isNull);
        await t.enterText(find.byType(TextField),'Edited draft');await tap(t,'Check comments');expect(reads,2);expect(find.text('Edited draft'),findsOneWidget);expect(writes,1);
        await tap(t,'New comment');await tap(t,'Cancel');expect(button(t,'Send comment').onPressed,isNull);
        await tap(t,'New comment');await t.tap(find.widgetWithText(TextButton,'New comment').last);await flush(t);expect(button(t,'Send comment').onPressed,isNotNull);expect(writes,1);
      });
    });
  }
  testWidgets('close guard keeps draft until explicit discard and returns no mutation',(t)async{
    int? result;await fixture(t,(_)async=>json({'data':[],'next_cursor':null}),()async{
      await t.enterText(find.byType(TextField),'Important draft');await t.tap(find.byTooltip('Close comments'));await flush(t);await tap(t,'Keep editing');expect(find.text('Important draft'),findsOneWidget);
      await t.binding.handlePopRoute();await flush(t);await tap(t,'Discard');expect(find.byType(CommentsSheet),findsNothing);expect(result,0);
    },closed:(r)=>result=r);
  });
  testWidgets('deleted thread stays removed across late page and returns full server count',(t)async{
    final page=Completer<http.Response>();int? result;var reads=0;
    await fixture(t,(r)async{if(r.method=='DELETE')return json({'deleted_count':4});return ++reads==1?json({'data':[comment('a')],'next_cursor':'page2'}):page.future;},()async{
      await tap(t,'Load more comments');await t.tap(find.byTooltip('Delete'));await flush(t);page.complete(json({'data':[comment('a'),comment('r',parent:'a'),comment('b')],'next_cursor':null}));await flush(t);
      expect(find.text('Comment a'),findsNothing);expect(find.text('Comment r'),findsNothing);expect(find.text('Comment b'),findsOneWidget);await t.tap(find.byTooltip('Close comments'));await flush(t);expect(result,-4);
    },closed:(r)=>result=r);
  });
  testWidgets('deleting last visible row does not hide the next-page action',(t)async{
    await fixture(t,(r)async=>r.method=='DELETE'?json({'deleted_count':1}):json({'data':[comment('a')],'next_cursor':'page2'}),()async{await t.tap(find.byTooltip('Delete'));await flush(t);expect(find.text('Load more comments'),findsOneWidget);});
  });
  testWidgets('refresh retry repeats refresh rather than switching to an old next page',(t)async{
    final cursors=<String?>[];await fixture(t,(r)async{cursors.add(r.url.queryParameters['cursor']);return cursors.length==2?json({'message':'Refresh failed'},503):json({'data':[comment('a')],'next_cursor':'page2'});},()async{
      await t.tap(find.byTooltip('Refresh comments'));await flush(t);await tap(t,'Try again');expect(cursors,[null,null,null]);
    });
  });
  testWidgets('changing reply selection preserves an existing draft',(t)async{
    await fixture(t,(_)async=>json({'data':[comment('a')],'next_cursor':null}),()async{
      await t.enterText(find.byType(TextField),'Existing draft');await t.tap(find.widgetWithText(TextButton,'Reply'));await flush(t);expect(find.text('Existing draft'),findsOneWidget);
      await t.tap(find.byTooltip('Cancel reply'));await flush(t);expect(find.text('Existing draft'),findsOneWidget);
    });
  });
  testWidgets('deleting selected reply target never silently converts draft to a root comment',(t)async{
    var writes=0;await fixture(t,(r)async{if(r.method=='POST'){writes++;return json({});}return r.method=='DELETE'?json({'deleted_count':1}):json({'data':[comment('a')],'next_cursor':null});},()async{
      await t.tap(find.widgetWithText(TextButton,'Reply'));await flush(t);await t.enterText(find.byType(TextField),'Reply draft');await t.tap(find.byTooltip('Delete'));await flush(t);
      expect(find.text('Original comment removed. Choose another reply or cancel.'),findsOneWidget);expect(button(t,'Send comment').onPressed,isNull);expect(find.text('Reply draft'),findsOneWidget);expect(writes,0);
      await t.tap(find.byTooltip('Cancel reply'));await flush(t);expect(button(t,'Send comment').onPressed,isNotNull);expect(writes,0);
    });
  });
  for(final reel in [false,true]){
    testWidgets('actual ${reel?'reel':'post'} route protects a draft and reconciles server count',(t)async{
      SharedPreferences.setMockInitialValues({});var countReads=0;
      await http.runWithClient(()async{
        final session=Session();await session.login('fixture','not-a-password');
        final post={'public_id':'post','kind':reel?'reel':'post','body':'Community discussion','author':{'public_id':'asha','username':'asha'},'media':[],'hashtags':[],'comments_count':8,'likes_count':0,'created_at':'2026-11-17T00:00:00Z'};
        await t.pumpWidget(MaterialApp(theme:buildTheme(Brightness.light),home:Scaffold(body:reel?ReelItem(session:session,reel:post,playing:false,muted:true,onToggleMute:(){}):PostCard(session:session,post:post,onRemoved:(){}))));await flush(t);
        await t.tap(reel?find.byTooltip('8'):find.text('8'));await flush(t);await t.enterText(find.byType(TextField),'Keep this draft');
        await t.tapAt(const Offset(10,10));await flush(t);expect(find.byType(CommentsSheet),findsOneWidget);
        await t.drag(find.byType(CommentsSheet),const Offset(0,400));await flush(t);expect(find.text('Keep this draft'),findsOneWidget);
        await t.tap(find.byTooltip('Close comments'));await flush(t);await tap(t,'Discard');await flush(t);expect(countReads,1);expect(find.text('3'),findsOneWidget);
        await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:1));
      },()=>MockClient((r)async{
        if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'fixture','expires_in':3600});
        if(r.url.path.endsWith('/auth/me'))return json({'user':{'public_id':'me','username':'me'}});
        if(r.url.path.endsWith('/comments'))return json({'data':[],'next_cursor':null});
        if(r.url.path.endsWith('/posts/post')){countReads++;return json({'post':{'comments_count':3}});}
        return json({});
      }));
    });
  }
  for(final operation in ['read','send','delete']){
    testWidgets('completion after forced disposal is safe: $operation',(t)async{
      final pending=Completer<http.Response>();await fixture(t,(r)async{
        if(operation=='read'||(operation=='send'&&r.method=='POST')||(operation=='delete'&&r.method=='DELETE'))return pending.future;
        return json({'data':[comment('a')],'next_cursor':null});
      },()async{
        if(operation=='send'){await t.enterText(find.byType(TextField),'Pending');await send(t);}
        if(operation=='delete'){await t.tap(find.byTooltip('Delete'));await flush(t);}
        await t.pumpWidget(const SizedBox());pending.complete(json(operation=='read'?{'data':[],'next_cursor':null}:operation=='send'?{'comment':comment('new')}:{'deleted_count':1}));await flush(t);expect(t.takeException(),isNull);
      });
    });
  }
  for(final language in ['en','ne']){for(final brightness in [Brightness.light,Brightness.dark]){
    testWidgets('populated comments and reply ${brightness.name} $language',(t)async{
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await fixture(t,(_)async=>json({'data':[comment('a',author:'asha',body:language=='ne'?'अर्को हप्ता सामुदायिक भेटघाट कहाँ गर्ने?':'Where should we meet for the next community gathering?'),comment('r',parent:'a',author:'bina',body:'Saturday works for me.')],'next_cursor':null}),()async{
        final reply=find.widgetWithText(TextButton,language=='ne'?'जवाफ':'Reply');
        await t.ensureVisible(reply);await t.tap(reply);await flush(t);await t.enterText(find.byType(TextField),language=='ne'?'म पनि आउँछु।':'I will be there too.');await flush(t);expect(t.takeException(),isNull);
        await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('comments-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/comments_reply_${brightness.name}_$language.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
      },brightness:brightness,scale:1.8,language:language,keyboard:240);
    });
  }}
  for(final language in ['en','ne']){for(final brightness in [Brightness.light,Brightness.dark]){
    testWidgets('comments small phone large text ${brightness.name} $language',(t)async{
      t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await fixture(t,(r)async{if(r.method=='POST')throw const SocketException('Fixture response lost');return json({'data':[comment('a',author:'asha',body:'A thoughtful conversation about our next community gathering.')],'next_cursor':'next'});},()async{
        await t.enterText(find.byType(TextField),'A reply I want to keep');await t.tap(find.byTooltip(language=='ne'?'टिप्पणी पठाउनुहोस्':'Send comment'));await flush(t);expect(t.takeException(),isNull);
        await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('comments-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/comments_recovery_${brightness.name}_$language.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
      },brightness:brightness,scale:1.8,language:language,keyboard:240);
    });
  }}
}

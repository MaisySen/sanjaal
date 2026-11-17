// Synthetic HTTP and generated PNG only. Not Samsung/native upload evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/wallet_page.dart';
import 'upload_center_test.dart' as helpers;

void main() {
  for(final failFirst in [false,true]) {
    testWidgets('story production handoff leaves app usable and ${failFirst?'retries original':'inserts confirmation'}', (t) async {
      final pending=Completer<http.Response>();final bodies=<String>[];var writes=0;
      final recorder=ui.PictureRecorder();Canvas(recorder).drawColor(const Color(0xFF286067),BlendMode.src);
      final picture=recorder.endRecording();
      final data=(await t.runAsync(()async{final image=await picture.toImage(16,16);return (await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();}))!;
      final file=XFile.fromData(data,name:'synthetic-story.png',mimeType:'image/png');
      await helpers.fixture(t,(session,center)async {
        session.protectedStoriesEnabled=true;
        final nav=GlobalKey<NavigatorState>();
        await t.pumpWidget(MaterialApp(navigatorKey:nav,theme:buildTheme(Brightness.dark),home:HomeShell(session:session)));
        await helpers.flush(t);
        nav.currentState!.push(MaterialPageRoute(builder:(_)=>StoryComposePage(session:session,file:file,isVideo:false,backgroundUpload:true)));
        await helpers.flush(t);
        await t.enterText(find.byType(TextField),'Immutable synthetic caption');
        await t.tap(find.text('Share story'));await helpers.flush(t);await t.pump(const Duration(milliseconds:400));
        expect(find.byType(StoryComposePage),findsNothing);
        expect(center.busy,isTrue);expect(writes,1);
        await t.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.text('Wallet')));await helpers.flush(t);
        expect(find.byType(WalletPage),findsOneWidget);
        if(failFirst) {
          pending.completeError(http.ClientException('Synthetic lost reply'));await helpers.flush(t);
          final retry=find.descendant(of:find.byType(UploadStrip),matching:find.text('Try again'));
          expect(center.canRetry,isTrue);expect(retry,findsOneWidget);
          await t.tap(retry);await helpers.flush(t);
          expect(writes,2);expect(bodies[1],bodies[0],reason:'same multipart snapshot and intent on explicit retry');
        } else {
          pending.complete(helpers.json({'story':{'public_id':'original','url':'https://fixture.invalid/story.png','type':'image','caption':'Immutable synthetic caption'}}));
          await helpers.flush(t);
        }
        expect(center.error,isNull);expect(center.confirmedStories.single['public_id'],'original');
        expect(find.text('Your story is up.'),findsOneWidget);expect(t.takeException(),isNull);
      },respond:(request)async {
        if(request.method=='POST'&&request.url.path.endsWith('/stories')) {
          writes++;final body=latin1.decode(request.bodyBytes);
          // Multipart boundary is transport-specific. All actual fields/bytes must match.
          bodies.add(body.replaceAll(RegExp(r'--dart-http-boundary-[^\r\n]+'),'--BOUNDARY'));
          expect(body,contains('Immutable synthetic caption'));expect(body,contains('protected_media'));expect(body,contains('upload_intent'));
          if(writes==1)return pending.future;
          return helpers.json({'story':{'public_id':'original','url':'https://fixture.invalid/story.png','type':'image','caption':'Immutable synthetic caption'},'replayed':true});
        }
        return helpers.json({'data':[],'next_cursor':null,'balance':0,'entries':[],'unread_messages':0});
      });
    });
  }
}

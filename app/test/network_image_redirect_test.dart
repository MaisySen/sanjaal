// Actual Flutter NetworkImage + loopback HTTP. Only a non-secret sentinel is
// used. No user credential, public network, production media or device claim.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
class DirectHttp extends HttpOverrides { HttpClient direct()=>super.createHttpClient(null); }
void main(){
 for(final crossOrigin in [false,true]){
 testWidgets('actual NetworkImage sensitive header redirect cross-origin=$crossOrigin',(t)async{
  await t.runAsync(()async{
   final a=await HttpServer.bind(InternetAddress.loopbackIPv4,0),b=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
   final client=DirectHttp().direct();final old=debugNetworkImageHttpClientProvider;debugNetworkImageHttpClientProvider=()=>client;
   final recorder=ui.PictureRecorder();ui.Canvas(recorder).drawColor(const ui.Color(0xff123456),ui.BlendMode.src);
   final pixel=await recorder.endRecording().toImage(2,2);final bytes=(await pixel.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();pixel.dispose();
   var finalRequests=0;bool? retained;final done=Completer<void>();
   Future<void> respond(HttpRequest r)async{
    if(r.uri.path=='/start'){
     r.response.statusCode=302;r.response.headers.set('location','http://127.0.0.1:${crossOrigin?b.port:a.port}/image');await r.response.close();return;
    }
    finalRequests++;retained=r.headers.value('authorization')!=null;r.response.headers.contentType=ContentType('image','png');r.response.add(bytes);await r.response.close();
   }
   a.listen(respond);b.listen(respond);
   final image=NetworkImage('http://127.0.0.1:${a.port}/start',headers:{'Authorization':'non-secret-redirect-sentinel'});
   final stream=image.resolve(ImageConfiguration.empty);
   final listener=ImageStreamListener((info,_) {info.dispose();if(!done.isCompleted)done.complete();},onError:(Object e,StackTrace? s){if(!done.isCompleted)done.completeError(e,s);});
   try{
    stream.addListener(listener);await done.future.timeout(const Duration(seconds:10));
    expect(finalRequests,1);expect(retained,!crossOrigin);
   }finally{stream.removeListener(listener);await image.evict();debugNetworkImageHttpClientProvider=old;client.close(force:true);await a.close(force:true);await b.close(force:true);}
  });
 });
 }
}

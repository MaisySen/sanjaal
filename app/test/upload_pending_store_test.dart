import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/upload_pending_store.dart';

class Store extends UploadPendingStore {
 bool failRead=false,failWrite=false,failClear=false; Map<String,dynamic>? saved;
 @override Future<Map<String,dynamic>?> read(String owner)async{if(failRead)throw StateError('read');return saved;}
 @override Future<void> write(String owner,String id,String kind)async{if(failWrite)throw StateError('write');saved={'version':1,'id':id,'kind':kind};}
 @override Future<void> clear(String owner)async{if(failClear)throw StateError('clear');saved=null;}
}
Future<void> flush(WidgetTester t)async{await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:15)));await t.pump();}
Session member([String id='owner'])=>Session()..user={'public_id':id,'username':id};
Map<String,dynamic> post()=>{'public_id':'confirmed','kind':'post','author':{'public_id':'owner','username':'owner'},'media':[]};
void main(){
 const store=UploadPendingStore();
 test('secure marker round-trips, stays member-scoped and clears with readback',()async{
  FlutterSecureStorage.setMockInitialValues({});final first=newUploadIntent(),second=newUploadIntent();
  await store.write('one',first,'post');await store.write('two',second,'story');expect((await store.read('one'))!['id'],first);
  await store.clear('one');expect(await store.read('one'),isNull);expect((await store.read('two'))!['id'],second);
 });
 testWidgets('reopened app is paused by the earlier marker and never automatically sends',(t)async{
  await store.write('owner',newUploadIntent(),'reel');final s=member();final center=UploadCenter.of(s);var writes=0;await flush(t);
  expect(center.restoring,isFalse);expect(center.error,isA<UploadError>());expect(center.canRetry,isFalse);expect(center.start('post',()async{writes++;return post();}),isFalse);expect(writes,0);
  await center.dismiss();expect(await store.read('owner'),isNull);expect(center.start('post',()async{writes++;return post();}),isTrue);await flush(t);expect(writes,1);
 });
 testWidgets('storage write failure prevents any network closure and keeps retry original',(t)async{
  final storage=Store()..failWrite=true;final center=UploadCenter.of(member(),store:storage);await flush(t);var writes=0;
  center.start('post',()async{writes++;return post();});await flush(t);expect(writes,0);expect(center.error.toString(),contains('Nothing was sent'));expect(center.canRetry,isTrue);
  storage.failWrite=false;center.retry();await flush(t);expect(writes,1);expect(center.error,isNull);expect(storage.saved,isNull);
 });
 testWidgets('marker is saved before the first request begins',(t)async{
  final storage=Store();final center=UploadCenter.of(member(),store:storage);await flush(t);
  center.start('post',()async{expect(storage.saved?['kind'],'post');return post();});await flush(t);expect(center.result?['public_id'],'confirmed');expect(storage.saved,isNull);
 });
 testWidgets('unreadable safety info fails closed rather than assuming no prior upload',(t)async{
  final storage=Store()..failRead=true;final center=UploadCenter.of(member(),store:storage);await flush(t);expect(center.occupied,isTrue);expect(center.canRetry,isFalse);expect(center.start('post',()async=>post()),isFalse);
 });
 testWidgets('clear failure retains known success and blocks a separate send',(t)async{
  final storage=Store()..failClear=true;final center=UploadCenter.of(member(),store:storage);await flush(t);var writes=0;
  center.start('post',()async{writes++;return post();});await flush(t);expect(writes,1);expect(center.result?['public_id'],'confirmed');expect(center.confirmedPosts.length,1);expect(center.canRetry,isFalse);expect(center.occupied,isTrue);
  await center.dismiss();expect(center.occupied,isTrue);expect(writes,1);storage.failClear=false;await center.dismiss();expect(center.occupied,isFalse);expect(writes,1);
 });
 testWidgets('account change during preparation prevents a queued original from starting',(t)async{
  final storage=Store();final s=member();final center=UploadCenter.of(s,store:storage);await flush(t);
  s.user={'public_id':'other','username':'other'};s.notifyListeners();await flush(t);expect(center.result,isNull);expect(center.confirmedPosts,isEmpty);
 });
}

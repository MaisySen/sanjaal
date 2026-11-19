import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sanjaal/creator_media_draft_store.dart';

class FailingMedia extends XFile {
  FailingMedia():super('/not-a-file/media.jpg');
  @override Future<int> length()async=>4;
  @override Stream<Uint8List> openRead([int? start,int? end])async*{throw StateError('picker file disappeared');}
}
class GrowingMedia extends XFile {
 GrowingMedia():super('growing.jpg');
 @override Future<int> length()async=>4;
 @override Stream<Uint8List> openRead([int? start,int? end])async*{yield Uint8List(5);throw StateError('must stop before second chunk');}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late Directory root;late CreatorMediaDraftStore store;
 final payload=Uint8List.fromList(utf8.encode('private synthetic media bytes'));
 XFile file({String name='original.jpg'})=>XFile.fromData(payload,path:name,name:name);
 setUp(()async{FlutterSecureStorage.setMockInitialValues({});root=await Directory.systemTemp.createTemp('media-drafts-test-');store=CreatorMediaDraftStore(testRoot:root);});
 tearDown(()async{await root.delete(recursive:true);});
 test('encrypted immutable media copy survives picker loss and store reconstruction',()async{
  final d=await store.save('a',text:'Caption नमस्ते',video:false,files:[file(),file(name:'second.png')]);
  final disk=await root.list(recursive:true).where((e)=>e is File).cast<File>().toList();
  expect(disk.length,2);
  for(final f in disk){final bytes=await f.readAsBytes();expect(utf8.decode(bytes,allowMalformed:true),isNot(contains('private synthetic')));}
  final reopened=CreatorMediaDraftStore(testRoot:root);final list=await reopened.read('a');expect(list.single.toJson(),d.toJson());
  final files=await reopened.open('a',list.single);expect(await files[0].readAsBytes(),payload);expect(await files[1].readAsBytes(),payload);
  expect(await reopened.read('b'),isEmpty);await expectLater(reopened.open('b',d),throwsStateError);
 });
 test('changed file stream is bounded before encryption and does not commit',()async{
  await expectLater(store.save('a',text:'Changed',video:false,files:[GrowingMedia()]),throwsStateError);
  expect(await store.read('a'),isEmpty);
 });
 for(final audience in ['followers','close_friends','only_me']){
  test('story caption media and $audience audience survive reopening and attempted reset',()async{
   final d=await store.save('a',text:'Story',video:false,files:[file()],story:true,audience:audience);
   final restored=(await CreatorMediaDraftStore(testRoot:root).read('a')).single;
   expect(restored.story,isTrue);expect(restored.audience,audience);expect(restored.text,'Story');
   final marked=await store.attempted('a',restored,value:true);
   final reset=await store.attempted('a',marked,value:false);
   expect(reset.audience,audience);expect(reset.story,isTrue);
   expect(await (await store.open('a',reset)).single.readAsBytes(),payload);
   await expectLater(store.save('a',text:'Wrong editor',video:false,files:[file()],id:d.id,expectedRevision:reset.revision,expectedStamp:reset.stamp),throwsStateError);
  });
 }
 test('story storage rejects unknown audience or multiple photos instead of widening visibility',()async{
  await expectLater(store.save('a',text:'Story',video:false,files:[file()],story:true),throwsArgumentError);
  await expectLater(store.save('a',text:'Story',video:false,files:[file()],story:true,audience:'everyone'),throwsArgumentError);
  await expectLater(store.save('a',text:'x'*201,video:false,files:[file()],story:true,audience:'only_me'),throwsArgumentError);
  await expectLater(store.save('a',text:'Story',video:false,files:[file(),file()],story:true,audience:'only_me'),throwsArgumentError);
  expect(await store.read('a'),isEmpty);
 });
 test('video and photo limits reject incompatible selections',()async{
  await expectLater(store.save('a',text:'',video:true,files:[file()]),throwsStateError);
  await expectLater(store.save('a',text:'',video:false,files:List.generate(5,(_)=>file())),throwsArgumentError);
  final d=await store.save('a',text:'',video:true,files:[file(name:'clip.mp4')]);expect(d.video,isTrue);expect((await store.open('a',d)).single.name,'media.mp4');
 });
 test('interrupted replacement keeps previous complete revision readable',()async{
  final d=await store.save('a',text:'Old caption',video:false,files:[file()]);
  await expectLater(store.save('a',text:'New caption',video:false,files:[file(),FailingMedia()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp),throwsStateError);
  expect((await store.read('a')).single.toJson(),d.toJson());expect(await (await store.open('a',d)).single.readAsBytes(),payload);
 });
 test('stale delete and stale save cannot erase newer saved revision',()async{
  final d=await store.save('a',text:'Old',video:false,files:[file()]);
  final newer=await store.save('a',text:'New',video:false,files:[file()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp);
  await expectLater(store.remove('a',d),throwsStateError);
  await expectLater(store.save('a',text:'Stale',video:false,files:[file()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp),throwsStateError);
  expect((await store.read('a')).single.toJson(),newer.toJson());
 });
 test('attempted media stays guarded across a new instance until explicit separate upload',()async{
  final d=await store.save('a',text:'Caption',video:false,files:[file()]);
  final attempted=await store.attempted('a',d,value:true);
  expect((await CreatorMediaDraftStore(testRoot:root).read('a')).single.attempted,isTrue);
  await expectLater(store.attempted('a',d,value:false),throwsStateError);
  await expectLater(store.remove('a',d),throwsStateError);
  await expectLater(store.save('a',text:'Changed',video:false,files:[file()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp),throwsStateError);
  final reset=await store.attempted('a',attempted,value:false);expect(reset.attempted,isFalse);
  expect(await (await store.open('a',reset)).single.readAsBytes(),payload);
 });
 test('old confirmation stays stale even after attempted guard resets',()async{
  final d=await store.save('a',text:'Caption',video:false,files:[file()]);
  final attempted=await store.attempted('a',d,value:true);
  final reset=await store.attempted('a',attempted,value:false);
  expect(reset.stamp,isNot(d.stamp));
  await expectLater(store.remove('a',d),throwsStateError);
  await expectLater(store.attempted('a',d,value:true),throwsStateError);
  await expectLater(store.save('a',text:'Old',video:false,files:[file()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp),throwsStateError);
 });
 test('next save collects interrupted revisions but not a live saved copy',()async{
  final d=await store.save('a',text:'Old',video:false,files:[file()]);
  await expectLater(store.save('a',text:'Fail',video:false,files:[file(),FailingMedia()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp),throwsStateError);
  final next=await store.save('a',text:'New',video:false,files:[file()],id:d.id,expectedRevision:d.revision,expectedStamp:d.stamp);
  expect(await (await store.open('a',next)).single.readAsBytes(),payload);
 });
 test('missing or tampered encrypted file never returns partial media',()async{
  final d=await store.save('a',text:'Caption',video:false,files:[file(),file()]);
  final disk=await root.list(recursive:true).where((e)=>e is File).cast<File>().toList();
  final data=await disk.last.readAsBytes();data[15]^=1;await disk.last.writeAsBytes(data);
  await expectLater(store.open('a',d),throwsA(anything));
  await disk.last.delete();await expectLater(store.open('a',d),throwsStateError);
  expect((await store.read('a')).single.id,d.id);
 });
 test('symlink replacement cannot read or delete a different directory',()async{
  final d=await store.save('a',text:'Caption',video:false,files:[file()]);
  final disk=await root.list(recursive:true).where((e)=>e is File).cast<File>().single;
  final outside=await Directory.systemTemp.createTemp('media-outside-');
  try{
   final protected=File('${outside.path}/protected');await protected.writeAsString('keep');
   final revision=disk.parent;await revision.delete(recursive:true);await Link(revision.path).create(outside.path);
   await expectLater(store.open('a',d),throwsStateError);expect(await protected.readAsString(),'keep');
   await store.remove('a',d);expect(await protected.readAsString(),'keep');
  }finally{await outside.delete(recursive:true);}
 });
 test('delete removes only current account draft encrypted files',()async{
  final a=await store.save('a',text:'A',video:false,files:[file()]);final b=await store.save('b',text:'B',video:false,files:[file()]);
  await store.remove('a',a);expect(await store.read('a'),isEmpty);expect(await (await store.open('b',b)).single.readAsBytes(),payload);
 });
 test('eight media draft bound does not silently evict an older copy',()async{
  for(var i=0;i<8;i++){await store.save('a',text:'$i',video:false,files:[file()]);}
  await expectLater(store.save('a',text:'ninth',video:false,files:[file()]),throwsStateError);expect((await store.read('a')).length,8);
 });
}

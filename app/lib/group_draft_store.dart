import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One explicitly saved group plan per account. This is not a server replay key,
/// a conversation, membership, an invitation or permission to create anything.
class GroupDraft {
  GroupDraft._(this.title,this.people,this.revision,this.attempted);
  final String title,revision;
  final List<Map<String,dynamic>> people;
  final bool attempted;
  Map<String,dynamic> toJson()=>{'version':1,'title':title,'people':people,'revision':revision,'attempted':attempted};
  static GroupDraft decode(dynamic value){
    if(value is! Map || value['version']!=1 || value['title'] is! String || (value['title'] as String).length>80 ||
       value['revision'] is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['revision']) || value['attempted'] is! bool ||
       value['people'] is! List || (value['people'] as List).length>49)throw const FormatException('Unrecognized group draft');
    final people=<Map<String,dynamic>>[];final ids=<String>{},names=<String>{};
    for(final item in value['people']){
      if(item is! Map || item['public_id'] is! String || (item['public_id'] as String).isEmpty || (item['public_id'] as String).length>256 ||
         item['username'] is! String || (item['username'] as String).trim().isEmpty || (item['username'] as String).length>80 ||
         item['name'] is! String || (item['name'] as String).length>200 || !ids.add(item['public_id']) || !names.add(item['username']))throw const FormatException('Unrecognized group member');
      people.add(Map.unmodifiable({'public_id':item['public_id'],'username':item['username'],'name':item['name']}));
    }
    return GroupDraft._(value['title'],List.unmodifiable(people),value['revision'],value['attempted']);
  }
}
class GroupDraftStore {
  const GroupDraftStore();
  static const _storage=FlutterSecureStorage();
  static final _tails=<String,Future<void>>{};
  static String _key(String owner){if(owner.isEmpty || owner.length>256)throw ArgumentError('Account required');return 'group_draft_v1_${sha256.convert(utf8.encode(owner))}';}
  Future<GroupDraft?> read(String owner)async{
    final raw=await _storage.read(key:_key(owner));if(raw==null)return null;
    if(raw.length>50000)throw const FormatException('Group draft exceeds its bound');
    return GroupDraft.decode(jsonDecode(raw));
  }
  Future<T> _serial<T>(String owner,Future<T> Function() action)async{
    final key=_key(owner),before=_tails[_key(owner)]??Future<void>.value();
    final work=before.then((_)=>action());final tail=work.then<void>((_) {},onError:(Object _,StackTrace __){});_tails[key]=tail;
    try{return await work;}finally{if(identical(_tails[key],tail))_tails.remove(key);}
  }
  static String _revision(){final r=Random.secure();return List.generate(16,(_)=>r.nextInt(256).toRadixString(16).padLeft(2,'0')).join();}
  Future<GroupDraft> _write(String owner,{required String title,required List<Map<String,dynamic>> people,required bool attempted})async{
    final value=GroupDraft.decode({'version':1,'title':title,'people':people,'attempted':attempted,'revision':_revision()});
    final raw=jsonEncode(value.toJson());if(raw.length>50000)throw const FormatException('Group draft exceeds its bound');await _storage.write(key:_key(owner),value:raw);
    if(await _storage.read(key:_key(owner))!=raw)throw StateError('Group draft save could not be verified');return value;
  }
  Future<GroupDraft> save(String owner,{required String title,required List<Map<String,dynamic>> people,String? expectedRevision})=>_serial(owner,()async{
    final existing=await read(owner);
    if(existing?.revision!=expectedRevision)throw StateError('The saved group changed. Reopen it before saving again.');
    if(existing?.attempted==true)throw StateError('This group may already exist. Check Chats before starting it again.');
    if(title.trim().isEmpty && people.isEmpty)throw ArgumentError('Add a group name or people before saving.');
    return _write(owner,title:title,people:people,attempted:false);
  });
  Future<GroupDraft> markAttempt(String owner,GroupDraft draft,{bool attempted=true})=>_serial(owner,()async{
    final existing=await read(owner);
    if(existing?.revision!=draft.revision)throw StateError('The saved group changed. Reopen it before creating a group.');
    return _write(owner,title:existing!.title,people:existing.people,attempted:attempted);
  });
  Future<void> remove(String owner,GroupDraft draft)=>_serial(owner,()async{
    final existing=await read(owner);if(existing==null)return;
    if(existing.revision!=draft.revision)throw StateError('The saved group changed. Reopen it before deleting it.');
    await _storage.delete(key:_key(owner));
    if(await _storage.read(key:_key(owner))!=null)throw StateError('Group draft deletion could not be verified');
  });
}

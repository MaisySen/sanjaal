import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'api.dart';

/// Private images use the same origin-checked, non-redirecting downloader as
/// chat audio. The cache key includes the opening member, never credentials.
class PrivateMediaImage extends ImageProvider<PrivateMediaImage> {
  PrivateMediaImage(this.session,this.url):account=session.user?['public_id'];
  final Session session;
  final String url;
  final Object? account;
  @override
  Future<PrivateMediaImage> obtainKey(ImageConfiguration configuration)=>SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(PrivateMediaImage key,ImageDecoderCallback decode)=>MultiFrameImageStreamCompleter(codec:_load(decode),scale:1);
  Future<ui.Codec> _load(ImageDecoderCallback decode)async{
    if(account==null || session.user?['public_id']!=account)throw ApiError('Please sign in again.',401);
    final bytes=await session.fetchBytes(url);
    if(session.user?['public_id']!=account)throw ApiError('Please sign in again.',401);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
  @override
  bool operator==(Object other)=>other is PrivateMediaImage && identical(other.session,session) && other.account==account && other.url==url;
  @override
  int get hashCode=>Object.hash(identityHashCode(session),account,url);
}

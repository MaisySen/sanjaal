import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'api.dart';
import 'package:material_ui/material_ui.dart';
import 'photo_gallery.dart';
import 'session_bound_state.dart';

/// Private images use the same origin-checked, non-redirecting downloader as
/// chat audio. The cache key includes the opening member, never credentials.
class PrivateMediaImage extends ImageProvider<PrivateMediaImage> {
  PrivateMediaImage(this.session,this.url):account=session.user?['public_id'],generation=session.generation;
  final Session session;
  final String url;
  final Object? account;
  final int generation;
  bool get active=>account!=null && session.user?['public_id']==account && session.generation==generation;
  @override
  Future<PrivateMediaImage> obtainKey(ImageConfiguration configuration)=>active?SynchronousFuture(this):Future.error(ApiError('Please sign in again.',401));
  @override
  ImageStreamCompleter loadImage(PrivateMediaImage key,ImageDecoderCallback decode)=>MultiFrameImageStreamCompleter(codec:_load(decode),scale:1);
  Future<ui.Codec> _load(ImageDecoderCallback decode)async{
    if(!active)throw ApiError('Please sign in again.',401);
    final bytes=await session.fetchBytes(url);
    if(!active)throw ApiError('Please sign in again.',401);
    final buffer=await ui.ImmutableBuffer.fromUint8List(bytes);
    if(!active){buffer.dispose();throw ApiError('Please sign in again.',401);}
    final codec=await decode(buffer);
    if(!active){codec.dispose();throw ApiError('Please sign in again.',401);}
    return codec;
  }
  @override
  bool operator==(Object other)=>other is PrivateMediaImage && identical(other.session,session) && other.account==account && other.generation==generation && other.url==url;
  @override
  int get hashCode=>Object.hash(identityHashCode(session),account,generation,url);
}

/// Unlike public feed photos, private chat photos belong to the opening login.
/// Keep this boundary on the pushed route, not only on the chat underneath it.
class PrivatePhotoViewer extends StatefulWidget {
  const PrivatePhotoViewer({super.key,required this.session,required this.urls});
  final Session session;
  final List<String> urls;
  @override
  State<PrivatePhotoViewer> createState()=>_PrivatePhotoViewerState();
}
class _PrivatePhotoViewerState extends State<PrivatePhotoViewer> with SessionBoundState<PrivatePhotoViewer>{
  @override Session get viewSession=>widget.session;
  @override Widget build(BuildContext context)=>!sessionActive?retiredSessionView():PhotoViewer(urls:widget.urls,provider:(url)=>PrivateMediaImage(widget.session,url));
}

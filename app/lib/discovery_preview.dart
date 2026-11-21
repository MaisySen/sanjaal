/// A preview reference, not proof of decode, public audience or eligibility.
/// The eventual server must authorize discovery separately and reject private
/// media at the byte route. This parser never fetches bytes or plays a video.
class DiscoveryPreview {
  const DiscoveryPreview({required this.url, required this.video});
  final Uri url;
  final bool video;

  static DiscoveryPreview? fromPost(
    Map<String, dynamic> post, {
    required Uri apiBase,
  }) {
    if (post['kind'] != 'post' && post['kind'] != 'reel') return null;
    final media = post['media'];
    if (media is! List) return null;
    for (final video in [false, true]) {
      for (final entry in media) {
        if (entry is! Map || entry['type'] != (video ? 'video' : 'image')) {
          continue;
        }
        final value = entry[video ? 'thumbnail_url' : 'url'];
        if (value is! String) continue;
        final uri = Uri.tryParse(value);
        final prefix =
            '${apiBase.path.replaceFirst(RegExp(r'/+$'), '')}/media/';
        if (uri == null ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.scheme != apiBase.scheme ||
            uri.host != apiBase.host ||
            uri.port != apiBase.port ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            !uri.path.startsWith(prefix)) {
          continue;
        }
        final id = uri.path.substring(prefix.length);
        if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
          continue;
        }
        return DiscoveryPreview(url: uri, video: video);
      }
    }
    return null;
  }
}

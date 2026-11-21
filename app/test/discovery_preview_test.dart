import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/discovery_preview.dart';

final base = Uri.parse('https://fixture.invalid/api/v1');
const media =
    'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001';
DiscoveryPreview? preview(List<dynamic> items, {String kind = 'post'}) =>
    DiscoveryPreview.fromPost({'kind': kind, 'media': items}, apiBase: base);
void main() {
  test('valid image and actual video poster remain distinct', () {
    expect(
      preview([
        {'type': 'image', 'url': media},
      ])?.video,
      isFalse,
    );
    expect(
      preview([
        {
          'type': 'video',
          'url': 'https://fixture.invalid/clip.mp4',
          'thumbnail_url': media,
        },
      ], kind: 'reel')?.video,
      isTrue,
    );
  });
  test('never treats the video source or an author avatar as its poster', () {
    expect(
      preview([
        {'type': 'video', 'url': media},
      ]),
      isNull,
    );
    expect(
      DiscoveryPreview.fromPost({
        'kind': 'reel',
        'author': {'avatar_url': media},
        'media': [
          {'type': 'video', 'url': media},
        ],
      }, apiBase: base),
      isNull,
    );
  });
  test('story/chat kinds never become tiles through a shared media field', () {
    for (final kind in ['story', 'chat', 'unknown']) {
      expect(
        preview([
          {'type': 'image', 'url': media},
        ], kind: kind),
        isNull,
      );
    }
  });
  test('requires same API origin and exact public-media reference route', () {
    for (final url in [
      'https://other.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
      'http://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
      'https://fixture.invalid:444/api/v1/media/00000000-0000-4000-8000-000000000001',
      'https://user@fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
      'https://fixture.invalid/api/v1/stories/private/media',
      '$media?token=private',
      '$media#fragment',
      'data:image/png,hello',
      'file:///private.png',
      'https://fixture.invalid/api/v1/media/not-a-uuid',
    ]) {
      expect(
        preview([
          {'type': 'image', 'url': url},
        ]),
        isNull,
        reason: url,
      );
    }
  });
  test(
    'malformed entries fail safely and a later valid image can supply preview',
    () {
      expect(
        preview([
          null,
          2,
          {},
          {'type': 'image', 'url': 12},
        ]),
        isNull,
      );
      expect(
        preview([
          {'type': 'image', 'url': 'broken'},
          {'type': 'image', 'url': media},
        ])?.url.toString(),
        media,
      );
    },
  );
}

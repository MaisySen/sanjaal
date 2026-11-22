import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/discovery_contract.dart';

final base = Uri.parse('https://fixture.invalid/api/v1');
Map<String, dynamic> row({Map<String, dynamic>? facts}) => {
  'public_id': 'post-1',
  'kind': 'post',
  'body': 'A real caption',
  'media': [
    {
      'type': 'image',
      'url': 'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
    },
  ],
  'discovery':
      facts ??
      {
        'author_opted_in': true,
        'moderation': 'approved',
        'public_post': true,
        'private_bytes': false,
        'blocked_either_way': false,
        'deleted': false,
      },
};
Map<String, dynamic> envelope(List<dynamic> rows) => {
  'contract': 'discovery_v1',
  'version': 'v1',
  'data': rows,
  'next_cursor': null,
};
void main() {
  test('proposed eligible tile parses without manufacturing facts', () {
    final page = parseDiscoveryPage(
      envelope([row()]),
      apiBase: base,
      maxPageSize: 15,
    );
    expect(page.items.single.id, 'post-1');
    expect(page.items.single.caption, 'A real caption');
    expect(page.items.single.preview.video, isFalse);
  });
  test(
    'missing eligibility and unknown moderation cannot default to eligible',
    () {
      for (final facts in [
        {},
        {'author_opted_in': true},
        {
          ...row()['discovery'] as Map<String, dynamic>,
          'moderation': 'unknown',
        },
      ]) {
        expect(
          parseDiscoveryPage(
            envelope([row(facts: Map<String, dynamic>.from(facts))]),
            apiBase: base,
            maxPageSize: 15,
          ).items,
          isEmpty,
        );
      }
    },
  );
  test(
    'ineligible page preserves cursor for bounded next-page progression',
    () {
      final body = envelope([row(facts: {})])..['next_cursor'] = 'more';
      final p = parseDiscoveryPage(body, apiBase: base, maxPageSize: 15);
      expect(p.items, isEmpty);
      expect(p.nextCursor, 'more');
    },
  );
  test(
    'malformed identities reject whole page rather than partial replacement',
    () {
      expect(
        () => parseDiscoveryPage(
          envelope([
            row(),
            {'public_id': null},
          ]),
          apiBase: base,
          maxPageSize: 15,
        ),
        throwsFormatException,
      );
    },
  );
  test('absent marker, oversized page and invalid cursor reject', () {
    for (final body in [
      envelope([row()])..remove('contract'),
      envelope(List.generate(16, (_) => row())),
      envelope([])..['next_cursor'] = 12,
    ]) {
      expect(
        () => parseDiscoveryPage(body, apiBase: base, maxPageSize: 15),
        throwsFormatException,
      );
    }
  });
  test('private bytes, blocked and unapproved author always disappear', () {
    for (final patch in [
      {'private_bytes': true},
      {'blocked_either_way': true},
      {'author_opted_in': false},
      {'deleted': true},
    ]) {
      final facts = {...row()['discovery'] as Map<String, dynamic>, ...patch};
      expect(
        parseDiscoveryPage(
          envelope([row(facts: facts)]),
          apiBase: base,
          maxPageSize: 15,
        ).items,
        isEmpty,
      );
    }
  });
}

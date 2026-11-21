import 'discovery_eligibility.dart';
import 'discovery_paging.dart';
import 'discovery_preview.dart';

/// Candidate Discovery wire contract v1, connected only through the default-off
/// capability gate. No live service is asserted. Server facts must be authorized
/// server-side. Client parsing is defense in depth, never access control.
class DiscoveryTile {
  const DiscoveryTile({
    required this.id,
    required this.caption,
    required this.preview,
  });
  final String id, caption;
  final DiscoveryPreview preview;
}

DiscoveryPageData<DiscoveryTile> parseDiscoveryPage(
  Object? payload, {
  required Uri apiBase,
  required int maxPageSize,
}) {
  if (maxPageSize < 1 ||
      payload is! Map ||
      payload['contract'] != 'discovery_v1') {
    throw const FormatException('Unsupported Discovery contract');
  }
  final rows = payload['data'],
      version = payload['version'],
      cursor = payload['next_cursor'];
  if (rows is! List ||
      rows.length > maxPageSize ||
      version is! String ||
      version.trim().isEmpty ||
      version.length > 128 ||
      (cursor != null &&
          (cursor is! String || cursor.isEmpty || cursor.length > 2048))) {
    throw const FormatException('Invalid Discovery envelope');
  }
  final tiles = <DiscoveryTile>[];
  for (final row in rows) {
    if (row is! Map ||
        row['public_id'] is! String ||
        (row['public_id'] as String).trim().isEmpty ||
        (row['public_id'] as String).length > 128 ||
        (row['body'] != null && row['body'] is! String)) {
      throw const FormatException('Invalid Discovery identity');
    }
    final post = Map<String, dynamic>.from(row);
    final facts = row['discovery'];
    if (facts is! Map) continue;
    final preview = DiscoveryPreview.fromPost(post, apiBase: apiBase);
    bool? fact(String key) => facts[key] is bool ? facts[key] as bool : null;
    final moderation = switch (facts['moderation']) {
      'approved' => DiscoveryModeration.approved,
      'pending' => DiscoveryModeration.pending,
      'rejected' => DiscoveryModeration.rejected,
      _ => null,
    };
    final eligibility = DiscoveryEligibility(
      kind: post['kind']?.toString() ?? '',
      authorOptedIn: fact('author_opted_in'),
      moderation: moderation,
      publicPost: fact('public_post'),
      privateBytes: fact('private_bytes'),
      blockedEitherWay: fact('blocked_either_way'),
      deleted: fact('deleted'),
      hasPreview: preview != null,
    );
    if (!eligibility.canRecommend) continue;
    tiles.add(
      DiscoveryTile(
        id: row['public_id'],
        caption: (row['body'] as String?) ?? '',
        preview: preview!,
      ),
    );
  }
  return DiscoveryPageData(
    items: tiles,
    nextCursor: cursor as String?,
    version: version,
  );
}

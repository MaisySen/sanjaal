import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'discovery_contract.dart';
import 'discovery_route.dart';
import 'search_page.dart';

/// Compatibility entry. Only the explicit coordinated v1 capability opts into
/// the proposed service. Absent/older servers keep existing people/tag search.
/// The candidate server config remains hard false until approved activation.
Widget discoveryEntry(Session session) {
  if (!session.discoveryEnabled) return SearchPage(session: session);
  return DiscoveryRoute(
    session: session,
    sourceAvailable: () => session.discoveryEnabled,
    allowReelsFilter: true,
    read: (query, cursor) async {
      if (!session.discoveryEnabled) {
        throw StateError('Discovery is no longer available for this session.');
      }
      final parameters = Map<String, String>.of(query);
      if (cursor != null) {
        parameters['cursor'] = cursor;
      }
      final result = await session.call('GET', '/discovery', query: parameters);
      return parseDiscoveryPage(
        result,
        apiBase: Uri.parse(apiBase),
        maxPageSize: 15,
      );
    },
  );
}

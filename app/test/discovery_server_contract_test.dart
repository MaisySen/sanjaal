// Reads a local response produced by the actual isolated Laravel HTTP route.
// Opt-in runner input avoids checking synthetic inventory into app assets.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/discovery_contract.dart';

void main() {
  final path = Platform.environment['DISCOVERY_CONTRACT_CAPTURE'];
  test(
    'actual isolated Laravel response satisfies Dart Discovery contract',
    () {
      final response = jsonDecode(File(path!).readAsStringSync());
      final page = parseDiscoveryPage(
        response,
        apiBase: Uri.parse('http://localhost/api/v1'),
        maxPageSize: 15,
      );
      expect(page.version, 'eligible-recent-v1');
      expect(page.items.length, 2);
      expect(page.items.where((tile) => tile.preview.video).length, 1);
      expect(
        page.items.every(
          (tile) => tile.id.isNotEmpty && tile.caption == 'Local fixture',
        ),
        isTrue,
      );
    },
    skip: path == null ? 'Run isolated Laravel contract capture first.' : false,
  );
}

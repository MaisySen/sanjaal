// Compile guard only. This does not run an iOS application or any native journey.
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/ios_flows_test.dart' as native;

void main() {
  test(
    'native flow library compiles without executing its simulator journey',
    () {
      expect(native.main, isA<Function>());
    },
  );
}

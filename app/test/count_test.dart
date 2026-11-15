import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/profile_pages.dart' show shortCount;

void main() {
  test('short counts', () {
    expect(shortCount(0), '0');
    expect(shortCount(999), '999');
    expect(shortCount(1000), '1K');
    expect(shortCount(1240), '1.2K');
    expect(shortCount(1999), '1.9K');
    expect(shortCount(2500000), '2.5M');
  });
}

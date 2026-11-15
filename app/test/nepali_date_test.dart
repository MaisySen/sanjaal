import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/nepali_date.dart';

void main() {
  // (BS year, month, day, AD yyyy-mm-dd) from Nepal embassy public-holiday lists for 2083 BS (Cairo, Canberra, Washington).
  // Canberra's "29 Asoj = 5 Oct 2026" is left out: it contradicts the Cairo list (20 Ashoj = 6 Oct) and the month table.
  const pairs = <(int, int, int, String)>[
    (2083, 1, 1, '2026-04-14'), (2083, 1, 14, '2026-04-27'), (2083, 1, 18, '2026-05-01'), (2083, 2, 12, '2026-05-26'),
    (2083, 2, 15, '2026-05-29'), (2083, 2, 18, '2026-06-01'), (2083, 2, 25, '2026-06-08'), (2083, 3, 3, '2026-06-17'),
    (2083, 3, 16, '2026-06-30'), (2083, 4, 7, '2026-07-23'), (2083, 5, 10, '2026-08-26'), (2083, 6, 20, '2026-10-06'),
    (2083, 6, 25, '2026-10-11'), (2083, 7, 3, '2026-10-20'), (2083, 7, 4, '2026-10-21'), (2083, 7, 22, '2026-11-08'),
    (2083, 7, 24, '2026-11-10'), (2083, 7, 25, '2026-11-11'), (2083, 7, 29, '2026-11-15'), (2083, 9, 10, '2026-12-25'),
    (2083, 9, 13, '2026-12-28'), (2083, 9, 17, '2027-01-01'), (2083, 10, 12, '2027-01-26'), (2083, 11, 7, '2027-02-19'),
    (2083, 11, 24, '2027-03-08'), (2083, 11, 26, '2027-03-10'), (2083, 12, 7, '2027-03-21'), (2083, 12, 8, '2027-03-22'),
    (2083, 12, 12, '2027-03-26'), (2083, 12, 15, '2027-03-29'),
  ];

  test('matches published embassy date pairs both ways', () {
    for (final p in pairs) {
      final ad = bsToAd(p.$1, p.$2, p.$3)!;
      expect(ad.toIso8601String().substring(0, 10), p.$4, reason: '${p.$1}-${p.$2}-${p.$3}');
      expect(adToBs(ad), BsDate(p.$1, p.$2, p.$3), reason: p.$4);
    }
  });

  test('every day in range round trips and days are consecutive', () {
    var ad = bsToAd(2000, 1, 1)!;
    for (var y = 2000; y <= 2099; y++) {
      for (var m = 1; m <= 12; m++) {
        for (var d = 1; d <= daysInBsMonth(y, m); d++) {
          expect(bsToAd(y, m, d), ad);
          expect(adToBs(ad), BsDate(y, m, d));
          ad = ad.add(const Duration(days: 1));
        }
      }
    }
  });

  test('out of range and impossible days give null', () {
    expect(adToBs(DateTime.utc(1900, 1, 1)), isNull);
    expect(adToBs(DateTime.utc(2100, 1, 1)), isNull);
    expect(bsToAd(2083, 13, 1), isNull);
    expect(bsToAd(2083, 2, 40), isNull);
  });

  test('nepali digits', () {
    expect(nepaliDigits('2083'), '२०८३');
  });
}

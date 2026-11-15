import 'package:material_ui/material_ui.dart';
import 'nepali_date.dart';

/// Named public days for 2083 BS. Dates come from the Nepal embassy public-holiday lists (Washington, Canberra,
/// Cairo). Lunar festival dates change every year, so only 2083 is listed. Nothing here is guessed.
const _named2083 = <(int, int, String, String?)>[
  (1, 1, 'Nepali New Year', null),
  (1, 18, 'Buddha Jayanti', null),
  (2, 15, 'Republic Day', null),
  (11, 7, 'Democracy Day', null),
  (12, 8, 'Fagu Purnima (Holi)', 'Embassy lists differ by one day (7 or 8 Chaitra). Check the local notice.'),
];

/// Bikram Sambat calendar: today's date and a month grid with the named days for 2083.
class NepaliCalendarPage extends StatefulWidget {
  const NepaliCalendarPage({super.key});

  @override
  State<NepaliCalendarPage> createState() => _NepaliCalendarPageState();
}

class _NepaliCalendarPageState extends State<NepaliCalendarPage> {
  final BsDate? today = adToBs(DateTime.now());
  late int year = today?.year ?? 2083;
  late int month = today?.month ?? 1;

  void _step(int by) {
    var m = month + by;
    var y = year;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    if (y < 2000 || y > 2099) return;
    setState(() {
      year = y;
      month = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final first = bsToAd(year, month, 1)!;
    final offset = first.weekday % 7; // Sunday first
    final days = daysInBsMonth(year, month);
    final named = year == 2083 ? _named2083.where((n) => n.$1 == month).toList() : const <(int, int, String, String?)>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Nepali calendar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (today != null) ...[
          Text('Today', style: t.labelLarge),
          Text(today!.nepali, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('${weekdaysNepali[now.weekday - 1]} . ${today!.roman}', style: t.bodyMedium),
          const SizedBox(height: 16),
        ],
        Row(children: [
          IconButton(tooltip: 'Previous month', onPressed: () => _step(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${monthsNepali[month - 1]} ${nepaliDigits('$year')}  (${monthsRoman[month - 1]} $year)', textAlign: TextAlign.center, style: t.titleMedium)),
          IconButton(tooltip: 'Next month', onPressed: () => _step(1), icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final d in const ['आइत', 'सोम', 'मंगल', 'बुध', 'बिही', 'शुक्र', 'शनि'])
            Expanded(child: Center(child: Text(d, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < offset; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++) _cell(context, d, isToday: today != null && today!.year == year && today!.month == month && today!.day == d, marked: named.any((n) => n.$2 == d)),
          ],
        ),
        const SizedBox(height: 8),
        if (named.isNotEmpty)
          for (final n in named)
            ListTile(
              leading: const Icon(Icons.celebration_outlined),
              title: Text(n.$3),
              subtitle: Text('${nepaliDigits('${n.$2}')} ${monthsNepali[month - 1]} . ${bsToAd(year, month, n.$2)!.toIso8601String().substring(0, 10)}${n.$4 == null ? '' : '\n${n.$4}'}'),
            )
        else
          Text(year == 2083 ? 'No named public days listed this month.' : 'Named days are listed for 2083 BS only. Festival dates that follow the moon change every year.', style: t.bodySmall),
        const SizedBox(height: 16),
        Text('Dates follow published Nepal embassy holiday lists. Always check the official notice for the day.', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _cell(BuildContext context, int d, {required bool isToday, required bool marked}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isToday ? scheme.primary : (marked ? scheme.primaryContainer : null),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          nepaliDigits('$d'),
          style: TextStyle(fontWeight: isToday || marked ? FontWeight.w800 : FontWeight.w500, color: isToday ? scheme.onPrimary : (marked ? scheme.onPrimaryContainer : null)),
        ),
      ),
    );
  }
}

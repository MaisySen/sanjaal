import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'ui.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final pager = PageController();
  int page = 0;

  static const _slides = [
    (Icons.dynamic_feed, 'Share with your community', 'Post photos and thoughts, follow people, and see what Nepalis near and far are sharing.'),
    (Icons.movie_filter, 'Watch and make reels', 'Swipe through short videos or upload your own. Like, comment and follow.'),
    (Icons.forum, 'Chat and call', 'Message friends, make groups, and start a voice or video call from any chat.'),
    (Icons.account_balance_wallet, 'Coins you can send', 'Send coins to friends as gifts. Every balance change is recorded in your history.'),
  ];

  @override
  Widget build(BuildContext context) {
    final last = page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: prefs.finishOnboarding, child: Text(t_('Skip'))),
          ),
          Expanded(
            child: PageView(
              controller: pager,
              onPageChanged: (i) => setState(() => page = i),
              children: [
                for (var n = 0; n < _slides.length; n++)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 5,
                      child: SizedBox(width: double.infinity, child: CustomPaint(painter: _RidgePainter(seed: n, ink: Theme.of(context).colorScheme.onSurface, accent: brandRed, paper: Theme.of(context).colorScheme.surface))),
                    ),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t_(_slides[n].$2), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
                          const SizedBox(height: 12),
                          Text(t_(_slides[n].$3), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
                        ]),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == page ? brandRed : Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => last ? prefs.finishOnboarding() : pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(last ? t_('Get started') : t_('Next')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Original line art: layered mountain ridges under a sun disc. Each slide gets its own ridge
/// shape from its seed. Drawn in code, no image files.
class _RidgePainter extends CustomPainter {
  _RidgePainter({required this.seed, required this.ink, required this.accent, required this.paper});
  final int seed;
  final Color ink;
  final Color accent;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sun = Offset(w * (0.28 + 0.14 * seed), h * 0.30);
    canvas.drawCircle(sun, h * 0.11, Paint()..color = accent);
    for (var layer = 0; layer < 4; layer++) {
      final base = h * (0.52 + layer * 0.14);
      final amp = h * (0.20 - layer * 0.03);
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 4) {
        final t = x / w;
        final y = base - amp * (0.5 + 0.5 * math.sin(t * (5 + layer * 1.3) + seed * 1.9 + layer)) - amp * 0.35 * math.sin(t * (13 + layer * 3) + seed + layer * 2.1).abs();
        path.lineTo(x, y);
      }
      path.lineTo(w, h);
      path.close();
      final alpha = 0.10 + layer * 0.22;
      canvas.drawPath(path, Paint()..color = Color.alphaBlend(ink.withValues(alpha: alpha), paper));
    }
  }

  @override
  bool shouldRepaint(_RidgePainter old) => old.seed != seed || old.ink != ink || old.paper != paper;
}

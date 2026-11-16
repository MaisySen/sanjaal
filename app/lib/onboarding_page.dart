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
    (Icons.account_balance_wallet, 'Coins you can send', 'Top up with eSewa and send coins to friends. Every balance change is recorded.'),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('0${n + 1}', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w300, color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 8),
                      Container(width: 40, height: 3, color: brandRed),
                      const SizedBox(height: 24),
                      Icon(_slides[n].$1, size: 28, color: Theme.of(context).colorScheme.onSurface),
                      const SizedBox(height: 16),
                      Text(t_(_slides[n].$2), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
                      const SizedBox(height: 12),
                      Text(t_(_slides[n].$3), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
                    ]),
                  ),
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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'glass/glass_button.dart';
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
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => page = i);
              },
              children: [
                for (final s in _slides)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: brandRed),
                        child: Icon(s.$1, size: 64, color: Colors.white),
                      ),
                      const SizedBox(height: 36),
                      Text(s.$2, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(s.$3, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
              child: GlassButton(
                label: last ? t_('Get started') : t_('Next'),
                onPressed: () => last ? prefs.finishOnboarding() : pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

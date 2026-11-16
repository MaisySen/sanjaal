import 'package:material_ui/material_ui.dart';
import 'ph.dart';
import 'ui.dart';

/// One optional introduction, then the real task. Feature help belongs beside
/// the task that needs it, not in a sequence of pages a new member must recall.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, this.onContinue});
  final ValueChanged<bool>? onContinue;

  void _continue(bool createAccount) {
    if (onContinue != null) {
      onContinue!(createAccount);
    } else {
      prefs.finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, bounds) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: bounds.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: Logo(size: 60)))),
                  const SizedBox(width: 16),
                  TextButton(onPressed: () => _continue(false), child: Text(t_('Sign in'))),
                ]),
                const SizedBox(height: 64),
                Align(alignment: Alignment.centerLeft, child: Container(width: 32, height: 4, color: brandRed)),
                const SizedBox(height: 24),
                Text(t_('Your people.\nYour stories.'), style: theme.textTheme.displaySmall?.copyWith(fontSize: 42, height: 1.08, fontWeight: FontWeight.w700, letterSpacing: -1.2)),
                const SizedBox(height: 20),
                Text(t_('A place for Nepalis, wherever you are.'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: colors.onSurfaceVariant)),
                const SizedBox(height: 40),
                _WelcomeRow(icon: 'image', title: t_('Share a moment'), detail: t_('Photos, thoughts and short videos.')),
                const SizedBox(height: 24),
                _WelcomeRow(icon: 'chat-circle', title: t_('Keep the conversation going'), detail: t_('Find your people and stay in touch.')),
                const SizedBox(height: 48),
                FilledButton(onPressed: () => _continue(true), child: Text(t_('Create an account'))),
                const SizedBox(height: 10),
                Text(t_('Your community starts with you.'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ]),
            ),
          ),
        )),
      ),
    );
  }
}

class _WelcomeRow extends StatelessWidget {
  const _WelcomeRow({required this.icon, required this.title, required this.detail});
  final String icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 3), child: PhIcon(icon, size: 24)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(detail, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45, color: theme.colorScheme.onSurfaceVariant)),
      ])),
    ]);
  }
}

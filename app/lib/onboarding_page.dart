import 'glass/glass_action.dart';
import 'package:material_ui/material_ui.dart';
import 'ui.dart';
import 'ph.dart';
import 'language_settings_page.dart';
import 'about_page.dart';

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
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, bounds) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: bounds.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(alignment:WrapAlignment.spaceBetween, crossAxisAlignment:WrapCrossAlignment.center, children:[
                  TextButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const LanguageSettingsPage())),icon:const PhIcon('translate',size:20),label:Text(t_('Language'))),
                  TextButton(onPressed: () => _continue(false), child: Text(t_('Sign in'))),
                ]),
                SizedBox(height: largeText ? 12 : 64),
                Center(child: Container(width: largeText ? 72 : 140, height: largeText ? 72 : 140,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: brandRed),
                  child: Center(child: PhIcon('newspaper', size: largeText ? 36 : 64, color: Colors.white)))),
                SizedBox(height: largeText ? 20 : 36),
                Text(t_('Share with your community'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontSize: largeText ? 22 : 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(t_('A place for Nepalis, wherever you are.'), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4, color: colors.onSurfaceVariant)),
                const SizedBox(height: 24),
                GlassAction(onPressed: () => _continue(true), label: t_('Create an account')),
                const SizedBox(height: 12),
                Text(t_('Your community starts with you.'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height:12),
                TextButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const AboutPage())),child:Text(t_('About, privacy and terms'),textAlign:TextAlign.center)),
              ]),
            ),
          ),
        )),
      ),
    );
  }
}

import 'ph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const brandRed = Color(0xFFC8102E);
const brandBlue = Color(0xFF003893);

String ago(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return t_('now');
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${t.day}/${t.month}/${t.year}';
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e.toString())));
}

/// Runs a photo or video pick. Cancelling returns null. A refused camera or photo permission, or a picker that fails,
/// shows a plain message and returns null instead of throwing.
Future<T?> guardPick<T>(BuildContext context, Future<T?> Function() pick) async {
  try {
    return await pick();
  } on PlatformException catch (e) {
    final c = e.code.toLowerCase();
    if (context.mounted) {
      showInfo(
        context,
        c.contains('camera_access') ? t_('Camera access is off. Turn it on in Settings to take photos or videos.')
            : c.contains('photo_access') ? t_('Photo access is off. Turn it on in Settings to choose photos or videos.')
            : t_('Could not open the camera or photos. Try again.'),
      );
    }
    return null;
  }
}

void showInfo(BuildContext context, String m) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

/// App wide settings: theme and language. Saved on the device.
class AppPrefs extends ChangeNotifier {
  ThemeMode mode = ThemeMode.dark;
  String lang = 'en';
  bool seenOnboarding = true;
  bool ready = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = switch (p.getString('theme')) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    lang = p.getString('lang') ?? 'en';
    seenOnboarding = p.getBool('onboarded') ?? false;
    ready = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', m == ThemeMode.dark ? 'dark' : m == ThemeMode.light ? 'light' : 'system');
  }

  Future<void> setLang(String l) async {
    lang = l;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
  }

  Future<void> finishOnboarding() async {
    seenOnboarding = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
  }
}

final prefs = AppPrefs();

const _ne = <String, String>{
  'Your people.\nYour stories.': 'आफ्ना मान्छे।\nआफ्ना कथा।',
  'A place for Nepalis, wherever you are.': 'जहाँ भए पनि, नेपालीका लागि आफ्नै ठाउँ।',
  'Share a moment': 'पल बाँड्नुहोस्',
  'Photos, thoughts and short videos.': 'फोटो, विचार र छोटा भिडियो।',
  'Keep the conversation going': 'कुराकानी जारी राख्नुहोस्',
  'Find your people and stay in touch.': 'आफ्ना मान्छे भेट्नुहोस् र सम्पर्कमा रहनुहोस्।',
  'Your community starts with you.': 'तपाईंबाटै सुरु हुन्छ समुदाय।',
  'Make yourself at home': 'आफ्नै ठाउँ सम्झनुहोस्',
  'Welcome back': 'फेरि स्वागत छ',
  'Create your place in the community.': 'समुदायमा आफ्नो ठाउँ बनाउनुहोस्।',
  'Sign in to pick up where you left off.': 'फेरि जोडिन साइन इन गर्नुहोस्।',
  'Share something that matters to you.': 'आफूलाई अर्थपूर्ण लागेको कुरा बाँड्नुहोस्।',
  'Create an account': 'खाता बनाउनुहोस्',
  'I already have an account': 'मेरो खाता छ',
  'Create a post': 'पोस्ट बनाउनुहोस्',
  'Posts from the people you follow will appear here.': 'तपाईंले फलो गरेका मान्छेका पोस्ट यहाँ देखिन्छन्।',
  'Find people': 'मान्छे खोज्नुहोस्',
  'A photo, a thought, a little of your day.': 'एउटा फोटो, एउटा विचार, तपाईंको दिनको सानो अंश।',
  'Home': 'गृह',
  'Reels': 'रिल्स',
  'Chats': 'च्याट',
  'Wallet': 'वालेट',
  'Me': 'म',
  'For you': 'तपाईंका लागि',
  'Following': 'फलोइङ',
  'Search': 'खोज्नुहोस्',
  'Notifications': 'सूचना',
  'Settings': 'सेटिङ',
  'Sign out': 'साइन आउट',
  'Sign in': 'साइन इन',
  'Create account': 'खाता बनाउनुहोस्',
  'Post': 'पोस्ट',
  'Comments': 'कमेन्ट',
  'Reply': 'जवाफ',
  'Delete': 'मेटाउनुहोस्',
  'Cancel': 'रद्द',
  'Save': 'सुरक्षित',
  'Follow': 'फलो',
  'Unfollow': 'अनफलो',
  'Message': 'सन्देश',
  'Edit profile': 'प्रोफाइल सम्पादन',
  'Posts': 'पोस्ट',
  'Followers': 'फलोअर',
  'Language': 'भाषा',
  'Theme': 'थिम',
  'Dark': 'ब्ल्याक',
  'Light': 'उज्यालो',
  'System': 'सिस्टम',
  'Report': 'रिपोर्ट',
  'Block': 'ब्लक',
  'Welcome to Sanjaal': 'सञ्जालमा स्वागत छ',
  'Get started': 'सुरु गरौं',
  'Next': 'अर्को',
  'Skip': 'छोड्नुहोस्',
  'now': 'अहिले',
  'Your Nepali community': 'तपाईंको नेपाली समुदाय',
  'Blocked people': 'ब्लक गरिएका',
  'About, privacy and terms': 'हाम्रोबारे, गोपनीयता र सर्त',
  'Coin wallet': 'सिक्का वालेट',
  'New chat': 'नयाँ च्याट',
  'Add coins': 'सिक्का थप्नुहोस्',
  'Balance': 'मौज्दात',
  'Calls': 'कल',
  'Gift': 'उपहार',
  'Go live': 'लाइभ जानुहोस्',
  'Let speak': 'बोल्न दिनुहोस्',
  'Live rooms': 'लाइभ कोठा',
  'Move to listeners': 'श्रोतामा सार्नुहोस्',
  'End': 'अन्त्य',
  'Dismiss': 'हटाउनुहोस्',
  'Back': 'पछाडि',
  'Copy': 'कपी',
  'Try again': 'फेरि प्रयास गर्नुहोस्',
  'Refresh': 'रिफ्रेस',
  'Send': 'पठाउनुहोस्',
  'Send coins': 'सिक्का पठाउनुहोस्',
  'Start': 'सुरु',
  'Unblock': 'अनब्लक',
  'New post': 'नयाँ पोस्ट',
  'Contact us': 'सम्पर्क गर्नुहोस्',
  'About Sanjaal': 'सञ्जालको बारेमा',
};

/// Translates a UI string into the chosen language. Falls back to English.
String t_(String en) => prefs.lang == 'ne' ? (_ne[en] ?? en) : en;

const _tones = [Color(0xFF24405F), Color(0xFF6B3A2E), Color(0xFF3F5B45), Color(0xFF5A3E6B), Color(0xFF7A5A1E), Color(0xFF2F5961)];

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.user, this.radius = 20});
  final Map<String, dynamic>? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = user?['avatar_url'] as String?;
    final name = (user?['username'] ?? user?['name'] ?? '?').toString();
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: _tones[name.hashCode.abs() % _tones.length],
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(letter, style: TextStyle(fontSize: radius * 0.9, color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action});
  final PhData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PhIcon(icon, size: 30, color: s.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: s.textTheme.titleMedium?.copyWith(fontSize: 16)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: s.textTheme.bodyMedium?.copyWith(color: s.colorScheme.outline)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) {
    // Draft identity: the Devanagari wordmark alone. No logo mark is approved yet.
    return Text('सञ्जाल', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Theme.of(context).colorScheme.onSurface));
  }
}

/// Opens a picture full screen with pinch zoom.
void openImage(BuildContext context, String url, {Map<String, String>? headers}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(child: InteractiveViewer(child: Image.network(url, headers: headers, fit: BoxFit.contain))),
    ),
  ));
}

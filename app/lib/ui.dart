import 'ph.dart';
import 'photo_gallery.dart';
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
  'Earlier messages could not be loaded.': 'अघिल्ला सन्देशहरू लोड हुन सकेनन्।',
  'Load earlier messages': 'अघिल्ला सन्देशहरू हेर्नुहोस्',
  'Start of conversation': 'कुराकानीको सुरुवात',
  'New messages': 'नयाँ सन्देशहरू',
  'Messages could not be loaded.': 'सन्देशहरू लोड हुन सकेनन्।',
  'Delivery could not be confirmed.': 'सन्देश पुगेको पुष्टि हुन सकेन।',
  'Delivery unconfirmed. Tap to retry.': 'सन्देश पुगेको पुष्टि भएन। फेरि प्रयास गर्न थिच्नुहोस्।',
  'Original message unavailable.': 'पहिलेको सन्देश उपलब्ध छैन।',
  'Your profile is still updating.': 'तपाईंको प्रोफाइल अद्यावधिक हुँदैछ।',
  'Photo saved. Text changes still need Save.': 'फोटो सुरक्षित भयो। लेखेका परिवर्तन सुरक्षित गर्न सेभ थिच्नुहोस्।',
  'Refresh profile': 'प्रोफाइल पुनः लोड गर्नुहोस्',
  'Profile could not be loaded.': 'प्रोफाइल लोड हुन सकेन।',
  'That member does not exist.': 'त्यो सदस्य भेटिएन।',
  'Name': 'नाम',
  'Username': 'प्रयोगकर्ता नाम',
  'Bio': 'परिचय',
  'Required': 'आवश्यक छ',
  'Change photo': 'फोटो बदल्नुहोस्',
  'Use 3 to 30 letters, numbers, dots or underscores': '३ देखि ३० अक्षर, अंक, डट वा अन्डरस्कोर प्रयोग गर्नुहोस्',

  'Comment posted.': 'टिप्पणी पोस्ट भयो।',
  'Original comment removed. Choose another reply or cancel.': 'पहिलेको टिप्पणी हटाइएको छ। अर्को टिप्पणी छान्नुहोस् वा जवाफ रद्द गर्नुहोस्।',
  'Your comment is still updating.': 'तपाईंको टिप्पणी अद्यावधिक हुँदैछ।',
  'Comments could not be loaded.': 'टिप्पणीहरू लोड हुन सकेनन्।',
  'This comment may already be posted.': 'यो टिप्पणी पोस्ट भइसकेको हुन सक्छ।',
  'Check comments': 'टिप्पणी जाँच्नुहोस्',
  'Write another comment?': 'अर्को टिप्पणी लेख्ने?',
  'New comment': 'नयाँ टिप्पणी',
  'No comments yet': 'अहिलेसम्म टिप्पणी छैन',
  'Say something kind.': 'केही राम्रो कुरा भन्नुहोस्।',
  'Load more comments': 'थप टिप्पणीहरू हेर्नुहोस्',
  'Refresh comments': 'टिप्पणीहरू पुनः लोड गर्नुहोस्',
  'Close comments': 'टिप्पणी बन्द गर्नुहोस्',
  'Replying to': 'जवाफ दिँदै',
  'Cancel reply': 'जवाफ रद्द गर्नुहोस्',
  'Add a comment': 'टिप्पणी लेख्नुहोस्',
  'Send comment': 'टिप्पणी पठाउनुहोस्',
  'The comment result is unknown.': 'टिप्पणीको नतिजा थाहा भएन।',

  'Open original': 'पहिलेको खोल्नुहोस्',
  'Prepare a new post': 'नयाँ पोस्ट तयार गर्नुहोस्',
  'Prepare a new story': 'नयाँ स्टोरी तयार गर्नुहोस्',
  'Start a separate upload?': 'छुट्टै अपलोड सुरु गर्ने?',
  'Prepare new upload': 'नयाँ अपलोड तयार गर्नुहोस्',
  'The earlier attempt may already be posted. Check it first to avoid a duplicate. Your current draft will be kept.': 'पहिलेको प्रयास पोस्ट भइसकेको हुन सक्छ। दोहोरिन नदिन पहिले जाँच्नुहोस्। तपाईंको हालको मस्यौदा सुरक्षित रहनेछ।',
  'This draft was already shared with different content.': 'यो मस्यौदा फरक सामग्रीसहित पहिले नै साझा भएको छ।',
  'The original upload was removed or expired.': 'पहिलेको अपलोड हटाइएको छ वा म्याद सकिएको छ।',
  'Upload interrupted. Your draft is kept. Retry to check the original result.': 'अपलोड रोकियो। मस्यौदा सुरक्षित छ। पहिलेको नतिजा जाँच्न फेरि प्रयास गर्नुहोस्।',
  'The upload result is unknown. Check your posts or stories before sharing again.': 'अपलोडको नतिजा थाहा भएन। फेरि साझा गर्नुअघि आफ्ना पोस्ट वा स्टोरी जाँच्नुहोस्।',
  'The original story was removed or expired.': 'पहिलेको स्टोरी हटाइएको छ वा म्याद सकिएको छ।',
  'Disappears after 24 hours': '२४ घण्टापछि हराउँछ',
  'Preview': 'पूर्वावलोकन',
  'Your story': 'तपाईंको स्टोरी',
  'Caption (optional)': 'क्याप्सन (ऐच्छिक)',
  'Share story': 'स्टोरी साझा गर्नुहोस्',
  'Sharing...': 'साझा गर्दै...',
  'Discard this draft?': 'यो मस्यौदा हटाउने?',
  'Leaving will remove this draft from this screen.': 'यहाँबाट निस्कँदा यो मस्यौदा यस स्क्रिनबाट हट्नेछ।',
  'Keep editing': 'सम्पादन जारी राख्नुहोस्',
  'Discard': 'हटाउनुहोस्',
  'Your upload is still in progress.': 'तपाईंको अपलोड जारी छ।',
  'Photo preview unavailable': 'तस्बिरको पूर्वावलोकन उपलब्ध छैन',
  'File could not be read': 'फाइल पढ्न सकिएन',
  'Video preview unavailable. Your video is still selected.': 'भिडियोको पूर्वावलोकन उपलब्ध छैन। तपाईंको भिडियो चयन भएकै छ।',
  'That file is over 25 MB. Choose a smaller one.': 'यो फाइल २५ एमबीभन्दा ठूलो छ। सानो फाइल छान्नुहोस्।',
  'Could not refresh.': 'रिफ्रेस हुन सकेन।',
  'Nothing yet': 'अहिलेसम्म केही छैन',
  'Likes, comments and new followers show up here.': 'लाइक, टिप्पणी र नयाँ फलोअरहरू यहाँ देखिन्छन्।',
  'Attach photo': 'तस्बिर संलग्न गर्नुहोस्',
  'Starting': 'सुरु हुँदैछ',
  'Recording': 'रेकर्ड हुँदैछ',
  'Finishing': 'सकिँदैछ',
  'Send voice message': 'आवाज सन्देश पठाउनुहोस्',
  'Microphone permission is needed to record. Allow it in Settings.': 'रेकर्ड गर्न माइक्रोफोनको अनुमति चाहिन्छ। सेटिङमा अनुमति दिनुहोस्।',
  'Could not start recording.': 'रेकर्ड सुरु गर्न सकिएन।',
  'Could not save the recording.': 'रेकर्ड सुरक्षित गर्न सकिएन।',
  'Hold on a little longer. That was too short.': 'अलि लामो रेकर्ड गर्नुहोस्। यो धेरै छोटो भयो।',
  'Loading voice message': 'आवाज सन्देश लोड हुँदैछ',
  'Pause voice message': 'आवाज सन्देश रोक्नुहोस्',
  'Play voice message': 'आवाज सन्देश सुन्नुहोस्',
  'Could not play this voice message.': 'यो आवाज सन्देश सुन्न सकिएन।',
  'Voice message': 'आवाज सन्देश',
  'Remove retry copy?': 'फेरि पठाउन राखिएको प्रतिलिपि हटाउने?',
  'Remove retry copy': 'फेरि पठाउने प्रतिलिपि हटाउनुहोस्',
  'This removes only the attachment kept on this screen. It does not delete a message that may already be delivered.': 'यसले यो स्क्रिनमा राखिएको संलग्नक मात्र हटाउँछ। पहिले नै पुगेको हुन सक्ने सन्देश मेटाउँदैन।',
  'Leave chat?': 'बाहिरिने?',
  'Leaving removes local retry copies, not messages that may have arrived.': 'बाहिरिँदा यहाँका प्रतिलिपि हट्छन्। पुगेका सन्देश मेटिँदैनन्।',
  'Stay here': 'यहीँ रहनुहोस्',
  'Leave': 'बाहिरिनुहोस्',
  'Your attachment is still sending.': 'तपाईंको संलग्नक अझै पठाइँदैछ।',
  'Photo': 'तस्बिर',
  'Photos': 'तस्बिरहरू',
  'Open full screen': 'पूरा स्क्रिनमा खोल्नुहोस्',
  'Photo could not load': 'तस्बिर लोड हुन सकेन',
  'Poll': 'मत सर्वेक्षण',
  'Option': 'विकल्प',
  'Add option': 'विकल्प थप्नुहोस्',
  'Remove poll': 'मत सर्वेक्षण हटाउनुहोस्',
  'Remove vote': 'मत हटाउनुहोस्',
  'vote': 'मत',
  'votes': 'मत',
  'One choice per person. Results show counts, not names.': 'प्रति व्यक्ति एउटा विकल्प। नतिजामा संख्या देखिन्छ, नाम होइन।',
  'Add a question and different, non-empty options.': 'प्रश्न र फरक, खाली नभएका विकल्पहरू राख्नुहोस्।',
  'Could not save your vote. Try again.': 'मत सुरक्षित हुन सकेन। फेरि प्रयास गर्नुहोस्।',
  'No reels yet': 'अहिलेसम्म रिल छैन',
  'Share a short video with your community.': 'आफ्नो समुदायसँग छोटो भिडियो साझा गर्नुहोस्।',
  'Create a reel': 'रिल बनाउनुहोस्',
  'Room title': 'कोठाको नाम',
  'What is your room about?': 'तपाईंको कोठा के विषयमा हो?',
  'No calls yet': 'अहिलेसम्म कल छैन',
  'Start a call from any chat.': 'कुनै पनि च्याटबाट कल सुरु गर्नुहोस्।',
  'No rooms live right now': 'अहिले कुनै कोठा लाइभ छैन',
  'Start one and others can listen in.': 'कोठा सुरु गर्नुहोस् र अरूलाई सुन्न दिनुहोस्।',
  'Incoming video call': 'भिडियो कल आउँदैछ',
  'Incoming voice call': 'भ्वाइस कल आउँदैछ',
  'Accept': 'स्वीकार गर्नुहोस्',
  'Decline': 'अस्वीकार गर्नुहोस्',
  'Could not update the call. Try again.': 'कल अद्यावधिक हुन सकेन। फेरि प्रयास गर्नुहोस्।',
  'No archived chats': 'अभिलेखमा च्याट छैन',
  'Start a conversation': 'कुराकानी सुरु गर्नुहोस्',
  'New group': 'नयाँ समूह',
  'One to one': 'एक जनासँग',
  'Group name': 'समूहको नाम',
  'Search by name or username': 'नाम वा प्रयोगकर्ता नामबाट खोज्नुहोस्',
  'Find someone to chat with': 'कुराकानी गर्न कोही खोज्नुहोस्',
  'Search for a member, then tap them.': 'सदस्य खोज्नुहोस् र छान्नुहोस्।',
  'No matches': 'कुनै नतिजा भेटिएन',
  'Enter a group name.': 'समूहको नाम राख्नुहोस्।',
  'Create group': 'समूह बनाउनुहोस्',
  'Discard this group?': 'यो समूहको मस्यौदा हटाउने?',
  'The name and selected people will be cleared.': 'नाम र छानिएका व्यक्तिहरू हट्नेछन्।',
  'Starting the conversation. Please wait.': 'कुराकानी सुरु हुँदैछ। पर्खनुहोस्।',
  'Could not load members. Try again.': 'सदस्यहरू देखाउन सकेन। फेरि प्रयास गर्नुहोस्।',
  'The chat may already exist. Check Chats before starting it again.': 'च्याट बनिसकेको हुन सक्छ। फेरि सुरु गर्नुअघि च्याटमा हेर्नुहोस्।',
  'Back to Chats': 'च्याटमा फर्कनुहोस्',
  'Choose up to 49 people.': '४९ जनासम्म छान्नुहोस्।',
  'Find someone by name or username.': 'नाम वा प्रयोगकर्ता नामबाट खोज्नुहोस्।',
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
  'Saved': 'सुरक्षित गरिएका',
  'You have not posted yet': 'तपाईंले अझै पोस्ट गर्नुभएको छैन',
  'No posts yet': 'अझै पोस्ट छैन',
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
    builder: (_) => PhotoViewer(urls: [url], headers: headers),
  ));
}

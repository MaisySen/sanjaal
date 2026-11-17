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
  'This private media link is not supported.': 'यो निजी मिडिया लिङ्क चल्दैन।',
  'This photo is unavailable.': 'यो तस्बिर उपलब्ध छैन।',
  'Could not read stories. Try again.': 'स्टोरी पढ्न सकिएन। फेरि प्रयास गर्नुहोस्।',
  'No upload details to show.': 'देखाउनका लागि अपलोडको विवरण छैन।',
  'Upload safety info could not be cleared. Uploading is paused.': 'अपलोडको सुरक्षा जानकारी हटाउन सकिएन। अपलोड रोकिएको छ।',
  'Your upload was confirmed, but its safety info could not be cleared. Open the original before starting another.': 'तपाईंको अपलोड पुष्टि भयो, तर यसको सुरक्षा जानकारी हटाउन सकिएन। अर्को सुरु गर्नुअघि मूल पोस्ट वा स्टोरी खोल्नुहोस्।',
  'Upload safety info could not be saved. Nothing was sent.': 'अपलोडको सुरक्षा जानकारी सुरक्षित गर्न सकिएन। केही पनि पठाइएको छैन।',
  'Earlier upload safety info could not be read. Uploading is paused.': 'अघिल्लो अपलोडको सुरक्षा जानकारी पढ्न सकिएन। अपलोड रोकिएको छ।',
  'An earlier upload may already be posted. Check your profile before starting another.': 'अघिल्लो अपलोड पोस्ट भइसकेको हुन सक्छ। अर्को सुरु गर्नुअघि आफ्नो प्रोफाइल जाँच्नुहोस्।',
  'Details': 'विवरण',
  'Upload details': 'अपलोडको विवरण',
  'Camera or media picker could not be opened. Try again.': 'क्यामेरा वा मिडिया छान्ने सुविधा खोल्न सकिएन। फेरि प्रयास गर्नुहोस्।',
  'Photo permissions could not be opened. Try again.': 'तस्बिरका अनुमति खोल्न सकिएन। फेरि प्रयास गर्नुहोस्।',
  "Sign in again to view this account's local drafts.": 'यो खाताका स्थानीय मस्यौदा हेर्न फेरि साइन इन गर्नुहोस्।',
  'Sign in to view saved drafts.': 'सुरक्षित मस्यौदा हेर्न साइन इन गर्नुहोस्।',
  'Could not read saved drafts. Nothing was replaced.': 'सुरक्षित मस्यौदा पढ्न सकिएन। केही पनि बदलिएको छैन।',
  'Untitled poll': 'शीर्षक नभएको मतदान',
  "Sign in again to view this account's settings.": 'यो खाताको सेटिङ हेर्न फेरि साइन इन गर्नुहोस्।',
  'Chats could not be loaded.': 'च्याटहरू लोड हुन सकेनन्।',
  'No messages yet': 'अहिलेसम्म सन्देश छैन',
  'Shared a post': 'पोस्ट साझा गर्नुभयो',
  'Unpin': 'पिन हटाउनुहोस्',
  'Pin to top': 'माथि पिन गर्नुहोस्',
  'Unarchive': 'अभिलेखबाट हटाउनुहोस्',
  'Archive': 'अभिलेखमा राख्नुहोस्',
  'Archived': 'अभिलेख',
  'Back to chats': 'च्याटमा फर्कनुहोस्',
  'Archived chats': 'अभिलेखमा राखिएका च्याटहरू',
  'More': 'थप',
  'Calls could not be loaded.': 'कलहरू लोड हुन सकेनन्।',
  'Rooms could not be loaded.': 'रुमहरू लोड हुन सकेनन्।',
  'Hosted by': 'सञ्चालक:',
  'Missed': 'छुटेको',
  'Incoming': 'आएको',
  'Outgoing': 'गरेको',
  'No answer': 'उठाइएन',
  'Search people and #tags': 'मान्छे र #ट्याग खोज्नुहोस्',
  'Find people to follow': 'फलो गर्न मान्छे खोज्नुहोस्',
  'Type a name, a username or a hashtag.': 'नाम, प्रयोगकर्ता नाम वा ह्यासट्याग लेख्नुहोस्।',
  'Search could not be loaded.': 'खोजका नतिजा लोड हुन सकेनन्।',
  'Clear search': 'खोज हटाउनुहोस्',
  'Notifications could not be loaded.': 'सूचनाहरू लोड हुन सकेनन्।',
  'liked your post': 'ले तपाईंको पोस्ट मन पराउनुभयो',
  'commented:': 'ले टिप्पणी गर्नुभयो:',
  'started following you': 'ले तपाईंलाई फलो गर्न थाल्नुभयो',
  'No photo or text posts yet': 'अहिलेसम्म तस्बिर वा लेख पोस्ट छैन',
  'No connection. Check your internet and try again.': 'इन्टरनेट जडान छैन। जडान जाँच गरेर फेरि प्रयास गर्नुहोस्।',
  'The server took too long. Try again.': 'सर्भरले धेरै समय लियो। फेरि प्रयास गर्नुहोस्।',
  'Please sign in again.': 'कृपया फेरि साइन इन गर्नुहोस्।',
  'You have not blocked anyone': 'तपाईंले कसैलाई ब्लक गर्नुभएको छैन',
  'Blocked people could not be loaded.': 'ब्लक गरिएका व्यक्तिहरू लोड हुन सकेनन्।',
  "Version": "संस्करण",
  "Unavailable": "उपलब्ध छैन",
  "A community app for Nepalis: a feed, short videos, chat, calls and a coin wallet.": "नेपाली समुदायको एप: फिड, छोटा भिडियो, च्याट, कल र सिक्का वालेट।",
  "App updates": "एप अद्यावधिक",
  "Publisher": "प्रकाशक",
  "Privacy": "गोपनीयता",
  "Terms": "सर्तहरू",
  "Open source licences": "खुला स्रोत इजाजतपत्रहरू",
  "View licences": "इजाजतपत्रहरू हेर्नुहोस्",
  "We store your email, username, display name, what you post and your messages so the app can work. We do not run ads, we do not sell your data and we do not track you across other apps. To delete your account and data, write to contact@fintex.au.": "एप सञ्चालन गर्न हामी तपाईंको इमेल, प्रयोगकर्ता नाम, देखाइने नाम, पोस्ट र सन्देशहरू राख्छौँ। हामी विज्ञापन देखाउँदैनौँ, तपाईंको डाटा बेच्दैनौँ र अन्य एपमा तपाईंलाई पछ्याउँदैनौँ। आफ्नो खाता र डाटा मेटाउन contact@fintex.au मा लेख्नुहोस्।",
  "Be kind. Do not post illegal content, spam or other people's private details. We may remove content or accounts that break these rules. Coins are an in-app balance.": "सम्मानपूर्वक व्यवहार गर्नुहोस्। गैरकानुनी सामग्री, स्प्याम वा अरूका निजी विवरण पोस्ट नगर्नुहोस्। यी नियम उल्लङ्घन गर्ने सामग्री वा खाता हामी हटाउन सक्छौँ। सिक्का एपभित्रको मौज्दात हो।",
  "Check Google Play for a newer full app build.": "एपको नयाँ पूर्ण संस्करणका लागि Google Play मा जाँच गर्नुहोस्।",
  "Checking Google Play...": "Google Play मा जाँच हुँदै छ...",
  "Google Play reports no newer build for this account.": "Google Play अनुसार यो खाताका लागि नयाँ संस्करण छैन।",
  "A newer build is available. Download it with Google Play.": "नयाँ संस्करण उपलब्ध छ। Google Play बाट डाउनलोड गर्नुहोस्।",
  "Choose whether to download in the Google Play dialog.": "Google Play को संवादमा डाउनलोड गर्ने वा नगर्ने रोज्नुहोस्।",
  "Downloading with Google Play. You can keep using Sanjaal.": "Google Play बाट डाउनलोड हुँदै छ। सञ्जाल चलाइरहन सक्नुहुन्छ।",
  "Update downloaded. Save your work before restarting.": "अद्यावधिक डाउनलोड भयो। पुनः सुरु गर्नुअघि आफ्नो काम सुरक्षित गर्नुहोस्।",
  "Google Play is installing the update and may restart Sanjaal.": "Google Play ले अद्यावधिक स्थापना गर्दै छ र सञ्जाल पुनः सुरु हुन सक्छ।",
  "Could not offer an update. Check your connection and use the Google Play account that installed Sanjaal.": "अद्यावधिक उपलब्ध गराउन सकिएन। इन्टरनेट जाँच गर्नुहोस् र सञ्जाल स्थापना गरेको Google Play खाता प्रयोग गर्नुहोस्।",
  "Update canceled. Your current app is unchanged.": "अद्यावधिक रद्द भयो। हालको एप परिवर्तन भएको छैन।",
  "The update did not finish. Check Google Play and try again.": "अद्यावधिक पूरा भएन। Google Play जाँच गरी फेरि प्रयास गर्नुहोस्।",
  "Install full app updates through your app store. In-app updates are available only on Android with Google Play.": "पूर्ण एप अद्यावधिक आफ्नो एप स्टोरबाट स्थापना गर्नुहोस्। एपभित्र अद्यावधिक गर्ने सुविधा Google Play भएको Android मा मात्र उपलब्ध छ।",
  "Restart and install": "पुनः सुरु गरी स्थापना गर्नुहोस्",
  "Download update": "अद्यावधिक डाउनलोड गर्नुहोस्",
  "Check for updates": "अद्यावधिक जाँच गर्नुहोस्",
  "These are full app updates, not background code patches.": "यी पूर्ण एप अद्यावधिक हुन्, पृष्ठभूमिमा कोड मात्र फेरिने अद्यावधिक होइनन्।",

  'No messages yet. Say hello to the room.': 'अहिलेसम्म सन्देश छैन। कोठामा नमस्ते भन्नुहोस्।',
  'Unmute': 'अनम्युट',
  'Mute': 'म्युट',
  'You can speak. Tap Unmute when ready.': 'तपाईं बोल्न सक्नुहुन्छ। तयार भएपछि अनम्युट थिच्नुहोस्।',
  'Push notifications': 'पुश सूचनाहरू',
  'Not set up yet': 'अझै सेट अप गरिएको छैन',
  'Checking notification permission...': 'सूचनाको अनुमति जाँच हुँदैछ...',
  'Off: allow notifications in system settings': 'बन्द छ: फोनको सेटिङमा सूचना अनुमति दिनुहोस्',
  'Off: no device token. Try again after reopening Sanjaal': 'फोन दर्ता हुन सकेन। सञ्जाल फेरि खोलेर प्रयास गर्नुहोस्',
  'Device registered. Push delivery has not been verified': 'फोन दर्ता भयो। सूचना आइपुग्ने कुरा अझै जाँचिएको छैन',
  'Notification registration needs another try': 'सूचनाका लागि फेरि दर्ता गर्नुपर्छ',
  'Not available on this device yet. Try again after reopening Sanjaal': 'यो फोनमा अहिले उपलब्ध छैन। सञ्जाल फेरि खोलेर प्रयास गर्नुहोस्',
  'Signing out of notifications...': 'सूचनाबाट साइन आउट हुँदैछ...',
  'Local notification token removed': 'फोनबाट सूचनाको टोकन हटाइयो',
  'Signed out. Notification token cleanup could not be confirmed': 'साइन आउट भयो। सूचनाको टोकन हटेको पुष्टि हुन सकेन',
  'Saved drafts': 'सुरक्षित मस्यौदाहरू',
  'Save text draft': 'लेखको मस्यौदा सुरक्षित गर्नुहोस्',
  'Text and polls, saved only on this device for this account. Photos and videos are not saved.': 'यस खाताका लेख र मतदानका मस्यौदा यही फोनमा मात्र सुरक्षित हुन्छन्। तस्बिर र भिडियो सुरक्षित हुँदैनन्।',
  'Drafts never post automatically. Signing out hides them until this account returns. Delete drafts here to remove them from this device.': 'मस्यौदा आफैँ पोस्ट हुँदैनन्। साइन आउट गरेपछि यही खातामा फेरि साइन इन नगरेसम्म देखिँदैनन्। फोनबाट हटाउन मस्यौदा यहाँ मेटाउनुहोस्।',
  'Text draft': 'लेखको मस्यौदा',
  'Poll draft': 'मतदानको मस्यौदा',
  'Delete draft': 'मस्यौदा मेटाउनुहोस्',
  'Delete this local draft?': 'फोनमा सुरक्षित यो मस्यौदा मेटाउने?',
  'This removes only the saved copy on this device, not any published post.': 'यसले फोनमा सुरक्षित प्रति मात्र मेटाउँछ, पोस्ट भइसकेको सामग्री होइन।',
  'No saved drafts yet. Use Save text draft while writing a post.': 'सुरक्षित मस्यौदा छैनन्। पोस्ट लेख्दा मस्यौदा सुरक्षित गर्ने बटन प्रयोग गर्नुहोस्।',
  'Sign in to save drafts on this device.': 'यो फोनमा मस्यौदा सुरक्षित गर्न साइन इन गर्नुहोस्।',
  'Only text and poll options can be saved for now. Photos and videos are not saved.': 'अहिले लेख र मतदानका विकल्प मात्र सुरक्षित गर्न सकिन्छ। तस्बिर र भिडियो सुरक्षित हुँदैनन्।',
  'Draft saved on this device. Find it in Settings > Saved drafts. Nothing was posted.': 'मस्यौदा यही फोनमा सुरक्षित भयो। सेटिङको सुरक्षित मस्यौदामा हेर्नुहोस्। केही पोस्ट भएको छैन।',
  'Polls are not available for this session. Keep the draft or remove the poll to post text.': 'यो सत्रमा मतदान उपलब्ध छैन। मस्यौदा राख्नुहोस् वा मतदान हटाएर लेख पोस्ट गर्नुहोस्।',

  'Take a photo': 'तस्बिर खिच्नुहोस्',
  'Stop recording': 'रेकर्डिङ रोक्नुहोस्',
  'Start recording': 'रेकर्डिङ सुरु गर्नुहोस्',
  'Flash off': 'फ्ल्यास बन्द',
  'Flash on': 'फ्ल्यास खुला',
  'Add to story': 'स्टोरीमा थप्नुहोस्',
  'Video': 'भिडियो',
  'seconds': 'सेकेन्ड',
  'Your media could not be loaded.': 'तस्बिर वा भिडियो लोड हुन सकेन।',
  'Your interrupted capture is ready to review. Nothing has been posted.': 'रोकिएको रेकर्डिङ हेर्न तयार छ। केही पनि पोस्ट भएको छैन।',
  'Videos': 'भिडियोहरू',
  'The interrupted recording could not be recovered. Nothing was posted.': 'रोकिएको रेकर्डिङ फिर्ता पाउन सकिएन। केही पोस्ट भएको छैन।',
  'The camera is unavailable. Try again or choose media from your library.': 'क्यामेरा उपलब्ध छैन। फेरि प्रयास गर्नुहोस् वा ग्यालरीबाट छान्नुहोस्।',
  'That item is unavailable. Check your connection or choose another.': 'यो फाइल उपलब्ध छैन। इन्टरनेट जाँच्नुहोस् वा अर्को छान्नुहोस्।',
  'That camera setting is not supported on this device.': 'यो फोनमा क्यामेराको त्यो सेटिङ चल्दैन।',
  'Switch camera': 'क्यामेरा बदल्नुहोस्',
  'Review capture': 'रेकर्डिङ हेर्नुहोस्',
  'Recents': 'हालका',
  'Photo permissions': 'तस्बिरको अनुमति',
  'Only the photos and videos you allow are shown.': 'तपाईंले अनुमति दिएका तस्बिर र भिडियो मात्र देखिन्छन्।',
  'Nothing has been posted. Discarding removes this local capture.': 'केही पनि पोस्ट भएको छैन। हटाउँदा यो स्थानीय रेकर्डिङ हट्छ।',
  'No media to show. Choose another album or allow more photos.': 'कुनै तस्बिर वा भिडियो छैन। अर्को एल्बम छान्नुहोस् वा थप तस्बिरलाई अनुमति दिनुहोस्।',
  'Load more': 'थप लोड गर्नुहोस्',
  'Discard this recording?': 'यो रेकर्डिङ हटाउने?',
  'Device picker': 'फोनबाट छान्नुहोस्',
  'Close camera': 'क्यामेरा बन्द गर्नुहोस्',
  'Close': 'बन्द गर्नुहोस्',
  'Story viewers': 'स्टोरी हेर्नेहरू',
  'Delete story': 'स्टोरी मेटाउनुहोस्',
  'Choose photos with the device picker, or allow library access to see your Recents here.': 'फोनको फोटो छनोटबाट छान्नुहोस् वा यहाँ हालका तस्बिर हेर्न ग्यालरीको अनुमति दिनुहोस्।',
  'Choose more photos in your device settings.': 'फोनको सेटिङमा थप तस्बिरलाई अनुमति दिनुहोस्।',
  'Choose more': 'थप छान्नुहोस्',
  'Choose a video up to': 'यति सेकेन्डसम्मको भिडियो छान्नुहोस्:',
  'Choose a video': 'भिडियो छान्नुहोस्',
  'Choose a photo': 'तस्बिर छान्नुहोस्',
  'Camera or microphone access is unavailable. Allow it in your device settings, or choose media from your library.': 'क्यामेरा वा माइक्रोफोनको अनुमति छैन। फोनको सेटिङमा अनुमति दिनुहोस् वा ग्यालरीबाट छान्नुहोस्।',
  'Camera': 'क्यामेरा',
  'All media': 'सबै फोटो र भिडियो',
  'When off, other members cannot send new copies of your posts through Share to chat. You can still share your own posts. Public links and earlier messages are not removed.': 'बन्द हुँदा अरू सदस्यले तपाईंका पोस्ट कुराकानीमा नयाँ रूपमा पठाउन सक्दैनन्। तपाईंले आफ्ना पोस्ट साझेदारी गर्न सक्नुहुन्छ। सार्वजनिक लिङ्क र पुराना सन्देश हट्दैनन्।',
  'This limits new comments and replies. Existing comments stay visible. You can still comment on your own posts.': 'यसले नयाँ टिप्पणी र जवाफ सीमित गर्छ। पुराना टिप्पणी देखिइरहन्छन्। आफ्ना पोस्टमा तपाईंले टिप्पणी गर्न सक्नुहुन्छ।',
  'Comments are limited by this member.': 'यस सदस्यले टिप्पणी सीमित गरेका छन्।',
  'Settings result is unconfirmed. Reload to check before changing them again.': 'सेटिङ सुरक्षित भएको पुष्टि भएन। फेरि परिवर्तन गर्नुअघि पुनः लोड गरेर जाँच्नुहोस्।',
  'Reload current settings': 'हालको सेटिङ फेरि लोड गर्नुहोस्',
  'Settings could not be loaded.': 'सेटिङ लोड हुन सकेन।',
  'This story is unavailable. It may have expired or its audience changed.': 'यो स्टोरी उपलब्ध छैन। यसको समय सकिएको वा हेर्न पाउनेहरूको सेटिङ बदलिएको हुन सक्छ।',
  'Story audience': 'स्टोरी हेर्न पाउनेहरू',
  'Choose close friends or hide your protected stories from someone. This applies to active protected stories and future protected stories.': 'नजिकका साथीहरू छान्नुहोस् वा कसैबाट आफ्ना सुरक्षित स्टोरीहरू लुकाउनुहोस्। यो अहिलेका र आगामी सुरक्षित स्टोरीहरूमा लागू हुन्छ।',
  'Earlier public stories and copies people saved cannot be made private. These settings do not change posts, reels or chats.': 'पहिलेका सार्वजनिक स्टोरी र अरूले सुरक्षित गरेका प्रतिहरू निजी बनाउन सकिँदैन। यी सेटिङले पोस्ट, रिल वा च्याट बदल्दैनन्।',
  'Exact username': 'ठ्याक्कै प्रयोगकर्ता नाम',
  'Find person': 'व्यक्ति खोज्नुहोस्',
  'No story audience changes yet.': 'स्टोरी हेर्न पाउनेहरूको सेटिङ अझै बदलिएको छैन।',
  'Hidden from stories': 'स्टोरीबाट लुकाइएको',
  'Close friend': 'नजिकका साथी',
  'Close friends': 'नजिकका साथीहरू',
  'No extra restrictions': 'थप प्रतिबन्ध छैन',
  'Story audience could not be loaded.': 'स्टोरी हेर्न पाउनेहरूको सेटिङ खोल्न सकिएन।',
  'Story audience saved.': 'स्टोरी हेर्न पाउनेहरूको सेटिङ सुरक्षित भयो।',
  'Can see stories shared with Close friends, even without following you.': 'तपाईंलाई फलो नगरे पनि नजिकका साथीहरूसँग साझा गरिएका स्टोरी हेर्न सक्छन्।',
  'Hide my stories': 'मेरा स्टोरी लुकाउनुहोस्',
  'Cannot view your protected stories, including Close friends stories.': 'नजिकका साथीहरूका लागि राखिएका लगायत तपाईंका सुरक्षित स्टोरीहरू हेर्न सक्दैनन्।',
  'Blocking still takes priority. Earlier public links and saved copies are not removed.': 'ब्लक गरिएका व्यक्तिले हेर्न पाउँदैनन्। पहिलेका सार्वजनिक लिङ्क र सुरक्षित गरिएका प्रतिहरू हट्दैनन्।',
  'Save result is unconfirmed. Reload before making another change.': 'सेभ भएको पुष्टि भएन। फेरि बदल्नुअघि पुनः खोल्नुहोस्।',
  'Story sharing needs the protected-story server update. Your draft is still here.': 'स्टोरी साझा गर्न सर्भरमा सुरक्षित स्टोरीको अपडेट चाहिन्छ। तपाईंको मस्यौदा यहीँ छ।',
  'Who can see this story': 'यो स्टोरी कसले हेर्न सक्छ',
  'Only me': 'म मात्र',
  'Hidden people and blocked people cannot view it. People can save what they see.': 'लुकाइएका वा ब्लक गरिएका व्यक्तिले हेर्न सक्दैनन्। हेर्न पाउनेले त्यसको प्रति राख्न सक्छन्।',
  'Close friends can view it even if they do not follow you. Hide my stories and blocking take priority.': 'नजिकका साथीहरूले फलो नगरे पनि हेर्न सक्छन्। स्टोरी लुकाउने र ब्लक गर्ने सेटिङ पहिले लागू हुन्छन्।',
  'Settings saved.': 'सेटिङ सुरक्षित भयो।',
  'Allow sharing to Sanjaal chats': 'Sanjaal कुराकानीमा साझेदारी गर्न दिनुहोस्',
  'Nobody else': 'अरू कसैले सक्दैन',
  'People you follow': 'तपाईंले फलो गरेका व्यक्तिहरू',
  'Everyone': 'सबैजना',
  'Who can comment on your posts and reels': 'तपाईंका पोस्ट र रिलमा कसले टिप्पणी गर्न सक्छ',
  'Comments and sharing': 'टिप्पणी र साझेदारी',
  'Sends a request by email': 'इमेलबाट अनुरोध पठाउँछ',
  'Delete my account': 'मेरो खाता मेटाउनुहोस्',
  'This removes the local retry copy. It does not remove anything already posted. Check your profile before starting a new upload.': 'यसले फेरि प्रयास गर्न राखिएको स्थानीय प्रति हटाउँछ। पहिले नै पोस्ट भएको कुरा हटाउँदैन। नयाँ अपलोड सुरु गर्नुअघि आफ्नो प्रोफाइल जाँच्नुहोस्।',
  'Check the current upload before starting another.': 'अर्को अपलोड सुरु गर्नुअघि हालको अपलोड जाँच्नुहोस्।',
  'Your story is up.': 'तपाईंको स्टोरी राखियो।',
  'Uploading... Keep the app open.': 'अपलोड हुँदैछ। एप खुला राख्नुहोस्।',
  'Finishing upload...': 'अपलोड पूरा हुँदैछ...',
  'Preparing upload...': 'अपलोड तयार हुँदैछ...',
  'Appearance': 'स्वरूप',
  'Login': 'लगइन',
  'More info and support': 'थप जानकारी र सहायता',
  'Your balance and activity': 'तपाईंको मौज्दात र गतिविधि',
  'Your app and media': 'तपाईंको एप र मिडिया',
  'Who can interact with you': 'तपाईंसँग अन्तरक्रिया गर्न सक्नेहरू',
  'How you use Sanjaal': 'तपाईंले Sanjaal प्रयोग गर्ने तरिका',
  'Your account': 'तपाईंको खाता',
  'No matching settings': 'मिल्ने सेटिङ भेटिएन',
  'Search settings': 'सेटिङ खोज्नुहोस्',
  'Settings and activity': 'सेटिङ र गतिविधि',
  'Review transfer': 'स्थानान्तरण जाँच्नुहोस्',
  'Confirm send': 'पठाउने पुष्टि गर्नुहोस्',
  'Resolve the saved original transfer first.': 'पहिले सुरक्षित गरिएको स्थानान्तरण पुष्टि गर्नुहोस्।',
  'Retry original transfer': 'पहिलेको स्थानान्तरण फेरि प्रयास गर्नुहोस्',
  'Retrying checks the same transfer. It will not send it twice.': 'फेरि प्रयास गर्दा यही स्थानान्तरण जाँचिन्छ। दुई पटक पठाइँदैन।',
  '{amount} coins to @{member}': '@{member} लाई {amount} सिक्का',
  'Original transfer needs confirmation.': 'पहिलेको स्थानान्तरण पुष्टि गर्न बाँकी छ।',
  'Reload pending transfer': 'बाँकी स्थानान्तरण फेरि लोड गर्नुहोस्',
  'Transfers are unavailable until live verification is complete.': 'सुरक्षित स्थानान्तरण तयार नहुँदासम्म सिक्का पठाउन मिल्दैन।',
  'Transfer confirmed.': 'सिक्का पठाएको पुष्टि भयो।',
  'Transfer was not sent because its details could not be saved.': 'विवरण सुरक्षित नभएकाले सिक्का पठाइएको छैन।',
  'Transfer result unconfirmed. Retry only this original transfer.': 'सिक्का पठाएको पुष्टि भएन। यही पहिलेको स्थानान्तरण मात्र फेरि प्रयास गर्नुहोस्।',
  'Pending transfer could not be saved. Sending is paused.': 'बाँकी स्थानान्तरण सुरक्षित भएन। सिक्का पठाउन रोकिएको छ।',
  'Pending transfer could not be read. Sending is paused.': 'बाँकी स्थानान्तरण पढ्न सकिएन। सिक्का पठाउन रोकिएको छ।',
  'The coins leave your balance now. If the payout fails, they come back.': 'अहिले सिक्का तपाईंको मौज्दातबाट घट्छ। भुक्तानी असफल भएमा सिक्का फिर्ता आउँछ।',
  'Cash out requested.': 'रकम निकाल्ने अनुरोध गरियो।',
  'Cash out canceled.': 'रकम निकाल्ने अनुरोध रद्द भयो।',
  'Cash outs': 'रकम निकालेको विवरण',
  'Cash out': 'रकम निकाल्नुहोस्',
  'Wallet action in progress.': 'वालेटको काम भइरहेको छ।',
  'Wallet could not be loaded.': 'वालेट लोड हुन सकेन।',
  'Showing the last loaded balance. Refresh before making changes.': 'पछिल्लो पटक लोड भएको मौज्दात देखाइएको छ। परिवर्तन गर्नुअघि पुनः लोड गर्नुहोस्।',
  'Adding coins is not switched on yet. Cash out is not available.': 'अहिले सिक्का थप्न र रकम निकाल्न मिल्दैन।',
  'Adding coins is not switched on yet.': 'अहिले सिक्का थप्न मिल्दैन।',
  'Cash out is not available yet.': 'अहिले रकम निकाल्न मिल्दैन।',
  'Transfer result unconfirmed. Check Activity before sending again.': 'सिक्का पठाएको पुष्टि भएन। फेरि पठाउनुअघि गतिविधि हेर्नुहोस्।',
  'Cash-out history could not be loaded.': 'रकम निकालेको विवरण लोड हुन सकेन।',
  'Retry cash-out history': 'रकम निकालेको विवरण फेरि लोड गर्नुहोस्',
  'No activity yet.': 'अहिलेसम्म कुनै गतिविधि छैन।',
  'Your coin history appears here.': 'तपाईंको सिक्काको विवरण यहाँ देखिन्छ।',
  'Enter a whole coin amount within your balance.': 'आफ्नो मौज्दातभित्रको पूर्ण सङ्ख्यामा सिक्का लेख्नुहोस्।',
  'Amount in NPR': 'नेपाली रुपैयाँमा रकम',
  '1 rupee = 1 coin. Minimum 10.': '१ रुपैयाँ = १ सिक्का। कम्तीमा १०।',
  'Test mode: no real money moves.': 'परीक्षण मोड: वास्तविक रकम सर्दैन।',
  'Pay with eSewa': 'eSewa बाट तिर्नुहोस्',
  'Note (optional)': 'नोट (वैकल्पिक)',
  'Sent.': 'पठाइयो।',
  'Coins (at least {min})': 'सिक्का (कम्तीमा {min})',
  'Could not open the browser.': 'ब्राउजर खोल्न सकिएन।',
  'Added {amount} coins.': '{amount} सिक्का थपियो।',
  'The payment did not go through. No coins were added.': 'भुक्तानी भएन। कुनै सिक्का थपिएन।',
  'eSewa top up': 'eSewa बाट सिक्का थपियो',
  'From {member}': '{member} बाट',
  'To {member}': '{member} लाई',
  'Gift from {member}': '{member} बाट उपहार',
  'Gift to {member}': '{member} लाई उपहार',
  'Cash out returned': 'निकाल्न राखिएको सिक्का फिर्ता भयो',
  'Requested': 'अनुरोध गरिएको',
  'Processing': 'प्रक्रियामा',
  'Under review': 'समीक्षामा',
  'Paid': 'भुक्तानी भएको',
  'Failed, coins returned': 'असफल, सिक्का फिर्ता भयो',
  'Canceled, coins returned': 'रद्द, सिक्का फिर्ता भयो',
  'Coins': 'सिक्का',
  'Activity': 'गतिविधि',

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
  'Email': 'इमेल',
  'Email or username': 'इमेल वा प्रयोगकर्ता नाम',
  'Enter a valid email': 'सही इमेल राख्नुहोस्',
  '3 to 30 letters, numbers, dots or underscores': '३ देखि ३० अक्षर, अंक, थोप्ला वा अन्डरस्कोर',
  'Password': 'पासवर्ड',
  'At least 8 characters': 'कम्तीमा ८ अक्षर',
  'Show password': 'पासवर्ड देखाउनुहोस्',
  'Hide password': 'पासवर्ड लुकाउनुहोस्',
  'Continue with Google': 'Google बाट जारी राख्नुहोस्',
  'Social sign in is in testing.': 'सामाजिक खाताबाट साइन इन परीक्षणमा छ।',
  'The first request can take up to a minute while the server wakes up.': 'सर्भर सुरु हुँदा पहिलो अनुरोधमा एक मिनेटसम्म लाग्न सक्छ।',
  'Sign in failed. Try again.': 'साइन इन हुन सकेन। फेरि प्रयास गर्नुहोस्।',
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
  'Block @{u}?': '@{u} लाई ब्लक गर्ने?',
  'Not enough coins. You need {n} more. Add coins from your wallet.': 'पर्याप्त कोइन छैन। तपाईंलाई {n} थप चाहिन्छ। वालेटबाट कोइन थप्नुहोस्।',
  'Sent {g} to @{u}': '@{u} लाई {g} पठाइयो',
  'Send a gift to @{u}': '@{u} लाई उपहार पठाउनुहोस्',
  'Raised hands ({n})': 'हात उठाएका ({n})',
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
  'Blocked people': 'ब्लक गरिएका व्यक्तिहरू',
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
  'Could not restore your sign-in. Try again.': 'तपाईंको साइन इन फेरि खोल्न सकिएन। फेरि प्रयास गर्नुहोस्।',
  'Your account has not been opened. Check your connection and try again.': 'तपाईंको खाता खोलिएको छैन। इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।',
  'Video preview unavailable': 'भिडियोको पूर्वावलोकन उपलब्ध छैन',
  'Try again': 'फेरि प्रयास गर्नुहोस्',
  'Refresh': 'रिफ्रेस',
  'Send': 'पठाउनुहोस्',
  'Send coins': 'सिक्का पठाउनुहोस्',
  'Start': 'सुरु',
  'Unblock': 'अनब्लक',
  'New post': 'नयाँ पोस्ट',
  'Contact us': 'सम्पर्क गर्नुहोस्',
  'About Sanjaal': 'सञ्जालको बारेमा',
  'A post was shared here. It is no longer available.': 'यहाँ एउटा पोस्ट सेयर गरिएको थियो। यो अब उपलब्ध छैन।',
  'Add': 'थप्नुहोस्',
  'Add people': 'मानिसहरू थप्नुहोस्',
  'Camera access is off. Turn it on in Settings to take photos or videos.': 'क्यामेरा अनुमति बन्द छ। फोटो वा भिडियो खिच्न सेटिङमा गएर खोल्नुहोस्।',
  'Checking earlier uploads...': 'अघिल्ला अपलोड जाँच्दै...',
  'Continue': 'जारी राख्नुहोस्',
  'Could not open the camera or photos. Try again.': 'क्यामेरा वा तस्बिर खोल्न सकिएन। फेरि प्रयास गर्नुहोस्।',
  'Create': 'बनाउनुहोस्',
  'Delete this story?': 'यो स्टोरी मेटाउने?',
  'Group info': 'समूहको जानकारी',
  'Keep': 'राख्नुहोस्',
  "You will not see each other's posts and they cannot follow you.": "तपाईंहरूले एकअर्काका पोस्ट देख्नुहुने छैन र उनीहरूले तपाईंलाई फलो गर्न सक्दैनन्।",
  "Video could not load": "भिडियो लोड हुन सकेन",
  "Delete post?": "पोस्ट मेटाउने?",
  "Send a gift": "उपहार पठाउनुहोस्",
  "On stage": "मञ्चमा",
  "Send message": "सन्देश पठाउनुहोस्",
  "End call": "कल समाप्त गर्नुहोस्",
  'Leave group': 'समूहबाट बाहिरिनुहोस्',
  'Leave this group?': 'यो समूहबाट बाहिरिने?',
  'Member': 'सदस्य',
  'New members see messages from when they join, not earlier ones.': 'नयाँ सदस्यले जोडिएपछिका सन्देश मात्र देख्छन्, अघिका देख्दैनन्।',
  'No connection. Some things may be out of date.': 'इन्टरनेट छैन। केही कुरा पुराना हुन सक्छन्।',
  'No views yet': 'अहिलेसम्म कसैले हेरेको छैन',
  'Photo access is off. Turn it on in Settings to choose photos or videos.': 'फोटो अनुमति बन्द छ। फोटो वा भिडियो छान्न सेटिङमा गएर खोल्नुहोस्।',
  'Photos or a text update': 'तस्बिर वा लेखिएको अपडेट',
  'Reel': 'रिल',
  'Remove from saved': 'सुरक्षित गरिएकामध्येबाट हटाउनुहोस्',
  'Removed from saved': 'सुरक्षित गरिएकामध्येबाट हटाइयो',
  'Rename group': 'समूहको नाम बदल्नुहोस्',
  'Retry': 'फेरि प्रयास गर्नुहोस्',
  'Sent to': 'पठाइयो',
  'Share to chat': 'च्याटमा सेयर गर्नुहोस्',
  'Short video': 'छोटो भिडियो',
  'Story': 'स्टोरी',
  'Usernames, separated by commas': 'प्रयोगकर्तानाम, अल्पविरामले छुट्याएर',
  'Video call': 'भिडियो कल',
  'Voice call': 'भ्वाइस कल',
  'You have no chats yet. Start one from Chats.': 'तपाईंसँग अहिलेसम्म कुनै च्याट छैन। च्याटबाट सुरु गर्नुहोस्।',
  'You will stop getting its messages. Someone has to add you again to rejoin.': 'तपाईंले यसका सन्देश पाउन छाड्नुहुनेछ। फेरि जोडिन कसैले तपाईंलाई थप्नुपर्छ।',
};

/// Translates a template with {name} placeholders, then fills them in.
String tf_(String en, Map<String, Object?> args) {
  var s = t_(en);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

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
    return Semantics(label: 'Sanjaal', image: true, child: FittedBox(fit: BoxFit.scaleDown, child: ExcludeSemantics(child: Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: size * 0.62, height: size * 0.62, child: const CustomPaint(painter: _SanjaalMark())),
      SizedBox(width: size * 0.14),
      Text('Sanjaal', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Theme.of(context).colorScheme.onSurface)),
    ]))));

  }
}

class _SanjaalMark extends CustomPainter {
  const _SanjaalMark();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save(); canvas.scale(size.width / 100, size.height / 100);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(25)), Paint()..color = brandRed);
    canvas.drawPath(Path()..moveTo(42,69)..lineTo(66,38)..lineTo(91,69)..close(), Paint()..color = const Color(0xFFFFD6DA));
    canvas.drawPath(Path()..moveTo(12,69)..lineTo(43,23)..lineTo(75,69)..close(), Paint()..color = Colors.white);
    canvas.drawPath(Path()..moveTo(33,38)..lineTo(43,23)..lineTo(53,38)..lineTo(47,36)..lineTo(43,42)..lineTo(39,36)..close(), Paint()..color = const Color(0xFFFFD6DA));
    canvas.drawPath(Path()..moveTo(28,81)..lineTo(50,78)..lineTo(72,81), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.4);
    for (final point in [const Offset(28,81), const Offset(72,81)]) { canvas.drawCircle(point, 4, Paint()..color = Colors.white); }
    canvas.drawCircle(const Offset(50,78), 6, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(50,78), 4.5, Paint()..color = brandBlue);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _SanjaalMark oldDelegate) => false;
}

/// Opens a picture full screen with pinch zoom.
void openImage(BuildContext context, String url, {Map<String, String>? headers}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PhotoViewer(urls: [url], headers: headers),
  ));
}

/// Retained read results stay usable while an explicit recovery action is shown.
class RefreshReadNotice extends StatelessWidget {
  const RefreshReadNotice({super.key,required this.onRetry});
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context)=>Material(color:Theme.of(context).colorScheme.surfaceContainerHigh,child:Padding(
    padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Row(children:[
      Expanded(child:Text(t_('Could not refresh.'),style:TextStyle(color:Theme.of(context).colorScheme.onSurface))),
      TextButton(onPressed:onRetry,child:Text(t_('Try again'),style:TextStyle(color:Theme.of(context).colorScheme.onSurface))),
    ]),
  ));
}

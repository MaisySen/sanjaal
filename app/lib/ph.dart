// ignore_for_file: constant_identifier_names
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Phosphor icons (MIT, https://github.com/phosphor-icons/core). SVGs are in assets/icons.
class PhData {
  const PhData(this.name);
  final String name;
}

class Ph {
  static const videocam = PhData('video-camera');
  static const send = PhData('paper-plane-tilt-fill');
  static const mic = PhData('microphone');
  static const cloud_off = PhData('cloud-slash');
  static const chevron_right = PhData('caret-right');
  static const card_giftcard = PhData('gift');
  static const search = PhData('magnifying-glass');
  static const person = PhData('user-fill');
  static const mode_comment_outlined = PhData('chat-teardrop');
  static const mic_off = PhData('microphone-slash');
  static const image_outlined = PhData('image');
  static const photo_outlined = PhData('image');
  static const delete_outline = PhData('trash');
  static const close = PhData('x');
  static const chat_bubble_outline = PhData('chat-circle');
  static const tag = PhData('hash');
  static const search_off = PhData('magnifying-glass');
  static const reply = PhData('arrow-bend-up-left');
  static const push_pin = PhData('push-pin-fill');
  static const play_circle_fill = PhData('play-circle-fill');
  static const notifications_off = PhData('bell-slash');
  static const notifications_none = PhData('bell');
  static const groups = PhData('users-three');
  static const favorite = PhData('heart-fill');
  static const favorite_border = PhData('heart');
  static const dynamic_feed_outlined = PhData('newspaper');
  static const bookmark_outline = PhData('bookmark-simple');
  static const call_outlined = PhData('phone');
  static const call_end = PhData('phone-x-fill');
  static const call = PhData('phone-fill');
  static const broken_image_outlined = PhData('image-broken');
  static const block = PhData('prohibit');
  static const back_hand_outlined = PhData('hand-waving');
  static const add = PhData('plus');
  static const account_balance_wallet_outlined = PhData('wallet');
  static const account_balance_wallet = PhData('wallet-fill');
  static const workspace_premium = PhData('crown');
  static const volume_up = PhData('speaker-high');
  static const volume_off = PhData('speaker-slash');
  static const visibility_outlined = PhData('eye');
  static const videocam_off = PhData('video-camera-slash');
  static const videocam_outlined = PhData('video-camera');
  static const unarchive_outlined = PhData('tray-arrow-up');
  static const settings_outlined = PhData('gear');
  static const rocket_launch = PhData('rocket-launch');
  static const refresh = PhData('arrow-clockwise');
  static const ramen_dining = PhData('bowl-food');
  static const push_pin_outlined = PhData('push-pin');
  static const podcasts = PhData('broadcast');
  static const play_circle_outline = PhData('play-circle');
  static const play_arrow_rounded = PhData('play-fill');
  static const person_search = PhData('user-focus');
  static const person_outline = PhData('user');
  static const person_off_outlined = PhData('user-minus');
  static const person_add = PhData('user-plus');
  static const pause_circle_filled = PhData('pause-circle-fill');
  static const notifications_outlined = PhData('bell');
  static const notifications_off_outlined = PhData('bell-slash');
  static const north_east = PhData('arrow-up-right');
  static const movie_outlined = PhData('film-strip');
  static const movie_filter = PhData('film-reel');
  static const more_horiz = PhData('dots-three');
  static const mode_comment = PhData('chat-teardrop-fill');
  static const mic_none = PhData('microphone');
  static const mail_outline = PhData('envelope-simple');
  static const logout = PhData('sign-out');
  static const local_florist = PhData('flower');
  static const landscape = PhData('mountains');
  static const info_outline = PhData('info');
  static const home_outlined = PhData('house');
  static const home = PhData('house-fill');
  static const group_add_outlined = PhData('users');
  static const graphic_eq = PhData('waveform');
  static const forum = PhData('chats-circle');
  static const fiber_manual_record = PhData('circle-fill');
  static const error_outline = PhData('warning-circle');
  static const edit_square = PhData('note-pencil');
  static const edit_outlined = PhData('pencil-simple');
  static const dynamic_feed = PhData('newspaper-fill');
  static const delete_forever_outlined = PhData('trash');
  static const copy = PhData('copy');
  static const check = PhData('check');
  static const chat_bubble = PhData('chat-circle-fill');
  static const camera_alt = PhData('camera');
  static const call_received = PhData('phone-incoming');
  static const call_made = PhData('phone-outgoing');
  static const archive_outlined = PhData('archive');
  static const add_circle_outline = PhData('plus-circle');
  static const add_box_outlined = PhData('plus-square');
}

class PhIcon extends StatelessWidget {
  const PhIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});
  /// A [PhData] or the asset name as a String.
  final Object icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final name = icon is PhData ? (icon as PhData).name : icon as String;
    return SvgPicture.asset('assets/icons/$name.svg', width: s, height: s, colorFilter: ColorFilter.mode(c, BlendMode.srcIn), semanticsLabel: semanticLabel);
  }
}

/// Lists the Phosphor MIT notice on the licences page.
void registerPhosphorLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/icons/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(['Phosphor Icons'], text);
  });
}

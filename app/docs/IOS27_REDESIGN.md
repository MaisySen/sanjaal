# Sanjaal iOS 27 redesign

Sanjaal is a Nepali community app: feed, reels, chats and calls, a coin wallet
with eSewa top-up, stories, search, notifications and profiles. Publisher is
Fintex Australia Pty Ltd, ABN 60 688 406 108, contact contact@fintex.au.
App version 0.4.0+4, Flutter, Android first with an iOS target.

This document is the design system spec and the record of the full iOS 27
Liquid Glass redesign, landed as one review branch,
review/sanjaal-ios27-redesign-20261121. The old look was Material 3: warm
paper #FAF7F2, crimson #B3122B, navy, 10px radii, flat outlined cards,
Material NavigationBar. The redesign keeps the brand and the structure and
changes the material: glass floats over the warm paper, crimson #C8102E and
blue #003893 stay the only accents, EN/NE language stays. Every screen was
restyled in this branch: Onboarding, Auth, Home feed, Stories, Reels, Chats,
Rooms, Calls, Wallet, Profile, Settings, Search, Notifications, About.

## What iOS 27 Liquid Glass is

Liquid Glass debuted in iOS 26 and was refined in iOS 27, which shipped
2026-09-14 and was introduced at WWDC 2026. It is GPU accelerated
translucency that simulates real glass optics: it lenses, bends and focuses
the background content rather than just blurring it, and highlights track
device motion. iOS 27 refinements: the material diffuses complex content
behind it better, improving readability; a darkened edge around glass
elements plus brighter specular highlights adds depth; a continuous
transparency slider in Settings, Appearance, Liquid Glass runs from ultra
clear to fully tinted and replaces the iOS 26.1 Clear/Tinted toggle; a
uniform toolbar appears across the top when content scrolls under floating
bars, keeping text legible; corner radius is consistent across the system;
app icons are sharper with refraction layers built in; search is
re-integrated into the tab bar. Liquid Glass adapts to Reduce Transparency
and Increase Contrast. Developers lost the opt-out: the
UIDesignRequiresCompatibility key is ignored when an app is built with the
iOS 27 SDK.

Sanjaal is Flutter, so there is no native .glassEffect(). Glass is
recreated: BackdropFilter with ImageFilter.blur plus layered gradients, a
1px bright top highlight and a darkened edge, and ClipRRect with large
consistent radii. True lensing needs a fragment shader under Impeller; that
is a later step, not this branch.

## Design system spec

All glass lives in `app/lib/glass/`. No screen invents its own glass values.

### Tokens: glass_tokens.dart

Radii, one consistent scale: card 20, sheet 28, button 8, input 12, pill
full. Blur: light 12, regular 20, heavy 32. Tints: light paper #FAF7F2, dark
#141311, so the glass floats over the same warm paper the app already has.
Specular highlight: white at 0.7 light, 0.8 dark. Darkened edge: black at
0.25 light, 0.4 dark. Shadow: soft warm black, never hard.
The radii are benchmarked: Instagram buttons are 8px, TikTok buttons 4px,
so 8px is the shared social button radius. A 16px button radius is the
generic template look.

Motion lives in GlassMotion: tab switch 200ms, like pop 300ms at scale
1 to 1.3 to 1, sheet slide 300ms, segment slide 200ms, all on an
ease-out cubic spring. Nothing in the app animates slower than 300ms for
a tap response. Slow fades are what make an app feel like a template.

### The glass recipe: glass_material.dart

GlassMaterial is the one recipe every component uses, top to bottom:
soft shadow under the shape, ClipRRect with the token radius, BackdropFilter
with ImageFilter.blur, the brightness tint at the effective opacity, a
vertical light falloff that is brighter at the top and slightly darker at
the bottom, a 1px bright top highlight, a 1px darkened edge around the
whole shape, then the child. It takes a child, a tint, a blur amount and
an opacity. When opacity is not given, the Liquid Glass slider drives it.

### The transparency slider: glass_settings.dart

One value, 0.0 ultra clear to 1.0 fully tinted, default 0.5, the middle of
the system slider. It maps to tint opacity between the contrast floor and
0.92. Fully tinted never reaches 1.0: glass stays glass. The setting is
stored in SharedPreferences under `glass_transparency`, following the
AppPrefs pattern in ui.dart, and the slider lives in Settings as
GlassSettingsRow, with Ultra clear and Fully tinted ends.

### Contrast floors

The floors are WCAG math, not taste. Worst case is glass over the opposite
extreme: pure black behind light glass, pure white behind dark glass. Body
text is ink #1C1A17 in light mode and #ECE8E1 in dark mode.
Light tint at 0.55 over black composites to about #8A8885, ink on it is
4.91:1. At 0.50 it is 4.16:1, below the bar. Floor is 0.55.
Dark tint at 0.65 over white composites to about #666664, light text on it
is 4.71:1. At 0.60 it is 3.99:1, below the bar. Floor is 0.65.
The slider never goes below its floor, and an explicit opacity passed to
GlassMaterial is clamped up to the floor, so text over glass always clears
4.5:1 even over the worst background.

### Reduce Transparency fallback

Stated plainly: Flutter exposes Increase Contrast through
MediaQuery.highContrast, but it exposes no Reduce Transparency media query
at all. There is no platform value to read for it. So the mechanism is the
in-app switch: `reduceGlass` in GlassSettings, stored under
`glass_reduced`, shown in Settings as Reduce glass. When it is on, or when
the platform reports Increase Contrast, every glass surface degrades to a
solid card colour with a plain outline: no blur, no gradients, no shadow.
The switch is the Reduce Transparency equivalent the user controls.

### Components

GlassTabBar: floating detached glass pill, 16px from the sides, 12px plus
the bottom safe area from the bottom. Five destinations, same labels,
same icons, same unread badge on Chats, active tab in a filled crimson
tinted capsule. Search is re-integrated into the bar as a circular glass
button at the end of the pill, as in iOS 27. It is an action, not a sixth
tab, so the five tab structure does not change. Tab taps give a selection
haptic.

GlassAppBar: full width glass surface at the top. Large title when content
is at the top, uniform toolbar when content has scrolled under it: same
glass surface, same actions, compact title. The collapse is a height
change in this branch; animating it is a follow-up motion item.

GlassCard: 20px radius, regular blur, 16px padding for things that are
cards, like a balance card. GlassCard.flush is the feed row: full bleed,
no radius, no padding, a hairline divider at the bottom. That is the
Instagram rule. GlassButton: primary crimson glass with a white label,
secondary clear glass. Both 44px minimum height, 8px radius, 14px
semibold label. GlassSheet: 28px top radius, drag handle, heavy blur, with
an optional height fraction; TikTok comments open at 60 percent of the
viewport. GlassSegmentedControl: For you / Following as TikTok does it,
two 16px text labels with a 28px wide, 3px tall crimson underline bar
under the active one, sliding in 200ms. It is deliberately not a pill.

### Theme: main.dart buildTheme

Radii split to the token scale: card 20, button 8, input 12. Bottom sheet
top radius 28, dialog radius 20. The unused navigationBarTheme and
tabBarTheme were removed: no TabBar or NavigationBar widget exists in
lib, only GlassTabBar. Warm paper, crimson and navy palette unchanged.

## Meta design book principles

The Meta principles applied across the branch: photography first, large
real photos carry the surface, not decoration. Pill buttons for primary
actions. Color scarcity, one accent reserved for action: Sanjaal keeps
Nepal crimson #C8102E for action and blue #003893 for brand moments, and
nothing else competes with them. Sentence case copy everywhere. Generous
whitespace, no packed rows. Large friendly type: 17px semibold titles,
16px body, 14px semibold names, 12px secondary metadata. Accessibility
first contrast, the floors above. Direct interaction: double tap to like,
tap the row to open it, no intermediate confirmations. Forgiving
interactions: double tap never removes a like, failed sends stay visible
with a retry, the offline queue holds stamps when the network drops.
Sensory feedback: haptics on tab taps, segment changes, likes, page
changes in onboarding, and the send button.

## Benchmark: TikTok and Instagram

The bar is TikTok and Instagram level, for everything. Sanjaal keeps its
own brand, Nepal crimson and blue, Nepali community, EN/NE, but the craft
standard is theirs. Every screen below names the exact behaviour it must
match. Sources are the live apps as measured in November 2026.

### TikTok

For You feed: one full screen 9:16 video at a time, 1080 by 1920, vertical
paging with snap. Top tabs are Following and For You, centred, with a
search icon top right. The right action rail is a vertical column: creator
avatar about 60px with a follow plus below it, then like, comment,
bookmark and share, each about 60 by 70px including its count label, 4px
between icon and count. Bottom left holds username, caption and the music
line. A 4px progress bar sits on the very bottom edge. The bottom tab bar
sits over the bottom 40px of video. Safe zone: keep faces and text inside
the centre column, about 100px clear at the top and 300px at the bottom.

Double tap to like: a big heart appears at the tap point and the rail
heart turns solid pink #FE2C55 with a glow. The like pop is a scale 1 to
1.3 to 1 over 0.3s. Single tap pauses and plays. Long press opens a
context sheet. Every like is optimistic: the count changes first, the API
catches up.

Comments: a bottom sheet at 60 percent of the viewport, dark surface,
rounded top corners, header with the comment count centred and a close
button, each comment with a 32px avatar, username, text and time, a like
button with a count per comment, replies, and a bottom input row with
avatar, text field, emoji and send.

Create: record with the camera or upload, then caption with hashtag chips
and post. The create button in the tab bar is the signature layered plus:
a white plus on a block with cyan on one side and pink on the other.
Sanjaal's create stays the Post action, but the flow must feel this
direct: one tap, camera open, caption, post. No form page with five
fields.

### Instagram

Stories: a horizontal row of 64px rings. Unseen is a 2px gradient ring,
45 degrees, #F58529 to #DD2A7B to #515BD4. Seen is a 1px #DBDBDB ring.
The avatar inside is 60px with a 2px gap. The username below is 12px
secondary, one line, truncated. The row runs off the right edge so a
cropped avatar tells the thumb there is more. Your own story carries a
plus badge. A ring is a signal, not decoration: when every ring looks the
same it says nothing.

Feed post: full bleed photo, no card, no radius, nothing on it. Header is
a 32px avatar, a 14px semibold username, a 12px timestamp. The action row
is heart, comment, repost and send on the left, save alone on the right,
24px icons. Portrait posts are 1080 by 1350, 4:5.

DM list: rows with a 56px avatar, name 14 semibold, preview 14 secondary,
timestamp 12 secondary, unread dot. Thread: 32px avatars, bubbles with
18px radius and a 4px tail corner, timestamps inline, no date header spam.

Profile: avatar about 110px, counts row, bio, then a 3 column grid with
1px gutters and 3:4 tiles. Posts, Reels and Tagged tabs are about 44px
tall. The grid is the profile: no list of cards.

Reels: full screen 9:16, right column with like, comment, repost, share
and the audio thumbnail, bottom overlay with profile picture, username,
Follow, caption and audio pill. Safe zone: 270px clear at the top, 670px
at the bottom, 120px on the right.

Tab bar: five tabs, 24px icons, 10pt labels, active icon filled. The DM
tab carries the red unread badge.

## What changed, screen by screen

Navigation shell (main.dart): Material NavigationBar replaced with
GlassTabBar. Same five tabs, same labels, same unread badge polled every
30 seconds, same compose behaviour. Search is a circular button at the end
of the pill. glassSettings.load() runs at startup. Reels, chats, wallet and
profile lists carry bottom padding for the floating bar.

Home feed (feed_page.dart): GlassAppBar with a large title that collapses
to the uniform toolbar when content scrolls under it, vertical scroll
only, so PageView horizontal swipes do not trigger it. TikTok text tabs
for For you and Following with the crimson underline. PostCard is the
Instagram layout: header row with a 32px avatar, 14px semibold name,
@username plus 12px time, menu; caption; full bleed media, single 300px
or multi 300px PageView; action row with ReactionButton, comment count,
gift; divider. Double tap on media likes through a
GlobalKey<ReactionButtonState>, with a centred 88px white heart overlay
fading after 700ms and a medium haptic. Comments open as a 60 percent
glass sheet with Instagram comment rows, 32px avatars, username plus time,
body, reply and delete, and a pill input with a filled crimson send
button. ComposePage Post is a GlassButton with a Posting state, and the
video card is a GlassCard.

Stories (stories_page.dart): Instagram rings, unseen 2.5px gradient
#F58529, #DD2A7B, #515BD4, seen 1px outlineVariant, 60px avatar, 12px
names, tile width 76, bar height 106. Plus badge in brandRed. Add
photo and video sheet and viewers sheet use showGlassSheet. Story
progress bars have rounded ends.

Reels (reels_page.dart): double tap to like with a 96px heart overlay and
a reaction key. Follow is a crimson pill 32px tall, Following is
transparent with a white border. Top bar title centred with refresh at
right. Right rail icons 32px, spacing 20, right offset 8. Empty state
wrapped in ThemeData.dark so text stays readable on black.

Chats (chat_pages.dart): ChatsPage uses a collapsed GlassAppBar, 56px
uniform toolbar, with a compose pencil action; the extended New chat FAB
is removed. DM rows use 56px leading circles, 15px titles semibold when
unread, 14px previews, crimson unread badges, grey when muted, time
coloured primary when unread. Pin, mute, archive and message menus use
showGlassSheet. ChatPage header has a 32px avatar plus name and typing
indicator. Bubbles are Instagram style: own crimson with white text,
others surfaceContainerHighest, 18px radius with a 4px tail corner, max
width 75 percent. Reply blocks tinted per side. Composer is a pill
TextField with a filled crimson send button. NewChat result avatars are
44px.

Rooms (rooms_page.dart): room list rows have a crimson LIVE pill with a
white dot instead of a chevron. RoomView stage is Spaces style circles:
56px avatar circles in a Wrap, crimson speaking ring, mic status, host
Move to listeners button under other speakers. Raised hands card is a
GlassCard. Room chat input is a pill field with a filled send.

Calls (call_page.dart, calls_page.dart, voice.dart): video tiles are
ClipRRect radius 20 on #1C1C1E with a glass name chip. Mic and cam
controls are white 0.14 glass circles 56px. End call is a 64px red circle.
Self view is clipped to radius 20. Call history avatars are 44px.
VoiceBubble gained a dark flag, white icon and progress inside own crimson
bubbles. The recorder bar is wrapped in a pill GlassMaterial. The
incoming call screen is unchanged in this branch: dark navy screen, 112px
avatar, 72px accept and decline buttons. It is already a dark full screen
layout; a glass pass on it is a follow-up.

Wallet (wallet_page.dart): balance is a GlassCard with 56px numerals,
GlassButton Add coins primary and Send secondary. History rows have
leading icon circles, crimson tint for incoming, grey for outgoing, and
bold amounts coloured crimson when positive.

Profile (profile_pages.dart): ProfileHeader is the Instagram layout, 110px
avatar left, stats row right, name 16 bold, @username grey, bio left
aligned, actions below, divider. Stats are 16px number w800 plus 13px
label. The post list is kept; the 3 column photo grid is not built, see
the not done list.

Settings (settings_page.dart): theme and language SegmentedButtons use
the token style, crimson selection, 8px radius. GlassSettingsRow holds the
Liquid Glass slider and the Reduce glass switch. All rows and the version
footer are unchanged.

Search (search_page.dart): pill search field in the app bar, 40px tall,
with a 44px result avatar. Tag rows use a 44px circle with a tag icon.

Notifications (notifications_page.dart): 44px leading circles with the
type icon on a 0.12 tint.

About (about_page.dart): Logo at top, 72px, centred title and version.
Publisher, privacy and terms text and the licences button are unchanged.

Auth (auth_page.dart): sign in and create account are a full width 52px
GlassButton primary, Continue with Google is a 52px GlassButton
secondary. Logo, subtitle, social testing note and server wake note are
unchanged.

Onboarding (onboarding_page.dart): the 140px red gradient circle is a
solid brandRed disc, no gradient blob. Next and Get started are a 52px
GlassButton. Four slides, dots and Skip are unchanged. Page changes give
a selection haptic.

Gifts (gifts.dart): gift tiles are GlassCard with 8px padding and a 28px
icon, the sheet opens with showGlassSheet. Gift names, prices, balance
line and the unaffordable message are unchanged.

Reactions (reactions.dart): emoji map replaced with reaction icons: like
thumb_up, love favorite, laugh emoji_emotions, wow
sentiment_very_satisfied, sad sentiment_dissatisfied, angry
sentiment_very_dissatisfied. The state class is public as
ReactionButtonState with a hasReaction getter and a like() method that
adds love only when none; double tap never removes. Like pop is
AnimatedScale 1.3 over 150ms. Picker uses showGlassSheet with icon
buttons in circles, selected gets a crimson tint. Reacted icon is crimson,
unreacted is favorite_border. No emoji characters anywhere in the UI.

EmptyState (ui.dart): icon 30 to 48, title 17 semibold, hint colour to
onSurfaceVariant.

Dialogs (actions.dart): covered by the theme radius 20 only; no per
dialog restyle.

## What was kept

Every existing asset and icon. The pubspec has no assets section, all
asset lines are commented out, so there are no bundled image assets to
move. Icons are Material Icons only, and every one is kept. The Logo
widget in ui.dart is code drawn, a solid brandRed rounded square with
the character, and it is unchanged. brandRed and brandBlue are unchanged.
docs/brand/logo-512.png is untouched. No asset file or icon was deleted,
replaced or renamed. No new asset was needed.

All API calls, routes, tab order and feature behaviour are unchanged. All
EN/NE strings are unchanged, including t_('Live rooms') as 'लाइभ कोठा' and
t_('Move to listeners') as 'श्रोतामा सार्नुहोस्'. Test visible signatures
are unchanged: PostCard(session, post, onRemoved), ProfileHeader(user,
actions), RoomView named params, showGiftSheet(context, session, postId,
username, path, onSent), buildStage, buildTheme(brightness, fontFamily).
Gift names and the unaffordable snackbar text are unchanged. No new
dependency. No backend URL and no credential anywhere.

## What is generic and was removed

Padded rounded cards with shadows used for everything: feed posts inside
boxes, 10px radii, outlined borders. The feed post is now a full bleed
row. A pill segmented control for For You and Following: replaced with
TikTok text tabs and an underline. 16px radius buttons: now 8px. 11pt tab
labels: now 10pt. No haptics anywhere: tab, segment, like, send and page
change taps now give haptics. Comments as a full page: now the 60 percent
sheet. Stories with no seen or unseen ring state: now the Instagram ring.
Profile as a list of rows: now the Instagram header, grid still open.
No double tap to like anywhere: now on feed and reels. Reels with no right
action rail and no safe zone: rail and centred title are in. A create flow
that is a plain form: now upload plus caption with a GlassButton Post
action. DM rows without avatar and timestamp discipline: now 56px avatars
and unread states. Gradient blob heroes: none existed and none were
added; the hero is the content itself, full bleed photo and video, not a
decorative gradient. The onboarding gradient circle is now a solid disc.

## Verification

Toolchain: Flutter 3.50.1, Dart 3.14.0, from a git clone of
github.com/flutter/flutter.git at tag 3.50.1, at
~/workspace/.tooling/flutter-git/bin/flutter. Flutter 3.50 formally
deprecates package:flutter/material.dart in favour of standalone
material_ui, which is why the app already imports
package:material_ui/material_ui.dart everywhere.

flutter pub get: exit 0, 29 dependencies changed, 33 packages have newer
versions incompatible with the constraints, none required.

flutter analyze: exit 0, no issues. Five errors were found and fixed
during verification: undefined `scheme` in chat_pages.dart, AnimatedBuilder
passed as a PreferredSizeWidget in feed_page.dart, a deprecated activeColor
on the SwitchListTile in glass_settings.dart, an unused local variable in
glass_tab_bar.dart, and unused imports in feed_page.dart and ui.dart. Two
info lints about null aware map entries were silenced with ignore comments
after proving the suggested `?` form is a type error: the map value type
is String, not String?.

flutter test: exit 0, 29 passed, 1 skipped, 0 failed. The skipped test is
live_api_test, skipped unless LIVE_API is set, and it was not run against
the live API. One failure was found and fixed during verification: gift
tiles overflowed by 0.455px after the GlassCard padding was added, fixed
by 8px padding and a 28px icon.

Scans on every file touched: 0 em or en dashes, 0 literal emoji
characters, 0 emoji escape sequences, no secrets added. The only
credential like values in the app are pre-existing and in files this
branch did not touch: push.dart FirebaseOptions apiKey, which that file
says is public by design, and api.dart auth0Domain, auth0ClientId and
Bearer header usage.

flutter build apk was not run: no Android SDK is installed on this
machine. No live device test was run: no physical device. Test renders
only.

## Honestly not done

Profile photo grid: the 3 column grid with 1px gutters and 3:4 tiles is
not built. Posts are text first and there is no media only feed endpoint,
so the profile keeps the post list under the Instagram header.

Story replies: no endpoint exists, so the viewers sheet is view only.

In-app camera recording for create: compose is upload from the gallery
plus caption. Camera recording needs a camera permission flow and is not
built.

True lensing fragment shader: glass is BackdropFilter plus gradients.
Lensing under Impeller is a later step.

Incoming call screen: unchanged in this branch, see above.

App bar collapse animation: the collapse is a height change, not an
animated morph. Tab switch morph is also still open.

flutter build apk: not run, no Android SDK on this machine. No physical
device test.

## Phase plan, updated

Phases 1 to 5 are done in this branch: design system, navigation shell,
feed and stories, reels, chats and calls, wallet and profile and settings.
Phase 6 remains: motion, haptics and accessibility pass. Collapse
animation for the app bar, tab switch morph, full Reduce Transparency and
Increase Contrast audit, contrast re-check on every glass surface, EN/NE
label check.

## Deliberately not changed

No API call, no route, no tab order, no feature behaviour. No new
dependency. No backend URL and no credential anywhere. The theme palette
is untouched: the same warm paper, crimson and navy, the same text
styles. True lensing through a fragment shader is not in this branch;
BackdropFilter blur plus gradients is the glass.

import 'package:material_ui/material_ui.dart';

/// Liquid Glass tokens for the Sanjaal iOS 27 redesign.
///
/// One consistent radius scale, one blur scale, one tint pair per brightness,
/// and one transparency value that drives them all. No screen invents its own
/// glass values; everything reads from here.
///
/// Contrast floors are grounded in WCAG math, not taste. Worst case is a
/// glass surface floating over the opposite extreme: pure black behind light
/// glass, pure white behind dark glass. Body text is ink #1C1A17 in light
/// mode and #ECE8E1 in dark mode, over the paper tint #FAF7F2 and the dark
/// tint #141311.
///   Light tint at 0.55 over black composites to about #8A8885, ink on it
///   is 4.91:1. At 0.50 it is 4.16:1, below the bar. Floor is 0.55.
///   Dark tint at 0.65 over white composites to about #666664, light text
///   on it is 4.71:1. At 0.60 it is 3.99:1, below the bar. Floor is 0.65.
/// The slider never goes below its floor, so text over glass always clears
/// 4.5:1 even over the worst background.
class GlassTokens {
  GlassTokens._();

  // Radii. One scale, used everywhere. Card 20, sheet 28, button 8, pill
  // full. The numbers are benchmarked, not picked: Instagram buttons are
  // 8px radius, TikTok buttons 4px; 8px is the shared social button radius.
  // Cards at 20px read as wallet and media cards; feed rows are full bleed
  // and use GlassCard.flush instead of a radius at all.
  static const double radiusCard = 20;
  static const double radiusSheet = 28;
  static const double radiusButton = 8;
  static const double radiusPill = 999;

  // Blur. Light for chips and small controls, regular for bars and cards,
  // heavy for sheets that sit over busy content.
  static const double blurLight = 12;
  static const double blurRegular = 20;
  static const double blurHeavy = 32;

  // Tints. The warm paper background is the surface the glass floats over,
  // so the light tint is paper itself and the dark tint is the dark surface.
  static const Color tintLight = Color(0xFFFAF7F2);
  static const Color tintDark = Color(0xFF141311);

  // Opacity floors. See the class doc: these are the minimum tint opacity
  // at the ultra clear end of the slider, and they keep body text at or
  // above 4.5:1 contrast over the worst case background.
  static const double opacityFloorLight = 0.55;
  static const double opacityFloorDark = 0.65;

  // Fully tinted end of the slider. Never 1.0: glass stays glass, it never
  // becomes a flat solid, unless Reduce Transparency is on.
  static const double opacityMax = 0.92;

  // Specular highlight: a bright top edge that sells the glass. Stronger in
  // dark mode, where the surface itself is dark.
  static const Color highlightLight = Color(0xB3FFFFFF);
  static const Color highlightDark = Color(0xCCFFFFFF);

  // Darkened edge: the iOS 27 darkened rim around every glass element. It
  // separates the glass from the content behind it.
  static const Color edgeLight = Color(0x40000000);
  static const Color edgeDark = Color(0x66000000);

  // Shadow under floating glass. Soft, warm, never black and hard.
  static const Color shadowLight = Color(0x26000000);
  static const Color shadowDark = Color(0x66000000);

  /// Maps the Liquid Glass transparency slider (0.0 ultra clear to 1.0
  /// fully tinted) to a tint opacity. The slider never drops below the
  /// contrast floor for the current brightness.
  static double opacityFor(double slider, Brightness brightness) {
    final clamped = slider.clamp(0.0, 1.0);
    final floor = brightness == Brightness.light ? opacityFloorLight : opacityFloorDark;
    return floor + (opacityMax - floor) * clamped;
  }

  /// Tint colour for the current brightness.
  static Color tintFor(Brightness brightness) => brightness == Brightness.light ? tintLight : tintDark;

  /// Specular highlight colour for the current brightness.
  static Color highlightFor(Brightness brightness) => brightness == Brightness.light ? highlightLight : highlightDark;

  /// Darkened edge colour for the current brightness.
  static Color edgeFor(Brightness brightness) => brightness == Brightness.light ? edgeLight : edgeDark;

  /// Shadow colour for the current brightness.
  static Color shadowFor(Brightness brightness) => brightness == Brightness.light ? shadowLight : shadowDark;
}

/// Motion and haptics, benchmarked against TikTok and Instagram.
///
/// TikTok's like pop is a scale 1 to 1.3 to 1 over 0.3s with a glow.
/// Tab switches and segment changes are fast, about 0.2s, with a light
/// selection haptic. Sheets slide in over about 0.3s. Nothing in the app
/// animates slower than 0.3s for a tap response; slow fades are what make
/// an app feel like a template.
class GlassMotion {
  GlassMotion._();

  /// Tab switch and segment change.
  static const Duration tabSwitch = Duration(milliseconds: 200);

  /// Like pop: scale 1 to 1.3 to 1.
  static const Duration likePop = Duration(milliseconds: 300);
  static const double likePopPeakScale = 1.3;

  /// Bottom sheet slide in.
  static const Duration sheetSlide = Duration(milliseconds: 300);

  /// Segment underline slide.
  static const Duration segmentSlide = Duration(milliseconds: 200);

  /// The spring curve for these. Fast out, gentle settle.
  static const Curve spring = Curves.easeOutCubic;
}

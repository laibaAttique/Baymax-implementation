import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Baymax look: "aurora glass". A cool mist background with soft indigo, violet and teal light, frosted white glass cards,
/// deep-indigo actions. Neutral and unisex by design.
///
/// Visibility rules (checked by `test/ui_test.dart`): every text colour reaches at least 4.5:1 contrast on the lightest AND
/// darkest background stop and on the glass surfaces, white text on every button colour reaches 4.5:1, and the light glow
/// colours are used for surfaces, borders and light only, never for small text.
class AppTheme {
  AppTheme._();

  // --- background (mist gradient with glowing orbs; see GlassBackground)
  static const Color gradTop = Color(0xFFF6F7FF);
  static const Color gradMid = Color(0xFFEEF1FC);
  static const Color gradBottom = Color(0xFFE4EEF6);

  // --- brand
  /// Deep indigo: buttons, active states and accent text. White on it is 7.9:1.
  static const Color primary = Color(0xFF4338CA);
  /// Pale indigo for chips and icon wells (text on it uses [textPrimary] or [primary]).
  static const Color primaryLight = Color(0xFFE6E8FF);
  /// The glow colour: shadows, orbs and gradients only.
  static const Color glow = Color(0xFF7C83FF);
  /// Teal companion to the indigo: orbs, accents on charts, positive highlights (never small text).
  static const Color aqua = Color(0xFF2CC5B4);
  static const Color violet = Color(0xFF9B8CFF);
  /// A teal that is dark enough for small text and icons on glass (6.1:1 on glass).
  static const Color teal = Color(0xFF086B60);

  // --- surfaces
  /// Glass fill: white at 66% over the mist background. Use [glass] for the full look (border + shadow).
  static const Color card = Color(0xA8FFFFFF);
  /// Plain background colour for small fills behind icons and unselected chips.
  static const Color background = Color(0xB3FFFFFF);
  static const Color border = Color(0xFFD5D9F2);

  // --- text
  static const Color textPrimary = Color(0xFF12162B);
  static const Color textSecondary = Color(0xFF4A5272);

  // --- status (all >= 4.5:1 on the glass surfaces)
  static const Color success = Color(0xFF0A6640);
  static const Color warning = Color(0xFF874C00);
  static const Color error = Color(0xFF9E1E17);

  // macro colours (each >= 4.5:1 on the glass surfaces)
  static const Color macroProtein = Color(0xFF9E1E17);
  static const Color macroCarbs = Color(0xFF874C00);
  static const Color macroFat = Color(0xFF1B5E9B);

  // --- spacing scale (4 pt grid) and radii: use these instead of ad-hoc numbers
  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20, s24 = 24, s32 = 32;
  static const double rSmall = 12, rMedium = 16, rLarge = 22, rHero = 28;
  /// Space to leave at the bottom of a scrolling screen. Inside the tabs, the outer Scaffold (extendBody) puts the floating bar's
  /// height into `MediaQuery.padding.bottom`, so this clears the bar there and is just the device inset plus breathing room on
  /// screens that are pushed without the bar.
  static double navSpace(BuildContext context) => MediaQuery.paddingOf(context).bottom + 28;

  /// A clean pastel of [c] for a background (a plain opacity over the mist goes muddy grey).
  static Color tint(Color c, [double amount = 0.12]) => Color.alphaBlend(c.withOpacity(amount), const Color(0xFFF8F9FF));

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gradTop, gradMid, gradBottom],
  );

  /// The primary action gradient. Both ends keep white text >= 4.5:1.
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5848E0), Color(0xFF3B30B8)],
  );

  /// A quieter gradient for hero surfaces and icon wells.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF3730A3), Color(0xFF2B2788)],
  );

  static List<BoxShadow> glowShadow({double blur = 24, double opacity = 0.22, Offset offset = const Offset(0, 8)}) =>
      [BoxShadow(color: const Color(0xFF4338CA).withOpacity(opacity), blurRadius: blur, offset: offset)];

  /// Layered, subtle elevation for glass cards: one tight contact shadow plus one soft indigo ambient shadow.
  static List<BoxShadow> softShadow() => [
        BoxShadow(color: const Color(0xFF1E2250).withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1)),
        BoxShadow(color: const Color(0xFF4338CA).withOpacity(0.10), blurRadius: 28, offset: const Offset(0, 12)),
      ];

  /// The glass card look: translucent white, a light rim, a soft indigo ambient shadow.
  static BoxDecoration glass({double radius = rLarge, Color? tint, bool glowing = true}) => BoxDecoration(
        color: tint ?? card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
        boxShadow: glowing ? softShadow() : const [],
      );

  // --- typography: Plus Jakarta Sans, one family, clear weights. Falls back to the system font offline.
  static TextTheme _textTheme() {
    final base = GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme);
    TextStyle? s(TextStyle? t, double size, FontWeight w, {double? h, double ls = 0, Color c = textPrimary}) =>
        t?.copyWith(fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c);
    return base.copyWith(
      displaySmall: s(base.displaySmall, 32, FontWeight.w800, h: 1.15, ls: -0.8),
      headlineMedium: s(base.headlineMedium, 26, FontWeight.w800, h: 1.2, ls: -0.5),
      headlineSmall: s(base.headlineSmall, 22, FontWeight.w800, h: 1.25, ls: -0.3),
      titleLarge: s(base.titleLarge, 19, FontWeight.w800, h: 1.3, ls: -0.2),
      titleMedium: s(base.titleMedium, 16, FontWeight.w700, h: 1.35, ls: -0.1),
      titleSmall: s(base.titleSmall, 14, FontWeight.w700, h: 1.35),
      bodyLarge: s(base.bodyLarge, 16, FontWeight.w500, h: 1.5),
      bodyMedium: s(base.bodyMedium, 14, FontWeight.w500, h: 1.5, c: textSecondary),
      bodySmall: s(base.bodySmall, 12.5, FontWeight.w500, h: 1.45, c: textSecondary),
      labelLarge: s(base.labelLarge, 14, FontWeight.w700, ls: 0.1),
      labelMedium: s(base.labelMedium, 12, FontWeight.w700, ls: 0.2, c: textSecondary),
      labelSmall: s(base.labelSmall, 11, FontWeight.w800, ls: 0.8, c: textSecondary),
    );
  }

  /// Overline style: small caps-like labels above values ("TODAY'S WORKOUT").
  static const TextStyle overline = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: textSecondary);

  static ThemeData get lightTheme {
    final text = _textTheme();
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMedium));
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent, // the gradient is painted once, behind every screen
      canvasColor: Colors.transparent,
      primaryColor: primary,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: aqua,
        surface: const Color(0xFFF6F7FF),
        onSurface: textPrimary,
        error: error,
        outline: border,
      ),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: textPrimary),
        actionsIconTheme: const IconThemeData(color: textPrimary),
        titleTextStyle: text.titleLarge,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD9DCF0),
          disabledForegroundColor: const Color(0xFF4A5272),
          minimumSize: const Size(double.infinity, 54),
          shape: shape,
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: card,
          side: const BorderSide(color: primary, width: 1.3),
          minimumSize: const Size(double.infinity, 52),
          shape: shape,
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary, minimumSize: const Size(48, 44), textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w800)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: textPrimary, minimumSize: const Size(48, 48))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xCCFFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(rMedium), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMedium), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMedium), borderSide: const BorderSide(color: primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMedium), borderSide: const BorderSide(color: error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rMedium), borderSide: const BorderSide(color: error, width: 2)),
        labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.w700),
        hintStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        prefixIconColor: textSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF59607F)),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : const Color(0xFFE3E6F6)),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : const Color(0xFF59607F)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primaryLight,
        side: const BorderSide(color: border),
        labelStyle: text.labelLarge!.copyWith(color: textPrimary, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xF5F8F9FF),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFB9BEDB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rHero))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFAF8F9FF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rHero)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge!.copyWith(fontSize: 14.5, color: textPrimary),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFFF6F7FF), surfaceTintColor: Colors.transparent),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: textPrimary,
        titleTextStyle: text.titleSmall!.copyWith(fontSize: 15, color: textPrimary),
        subtitleTextStyle: text.bodySmall!.copyWith(fontSize: 13, color: textSecondary, height: 1.4),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        actionTextColor: const Color(0xFFB9BEFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMedium)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary, linearTrackColor: Color(0xFFDDE0F5), circularTrackColor: Color(0xFFDDE0F5)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: textPrimary, borderRadius: BorderRadius.circular(10)),
        textStyle: text.bodySmall!.copyWith(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }

  /// A frosted-glass blur behind [child]. Use sparingly (navigation bar, hero cards): blur is costly on slow devices.
  static Widget blurred({required Widget child, double sigma = 16, BorderRadius radius = BorderRadius.zero}) =>
      ClipRRect(borderRadius: radius, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child));
}

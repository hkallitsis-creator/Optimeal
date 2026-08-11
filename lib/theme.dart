import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand constants used across the app.
class AppBrand {
  static const String appName = 'OptiMeal';
  static const String tagline = 'Time & Budget Kitchen Engine';
  static const String assistantName = 'Chef Harris';
}

class AppSpacing {
  // Spacing values
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Edge insets shortcuts
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal padding
  static const EdgeInsets horizontalXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXl = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXl = EdgeInsets.symmetric(vertical: xl);
}

/// Border radius constants for consistent rounded corners
class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

// =============================================================================
// TEXT STYLE EXTENSIONS
// =============================================================================

/// Extension to add text style utilities to BuildContext
/// Access via context.textStyles
extension TextStyleContext on BuildContext {
  TextTheme get textStyles => Theme.of(this).textTheme;
}

/// Helper methods for common text style modifications
extension TextStyleExtensions on TextStyle {
  /// Make text bold
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);

  /// Make text semi-bold
  TextStyle get semiBold => copyWith(fontWeight: FontWeight.w600);

  /// Make text medium weight
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);

  /// Make text normal weight
  TextStyle get normal => copyWith(fontWeight: FontWeight.w400);

  /// Make text light
  TextStyle get light => copyWith(fontWeight: FontWeight.w300);

  /// Add custom color
  TextStyle withColor(Color color) => copyWith(color: color);

  /// Add custom size
  TextStyle withSize(double size) => copyWith(fontSize: size);
}

// =============================================================================
// COLORS
// =============================================================================

/// Modern, neutral color palette for light mode
/// Uses soft grays and blues instead of purple for a contemporary look
class LightModeColors {
  // Palette (OptiMeal)
  // Canvas Background: Muted Sage (Home Dashboard) (#C5D3C1)
  // Cards & Bottom Sheets: Pure White (#FFFFFF)
  // Titles / Header / Selected States: Deep Forest (#284236)
  // Primary Actions (CTA): Warm Terracotta/Copper (#D96B43)
  // Subtext: Dark Slate (#4A5568)
  static const lightBackground = Color(0xFFC5D3C1);
  /// Default surface for cards, sheets, and panels.
  /// Requested: Warm Cream (#FBF9F4)
  static const lightSurface = Color(0xFFFBF9F4);

  /// Backwards-compatible alias (older call-sites reference this).
  static const lightWarmCreamSurface = lightSurface;

  /// Subtle warm tint for inputs / chips.
  /// Requested: #F2EFE9
  static const lightWarmCreamTint = Color(0xFFF2EFE9);
  static const lightOnSurface = Color(0xFF284236);
  static const lightOutline = Color(0xFF284236);

  // Primary is used for all primary buttons / CTAs across the app.
  // Requested: Terracotta Orange (#D94A1E)
  static const lightPrimary = Color(0xFFD94A1E);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFDCE8E1);
  static const lightOnPrimaryContainer = Color(0xFF284236);

  // Secondary is a muted structural tone
  static const lightSecondary = Color(0xFF284236);
  static const lightOnSecondary = Color(0xFFFFFFFF);

  // Tertiary maps to the main CTA / action accent
  /// Primary action / CTA.
  /// Requested: Terracotta Orange (#D94A1E)
  static const lightTertiary = Color(0xFFD94A1E);
  static const lightOnTertiary = Color(0xFFFFFFFF);

  // Error colors
  static const lightError = Color(0xFFBA1A1A);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFFDAD6);
  static const lightOnErrorContainer = Color(0xFF410002);

  // Variants (still within palette)
  static const lightSurfaceVariant = Color(0xFFF3F6F4);
  static const lightOnSurfaceVariant = Color(0xFF4A5568);

  // Shadow/inverse
  static const lightShadow = Color(0xFF000000);
  static const lightInversePrimary = Color(0xFFFFFFFF);
}

/// Dark mode colors with good contrast
class DarkModeColors {
  // For this rebrand we keep dark mode aligned with the same warm palette,
  // but with slightly deeper surfaces for comfort.
  static const darkBackground = Color(0xFF0F1714);
  static const darkSurface = Color(0xFF121C18);
  static const darkOnSurface = Color(0xFFEAF2ED);
  static const darkOutline = Color(0xFFEAF2ED);

  static const darkPrimary = Color(0xFFBFD3C9);
  static const darkOnPrimary = Color(0xFF0F1714);
  static const darkPrimaryContainer = Color(0xFF22352C);
  static const darkOnPrimaryContainer = Color(0xFFEAF2ED);

  static const darkSecondary = Color(0xFFBFD3C9);
  static const darkOnSecondary = Color(0xFF0F1714);

  static const darkTertiary = Color(0xFFD94A1E);
  static const darkOnTertiary = Color(0xFFFFFFFF);

  // Error colors
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF93000A);
  static const darkOnErrorContainer = Color(0xFFFFDAD6);

  static const darkSurfaceVariant = Color(0xFF18231F);
  static const darkOnSurfaceVariant = Color(0xFFB7C3BC);

  static const darkShadow = Color(0xFF000000);
  static const darkInversePrimary = Color(0xFFEAF2ED);
}

class AppSizing {
  static const double minTouchTarget = 48;
  static const double primaryButtonHeight = 56;

  /// Primary CTA padding.
  ///
  /// NOTE: This must always be a concrete EdgeInsets value (never nullable)
  /// to avoid web runtime errors where a button style attempts to read an
  /// undefined padding token.
  static const EdgeInsets primaryButtonPadding = EdgeInsets.symmetric(vertical: 16, horizontal: 24);

  /// Defensive fallback accessor for any call-sites that may migrate to a
  /// dynamic token source in the future.
  static EdgeInsets get primaryButtonPaddingOrFallback => primaryButtonPadding;
}

/// Font size constants
class FontSizes {
  static const double displayLarge = 57.0;
  static const double displayMedium = 45.0;
  static const double displaySmall = 36.0;
  static const double headlineLarge = 32.0;
  static const double headlineMedium = 28.0;
  static const double headlineSmall = 24.0;
  static const double titleLarge = 22.0;
  static const double titleMedium = 16.0;
  static const double titleSmall = 14.0;
  static const double labelLarge = 14.0;
  static const double labelMedium = 12.0;
  static const double labelSmall = 11.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
}

// =============================================================================
// THEMES
// =============================================================================

/// Light theme with modern, neutral aesthetic
ThemeData get lightTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.light(
    primary: LightModeColors.lightPrimary,
    onPrimary: LightModeColors.lightOnPrimary,
    primaryContainer: LightModeColors.lightPrimaryContainer,
    onPrimaryContainer: LightModeColors.lightOnPrimaryContainer,
    secondary: LightModeColors.lightSecondary,
    onSecondary: LightModeColors.lightOnSecondary,
    tertiary: LightModeColors.lightTertiary,
    onTertiary: LightModeColors.lightOnTertiary,
    error: LightModeColors.lightError,
    onError: LightModeColors.lightOnError,
    errorContainer: LightModeColors.lightErrorContainer,
    onErrorContainer: LightModeColors.lightOnErrorContainer,
    surface: LightModeColors.lightSurface,
    onSurface: LightModeColors.lightOnSurface,
    surfaceContainerHighest: LightModeColors.lightSurfaceVariant,
    onSurfaceVariant: LightModeColors.lightOnSurfaceVariant,
    outline: LightModeColors.lightOutline,
    shadow: LightModeColors.lightShadow,
    inversePrimary: LightModeColors.lightInversePrimary,
  ),
  brightness: Brightness.light,
  scaffoldBackgroundColor: LightModeColors.lightBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: LightModeColors.lightOnSurface,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: LightModeColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(
        color: LightModeColors.lightOutline.withValues(alpha: 0.12),
        width: 1,
      ),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: LightModeColors.lightTertiary,
      foregroundColor: LightModeColors.lightOnTertiary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: LightModeColors.lightTertiary,
      foregroundColor: LightModeColors.lightOnTertiary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(color: LightModeColors.lightPrimary.withValues(alpha: 0.55), width: 1.2),
      foregroundColor: LightModeColors.lightPrimary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(AppSizing.minTouchTarget, AppSizing.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
    ),
  ),
  textTheme: _buildTextTheme(Brightness.light),
);

/// Dark theme with good contrast and readability
ThemeData get darkTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: DarkModeColors.darkPrimary,
    onPrimary: DarkModeColors.darkOnPrimary,
    primaryContainer: DarkModeColors.darkPrimaryContainer,
    onPrimaryContainer: DarkModeColors.darkOnPrimaryContainer,
    secondary: DarkModeColors.darkSecondary,
    onSecondary: DarkModeColors.darkOnSecondary,
    tertiary: DarkModeColors.darkTertiary,
    onTertiary: DarkModeColors.darkOnTertiary,
    error: DarkModeColors.darkError,
    onError: DarkModeColors.darkOnError,
    errorContainer: DarkModeColors.darkErrorContainer,
    onErrorContainer: DarkModeColors.darkOnErrorContainer,
    surface: DarkModeColors.darkSurface,
    onSurface: DarkModeColors.darkOnSurface,
    surfaceContainerHighest: DarkModeColors.darkSurfaceVariant,
    onSurfaceVariant: DarkModeColors.darkOnSurfaceVariant,
    outline: DarkModeColors.darkOutline,
    shadow: DarkModeColors.darkShadow,
    inversePrimary: DarkModeColors.darkInversePrimary,
  ),
  brightness: Brightness.dark,
  scaffoldBackgroundColor: DarkModeColors.darkBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: DarkModeColors.darkOnSurface,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: DarkModeColors.darkSurface,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(
        color: DarkModeColors.darkOutline.withValues(alpha: 0.12),
        width: 1,
      ),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: DarkModeColors.darkTertiary,
      foregroundColor: DarkModeColors.darkOnTertiary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: DarkModeColors.darkTertiary,
      foregroundColor: DarkModeColors.darkOnTertiary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
      padding: AppSizing.primaryButtonPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(color: DarkModeColors.darkPrimary.withValues(alpha: 0.55), width: 1.2),
      foregroundColor: DarkModeColors.darkPrimary,
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(AppSizing.minTouchTarget, AppSizing.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
    ),
  ),
  textTheme: _buildTextTheme(Brightness.dark),
);

/// Build text theme using Inter font family
TextTheme _buildTextTheme(Brightness brightness) {
  return TextTheme(
      displayLarge: GoogleFonts.manrope(
        fontSize: FontSizes.displayLarge,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: FontSizes.displayMedium,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.manrope(
        fontSize: FontSizes.displaySmall,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: GoogleFonts.manrope(
        fontSize: FontSizes.headlineLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: FontSizes.headlineMedium,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: FontSizes.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: FontSizes.titleLarge,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: FontSizes.titleMedium,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: FontSizes.titleSmall,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: FontSizes.labelLarge,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: FontSizes.labelMedium,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: FontSizes.labelSmall,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: FontSizes.bodyLarge,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: FontSizes.bodyMedium,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: FontSizes.bodySmall,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
  );
}

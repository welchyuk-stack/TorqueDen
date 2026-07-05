import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette — straight from `TorqueDen-brand-and-theme.md`.
/// Dark-mode-first: Ember is the single hot accent, used sparingly.
class AppColors {
  AppColors._();

  static const carbon = Color(0xFF15171B); // deep ink — banners, scrims, nav
  static const background = Color(0xFF2A2F38); // app screen background (grey)
  static const graphite = Color(0xFF1C2026); // card surface
  static const graphiteRaised = Color(0xFF23272E); // elevated wells
  static const hairline = Color(0xFF2C313A); // borders / dividers
  static const ember = Color(0xFFFF6A2B); // primary accent, CTAs, "flame"
  static const emberHover = Color(0xFFF2581C); // accent hover / pressed
  static const onEmber = Color(0xFF2A0F04); // text / icons on ember fills
  static const steel = Color(0xFF7C8B99); // secondary accent, inactive
  static const cream = Color(0xFFF3ECE1); // primary text
  static const textSecondary = Color(0xFF9AA3AD);
  static const textMuted = Color(0xFF8A929C);
  static const success = Color(0xFF4FB477);
  static const warning = Color(0xFFE8A13A);
  static const danger = Color(0xFFE5484D);
}

/// The app-wide dark theme, derived from the brand guide.
ThemeData buildTorqueDenTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);

  // Inter for body/UI text, rendered in Cream over the dark canvas.
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: AppColors.cream,
    displayColor: AppColors.cream,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.ember,
      onPrimary: AppColors.onEmber,
      secondary: AppColors.steel,
      onSecondary: AppColors.carbon,
      surface: AppColors.graphite,
      onSurface: AppColors.cream,
      error: AppColors.danger,
      onError: AppColors.cream,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.archivo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.cream,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.graphiteRaised,
      hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
      labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15),
      floatingLabelStyle: GoogleFonts.inter(color: AppColors.ember, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.steel,
      textColor: AppColors.cream,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: AppColors.carbon,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.ember.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: selected ? AppColors.cream : AppColors.steel,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? AppColors.ember : AppColors.steel,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.graphiteRaised,
      contentTextStyle: GoogleFonts.inter(color: AppColors.cream),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ember,
        foregroundColor: AppColors.onEmber,
        disabledBackgroundColor: AppColors.hairline,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

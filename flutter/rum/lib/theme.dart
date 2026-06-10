import 'package:flutter/material.dart';

/// Shared design tokens for the Last9 RUM Flutter example.
///
/// Mirrors the visual language of the reference RUM demo: a soft grey
/// scaffold, an accent purple, and white cards with thin grey borders.
class AppColors {
  AppColors._();

  static const Color accent = Color(0xFF6C63FF);
  static const Color scaffold = Color(0xFFF8F9FA);
  static const Color cardBorder = Color(0xFFEEEEEE);
  static const Color featureBg = Color(0xFFF0EFFF);

  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF555555);
  static const Color textMuted = Color(0xFF888888);

  static const Color ok = Color(0xFF00B894);
  static const Color error = Color(0xFFFF6B6B);
  static const Color neutral = Color(0xFF636E72);
}

class AppText {
  AppText._();

  static const TextStyle appBarTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle hint = TextStyle(
    fontSize: 12,
    height: 1.5,
    color: AppColors.textMuted,
  );
}

/// Builds the [ThemeData] for the example app.
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.scaffold,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: AppText.appBarTitle,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
  );
}

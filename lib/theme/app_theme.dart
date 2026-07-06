import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFC51F45);
  static const primaryDark = Color(0xFF8F1430);
  static const secondary = Color(0xFF007C89);
  static const success = Color(0xFF188A5A);
  static const warning = Color(0xFFC77700);
  static const danger = Color(0xFFBA1A1A);
  static const surface = Color(0xFFFFFBFB);
  static const surfaceAlt = Color(0xFFF7F1F2);
  static const recessedPane = Colors.white;
  static const recessedPaneBorder = Color(0xFFDDD2D5);
  static const outline = Color(0xFFD9C8CD);
  static const ink = Color(0xFF21191B);
}

class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFD9E1),
      onPrimaryContainer: const Color(0xFF3F0012),
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFCDEFF2),
      onSecondaryContainer: const Color(0xFF002023),
      tertiary: AppColors.warning,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFE0B8),
      onTertiaryContainer: const Color(0xFF2A1700),
      error: AppColors.danger,
      surface: AppColors.surface,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFFFBFB),
      surfaceContainer: const Color(0xFFFCF6F7),
      surfaceContainerHigh: AppColors.surfaceAlt,
      surfaceContainerHighest: const Color(0xFFEDE1E4),
      outline: AppColors.outline,
      onSurface: AppColors.ink,
      onSurfaceVariant: const Color(0xFF5C4A4F),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        elevation: 1,
        shadowColor: AppColors.primaryDark.withValues(alpha: 0.12),
        surfaceTintColor: colorScheme.primary.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: colorScheme.secondaryContainer,
        checkmarkColor: colorScheme.onSecondaryContainer,
        side: BorderSide(color: colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFC51F45);
  static const primaryDark = Color(0xFF8F1430);
  static const secondary = Color(0xFF45515D);
  static const success = Color(0xFF188A5A);
  static const warning = Color(0xFFC77700);
  static const danger = Color(0xFFBA1A1A);
  static const surface = Color(0xFFF7F8FA);
  static const surfaceAlt = Color(0xFFF0F2F4);
  static const recessedPane = Color(0xFFFFFFFF);
  static const recessedPaneBorder = Color(0xFFD8DCE1);
  static const outline = Color(0xFFC7CDD4);
  static const ink = Color(0xFF20252B);
}

class AppTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFF9D9E0),
          onPrimaryContainer: const Color(0xFF470013),
          secondary: AppColors.secondary,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFE3E8EC),
          onSecondaryContainer: const Color(0xFF17212B),
          tertiary: AppColors.warning,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFFFE0B8),
          onTertiaryContainer: const Color(0xFF2A1700),
          error: AppColors.danger,
          surface: AppColors.surface,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF7F8FA),
          surfaceContainer: const Color(0xFFF3F5F7),
          surfaceContainerHigh: AppColors.surfaceAlt,
          surfaceContainerHighest: const Color(0xFFE8EBEE),
          outline: AppColors.outline,
          onSurface: AppColors.ink,
          onSurfaceVariant: const Color(0xFF59636E),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        elevation: 1,
        shadowColor: AppColors.primaryDark.withValues(alpha: 0.12),
        surfaceTintColor: colorScheme.primary.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 40),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

import 'package:flutter/material.dart';

class AppTheme {
  // Silent Obsidian & Amber Gold Brand Colors
  static const Color obsidianBg = Color(0xFF0D0F12);
  static const Color slateCard = Color(0xFF161A22);
  static const Color slateCardLight = Color(0xFF202632);
  static const Color borderSubtle = Color(0xFF262B36);
  static const Color amberGold = Color(0xFFE0A96D);
  static const Color amberGoldLight = Color(0xFFF3C088);
  static const Color amberGoldDark = Color(0xFFC5894B);

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F3F7);
  static const Color textSecondary = Color(0xFF8A91A0);
  static const Color textMuted = Color(0xFF5A6273);

  // Light Mode Colors (Warm Linen / Paper)
  static const Color paperLinenBg = Color(0xFFF8F6F0);
  static const Color paperCard = Color(0xFFFFFFFF);
  static const Color inkText = Color(0xFF1E2024);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: obsidianBg,
      primaryColor: amberGold,
      colorScheme: const ColorScheme.dark(
        primary: amberGold,
        secondary: amberGoldLight,
        surface: slateCard,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: obsidianBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: amberGold),
      ),
      cardTheme: CardThemeData(
        color: slateCard,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: amberGold,
        inactiveTrackColor: slateCardLight,
        thumbColor: Colors.white,
        overlayColor: amberGold.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amberGold,
          foregroundColor: obsidianBg,
          elevation: 4,
          shadowColor: amberGold.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

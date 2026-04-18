import 'package:flutter/material.dart';

/// Premium dark theme — true black background with clean white/accent palette.
/// Inspired by dialed.gg's minimal, high-contrast aesthetic.
class AppTheme {
  // ── Core palette ──
  static const Color bg = Color(0xFF000000);           // true black
  static const Color surface = Color(0xFF111111);       // near black
  static const Color surfaceAlt = Color(0xFF1A1A1A);   // card/elevated
  static const Color border = Color(0xFF2A2A2A);        // subtle borders
  static const Color borderLight = Color(0xFF333333);   // hover borders
  static const Color textPrimary = Color(0xFFF5F5F5);   // white-ish
  static const Color textSecondary = Color(0xFF999999);  // muted
  static const Color accent = Color(0xFFFFFFFF);         // white accent
  static const Color accentSoft = Color(0xFFCCCCCC);     // soft white

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: Color(0xFF000000),
      secondary: Color(0xFF888888),
      onSecondary: Color(0xFFFFFFFF),
      tertiary: Color(0xFFFF6B6B),
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceAlt,
      outline: border,
      error: Color(0xFFFF4444),
      onError: Colors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceAlt,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 0.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: const Color(0x22FFFFFF),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: 0.3,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: textSecondary,
            letterSpacing: 0.3,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: textPrimary, size: 22);
          }
          return const IconThemeData(color: textSecondary, size: 22);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: const Color(0xFF2A2A2A),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 0.5,
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 32,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
          color: textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.5,
          color: accentSoft,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
    );
  }
}

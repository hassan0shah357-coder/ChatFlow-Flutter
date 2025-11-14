import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF6750A4);
  static const Color primaryVariant = Color.fromARGB(255, 139, 58, 200);
  static const Color secondaryColor = Color(0xFF625B71);
  static const Color lightBackground = Color(0xFFFFFBFE);
  static const Color lightSurface = Color(0xFFF7F2FA);
  static const Color lightSurfaceVariant = Color(0xFFE7E0EC);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1C1B1F);
  static const Color lightOutline = Color(0xFF79747E);
  static const Color lightError = Color(0xFFBA1A1A);
  static const Color darkBackground = Color(0xff131313);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF49454F);
  static const Color darkOnPrimary = Color(0xFF1C1B1F);
  static const Color darkOnSurface = Color(0xFFE6E1E5);
  static const Color darkOutline = Color(0xFF938F99);
  static const Color darkError = Color(0xFFFFB4AB);
  ThemeData get themeLight => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primaryVariant,
      onPrimary: lightOnPrimary,
      secondary: secondaryColor,
      onSecondary: lightOnPrimary,
      error: lightError,
      onError: lightOnPrimary,
      surface: lightSurface,
      onSurface: lightOnSurface,
      surfaceContainerHighest: lightSurfaceVariant,
      outline: lightOutline,
    ),
    scaffoldBackgroundColor: lightBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBackground,
      foregroundColor: lightOnSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: primaryColor,
      titleTextStyle: TextStyle(
        color: lightOnSurface,
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      iconTheme: IconThemeData(color: lightOnSurface),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      selectedItemColor: primaryColor,
      unselectedItemColor: lightOutline,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: lightOnPrimary,
      elevation: 6,
      shape: CircleBorder(),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      tileColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: const TextStyle(color: lightOutline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: lightOnSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: lightOnSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: lightOnSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: lightOnSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: lightOnSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: lightOnSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: lightOutline,
      ),
    ),

    // Divider Theme
    dividerTheme: const DividerThemeData(
      color: lightOutline,
      thickness: 0.5,
      space: 1,
    ),

    // Icon Theme
    iconTheme: const IconThemeData(color: lightOnSurface, size: 24),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: lightOnPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
  );

  // Dark Theme
  ThemeData get themeDark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Color Scheme
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: primaryVariant,
      onPrimary: darkOnPrimary,
      secondary: secondaryColor,
      onSecondary: darkOnSurface,
      error: darkError,
      onError: darkOnPrimary,
      surface: darkSurface,
      onSurface: darkOnSurface,
      surfaceContainerHighest: darkSurfaceVariant,
      outline: darkOutline,
    ),

    // Scaffold
    scaffoldBackgroundColor: darkBackground,

    // AppBar Theme
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkOnSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: primaryVariant,
      titleTextStyle: TextStyle(
        color: darkOnSurface,
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      iconTheme: IconThemeData(color: darkOnSurface),
    ),

    // Bottom Navigation Bar Theme
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: primaryVariant,
      unselectedItemColor: darkOutline,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),

    // Floating Action Button Theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryVariant,
      foregroundColor: darkOnPrimary,
      elevation: 6,
      shape: CircleBorder(),
    ),

    // List Tile Theme
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      tileColor: Colors.transparent,
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: primaryVariant, width: 2),
      ),
      hintStyle: const TextStyle(color: darkOutline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),

    // Text Theme
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: darkOnSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: darkOnSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: darkOnSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: darkOnSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: darkOnSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: darkOnSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: darkOutline,
      ),
    ),

    // Divider Theme
    dividerTheme: const DividerThemeData(
      color: darkOutline,
      thickness: 0.5,
      space: 1,
    ),

    // Icon Theme
    iconTheme: const IconThemeData(color: darkOnSurface, size: 24),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryVariant,
        foregroundColor: darkOnPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
  );

  // Static getter for easy access
  static AppTheme get instance => AppTheme();
}

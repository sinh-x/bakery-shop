import 'package:flutter/material.dart';

class BakeryTheme {
  static const _seedColor = Color(0xFFD4841F); // Warm bakery orange

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: colorScheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // Status badge colors
  static const statusColors = {
    'new': Color(0xFF2196F3),
    'confirmed': Color(0xFF3F51B5),
    'in_progress': Color(0xFFFF9800),
    'ready': Color(0xFF4CAF50),
    'delivered': Color(0xFF009688),
    'completed': Color(0xFF9E9E9E),
    'cancelled': Color(0xFFF44336),
  };

  // Status icons
  static const statusIcons = {
    'new': Icons.fiber_new,
    'confirmed': Icons.check_circle_outline,
    'in_progress': Icons.autorenew,
    'ready': Icons.done,
    'delivered': Icons.local_shipping,
    'completed': Icons.done_all,
    'cancelled': Icons.cancel,
  };
}

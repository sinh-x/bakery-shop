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

  // Status badge colors (single source of truth — all screens reference this)
  static const statusColors = {
    'new': Color(0xFF2196F3),          // Blue
    'confirmed': Color(0xFFFF9800),    // Orange (aligns with order list view)
    'in_progress': Color(0xFF9C27B0),  // Purple
    'ready': Color(0xFF4CAF50),        // Green
    'delivered': Color(0xFF009688),    // Teal
    'completed': Color(0xFF9E9E9E),    // Grey
    'cancelled': Color(0xFFF44336),    // Red
    'to_deliver': Color(0xFFFF5722),   // Deep Orange
    'awaiting_payment': Color(0xFFE91E63), // Pink
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

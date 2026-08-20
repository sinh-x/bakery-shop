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
      splashFactory: InkRipple.splashFactory,
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

  // Work item status colors (cake queue items: pending/confirmed/working/ready/delivered)
  //
  // NOTE: This is an intentional 5-status subset of the full 6-status
  // `workItemStatusColors` map in `app/lib/shared/utils.dart:121`
  // (pending/confirmed/working/ready/delivered/cancelled). It mirrors the
  // shared map for the states it lists and intentionally omits only
  // `cancelled` (a terminal state never displayed in the cake queue). The
  // backend default cake-queue filter (`src/baker/api/cake_queue.py:53`)
  // includes `pending/confirmed/working` (plus `ready` when `include_ready`),
  // so `confirmed` items do appear in the cake queue and need a color here.
  // This narrower map must NOT be consolidated into the shared one. Do not
  // re-flag this as a duplication in future code-quality reviews.
  static const workItemStatusColors = {
    'pending': Colors.grey,
    'confirmed': Colors.blue,
    'working': Colors.orange,
    'ready': Colors.green,
    'delivered': Colors.teal,
  };

  // Urgency tier colors (FR-3: critical=red, urgent=amber)
  static const urgencyTierColors = {
    'critical': Color(0xFFD32F2F),  // Red
    'urgent': Color(0xFFFFA000),    // Amber
  };

  // Critical in-app alert overlay colors (DG-309: dark red bg + amber fg)
  // Darker red (#B71C1C) and lighter amber (#FFC107) chosen over the tier
  // defaults to maximize contrast while staying within the critical-urgency
  // red family. Contrast ratio is 4.03:1 — meets WCAG AA for large text
  // (requires >= 3:1) but falls short of AA for normal text (requires 4.5:1).
  // Acceptable for a transient 6-second alert. Theme-independent — hardcoded by design.
  static const criticalAlertBackground = Color(0xFFB71C1C); // Dark red
  static const criticalAlertForeground = Color(0xFFFFC107); // Amber

  // Completeness tier colors (DG-241 Phase 2)
  static const completenessTierColors = {
    'incomplete': Color(0xFFFFA000),  // Amber — distinct from urgency red
  };

  // Completeness tier icons (DG-241 Phase 2)
  static const completenessTierIcons = {
    'incomplete': Icons.warning_amber_rounded,
  };

  // Urgency tier icons (FR-3)
  static const urgencyTierIcons = {
    'critical': Icons.error_outline,
    'urgent': Icons.warning_amber_rounded,
    'normal': null,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../labels/orders.dart';

/// Displays an in-app alert overlay with a system sound and haptic feedback.
///
/// Used to notify staff when polling detects a newly-appeared critical order.
/// The alert shows as a top overlay with critical order info, plays a built-in
/// system notification sound, and triggers haptic feedback.
///
/// Sound and haptic are best-effort — degrade gracefully on platforms/browsers
/// that do not support them (NFR-5).
class InAppAlert {
  /// Shows the critical-order alert overlay.
  ///
  /// [count] is the number of new critical orders detected in this batch.
  /// Returns immediately — the caller does not need to await.
  static void show({
    required BuildContext context,
    required int count,
    VoidCallback? onDismiss,
  }) {
    _playAlertSound();
    _triggerHaptic();

    _showOverlay(context, count, onDismiss);
  }

  static void _playAlertSound() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Graceful degradation on web (NFR-5).
    }
  }

  static void _triggerHaptic() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {
      // Graceful degradation on web (NFR-5).
    }
  }

  static void _showOverlay(BuildContext context, int count, VoidCallback? onDismiss) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(ctx).colorScheme.errorContainer,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              entry.remove();
              onDismiss?.call();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          OrdersLabels.criticalAlertTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          OrdersLabels.criticalAlertBody(count),
                          style: TextStyle(
                            color: Colors.white.withAlpha(220),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      entry.remove();
                      onDismiss?.call();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(OrdersLabels.criticalAlertDismiss),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 6), () {
      if (entry.mounted) {
        entry.remove();
        onDismiss?.call();
      }
    });
  }
}

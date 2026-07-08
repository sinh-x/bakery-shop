import 'package:flutter/material.dart';

/// Determines the target stage (1-based) for a horizontal swipe gesture.
///
/// Returns the next stage in the swipe direction, or `null` when the swipe
/// is too small or would move past the first/last page.
///
/// Sign convention:
///   - drag left  (next page) → negative primary velocity
///   - drag right (previous page) → positive primary velocity
int? targetStageForSwipe({
  required Velocity velocity,
  required int currentStage,
  required int pageCount,
  double minVelocity = 200,
}) {
  final v = velocity.pixelsPerSecond.dx;
  if (v.abs() < minVelocity) return null;
  final target = v < 0 ? currentStage + 1 : currentStage - 1;
  if (target < 1 || target > pageCount) return null;
  return target;
}
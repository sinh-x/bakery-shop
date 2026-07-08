import 'package:flutter/material.dart';

/// Threshold width (in dp) above which the layout is considered a tablet and
/// the Stage 1 content is constrained to a centered max-width band
/// (DG-214 Phase 6, NFR-1).
const double _kTabletBreakpoint = 600;

/// Max content width (in dp) used on tablet layouts so the selected-items list
/// and extras section remain readable instead of stretching edge-to-edge
/// (DG-214 Phase 6, NFR-1).
const double _kStage1MaxContentWidth = 720;

/// Wraps [child] in a responsive container that, on tablet widths
/// (`>= _kTabletBreakpoint`), centers the content within a bounded band so it
/// does not stretch edge-to-edge. On phone widths the child fills the width.
///
/// Used by Stage 1 (DG-214 Phase 6, NFR-1) to keep the selected-items list and
/// extras section readable on tablets.
class Stage1ResponsiveContent extends StatelessWidget {
  const Stage1ResponsiveContent({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < _kTabletBreakpoint) {
      return child;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _kStage1MaxContentWidth,
        ),
        child: child,
      ),
    );
  }
}

/// Whether the current [BuildContext] width is at least the tablet breakpoint.
bool isTabletWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= _kTabletBreakpoint;
import 'package:flutter/material.dart';

/// A single tappable cell in the category icon picker grid.
///
/// Renders [child] centered inside an [AnimatedContainer] that highlights
/// when [selected] (primary-container background, primary border).
///
/// Extracted from `category_form.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class IconCell extends StatelessWidget {
  const IconCell({
    super.key,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
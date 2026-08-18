import 'package:flutter/material.dart';

/// A label-value row used in the blank detail screen header.
///
/// Renders a fixed-width [label] (grey) followed by an [Expanded] value.
/// Empty values display an em dash. Extracted from
/// `blank_detail_screen.dart` per §2 of `docs/flutter-coding-standards.md`.
class BlankFieldRow extends StatelessWidget {
  const BlankFieldRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
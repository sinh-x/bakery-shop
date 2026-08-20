import 'package:flutter/material.dart';

/// A label-value row for a single demand metric on the blank detail screen.
///
/// When [emphasize] is true the value is rendered in bold red (used for a
/// positive shortage). Extracted from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DemandRow extends StatelessWidget {
  const DemandRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: style?.copyWith(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: emphasize
                  ? style?.copyWith(color: Colors.red, fontWeight: FontWeight.bold)
                  : style,
            ),
          ),
        ],
      ),
    );
  }
}
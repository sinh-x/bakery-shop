import 'package:flutter/material.dart';

/// Shared empty-state widget for accounting tabs.
///
/// Extracted from accounts_tab.dart, balances_tab.dart, and journal_tab.dart
/// to avoid duplicated `_EmptyState`/`_EmptyList` widgets (DG-175 review cycle
/// 1, finding CQ-3).
class AccountingEmptyState extends StatelessWidget {
  const AccountingEmptyState({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ),
      ],
    );
  }
}
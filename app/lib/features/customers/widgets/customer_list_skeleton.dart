import 'package:flutter/material.dart';

/// Loading skeleton shown while the first customer page loads (DG-409
/// Phase 4 / loading indicators). Renders placeholder tiles so the screen
/// doesn't flash empty before data arrives.
///
/// Extracted from `customer_list_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CustomerListSkeleton extends StatelessWidget {
  const CustomerListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, _) => const ListTile(
        leading: CircleAvatar(child: SizedBox.shrink()),
        title: SizedBox(
          height: 16,
          child: LinearProgressIndicator(),
        ),
        subtitle: SizedBox(height: 12, child: LinearProgressIndicator()),
      ),
    );
  }
}
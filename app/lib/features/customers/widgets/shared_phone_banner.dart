import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/customers.dart';

import '../../../data/models/customer.dart';

/// Surfaces other customers sharing the same phone number (FR2a/AC6/AC8).
///
/// Extracted from `customer_form.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class SharedPhoneBanner extends StatelessWidget {
  const SharedPhoneBanner({super.key, required this.customers});

  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Text(
                CustomersLabels.customerSharedPhoneTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            CustomersLabels.customerSharedPhoneHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in customers)
                Chip(
                  label: Text(c.name),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
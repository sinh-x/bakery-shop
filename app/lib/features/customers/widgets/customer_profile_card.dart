import 'package:flutter/material.dart';

import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';

/// Shared customer profile card used across order detail, create, and edit
/// screens (DG-206 FR1/FR8).
///
/// Displays the customer's avatar (first letter), name, all phone numbers
/// (multi-phone with primary star), and — in [CustomerProfileCardMode.full]
/// mode — the per-year order count from `yearSummary` and created date.
///
/// Pass [onTap] to make the card tappable (typically navigating to
/// `/customers/:id`). Use [mode] to switch between:
/// - [CustomerProfileCardMode.full] — order detail: avatar, name, all
///   phones, order count, created date. Uses standard card margins.
/// - [CustomerProfileCardMode.compact] — order create/edit: avatar, name,
///   primary phone only. Tighter padding for inline display below a search
///   field.
class CustomerProfileCard extends StatelessWidget {
  const CustomerProfileCard({
    super.key,
    required this.customer,
    this.onTap,
    this.mode = CustomerProfileCardMode.full,
  });

  final Customer customer;

  /// Called when the card is tapped. When null the card is non-interactive.
  final VoidCallback? onTap;

  /// Display density: `full` for order detail, `compact` for create/edit.
  final CustomerProfileCardMode mode;

  /// Returns the primary phone number, preferring the primary entry in
  /// [Customer.phones] and falling back to the legacy denormalized
  /// [Customer.phone] for backward compatibility with pre-v58 data.
  String get _primaryPhone {
    if (customer.phones.isEmpty) return customer.phone;
    final primary = customer.phones.firstWhere(
      (p) => p.isPrimary,
      orElse: () => customer.phones.first,
    );
    return primary.phone;
  }

  /// Builds one line per phone number for [CustomerProfileCardMode.full].
  ///
  /// The primary phone is highlighted with a filled star icon and bold text
  /// suffixed with `(Số chính)`; secondary phones use a star border icon and
  /// regular weight. Falls back to the legacy [Customer.phone] when the
  /// `phones` list is empty (pre-v58 data).
  List<Widget> _buildPhoneLines(ThemeData theme) {
    final phones = customer.phones;
    if (phones.isEmpty) {
      if (customer.phone.isEmpty) return const [];
      return [
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.star, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                customer.phone,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ];
    }
    return [
      for (final entry in phones) ...[
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              entry.isPrimary ? Icons.star : Icons.star_border,
              size: 16,
              color: entry.isPrimary ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${entry.phone}${entry.isPrimary ? ' (${VN.customerPrimaryPhone})' : ''}',
                style: entry.isPrimary
                    ? theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _buildAvatar(ThemeData theme) {
    final display = customer.name.isEmpty
        ? CustomersLabels.customerNoName[0]
        : customer.name[0];
    return CircleAvatar(
      radius: mode == CustomerProfileCardMode.full ? 28 : 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Text(
        display,
        style: TextStyle(
          fontSize: mode == CustomerProfileCardMode.full ? 22 : 16,
        ),
      ),
    );
  }

  Widget _buildOrderCountLine(ThemeData theme) {
    final summary = customer.yearSummary;
    final count = summary?.orderCount ?? 0;
    return Text(
      '$count ${CustomersLabels.orderCountThisYearSuffix}',
      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = mode == CustomerProfileCardMode.full;

    final card = Card(
      margin: isFull ? const EdgeInsets.all(16) : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: isFull ? const EdgeInsets.all(16) : const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildAvatar(theme),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name, style: theme.textTheme.titleMedium),
                  if (isFull) ..._buildPhoneLines(theme) else if (_primaryPhone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_primaryPhone, style: theme.textTheme.bodyMedium),
                  ],
                  if (isFull) ...[
                    const SizedBox(height: 4),
                    _buildOrderCountLine(theme),
                    const SizedBox(height: 2),
                    Text(
                      '${VN.customerCreatedAt}: ${formatDisplayDate(customer.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(onTap: onTap, child: card);
  }
}

/// Display density modes for [CustomerProfileCard].
enum CustomerProfileCardMode {
  /// Order detail: avatar, name, all phones, order count, created date.
  full,

  /// Order create/edit: avatar, name, primary phone only. Tighter padding.
  compact,
}
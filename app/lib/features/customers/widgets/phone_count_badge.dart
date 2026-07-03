import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/customers.dart';

/// Small badge displayed on a customer [CircleAvatar] when the customer has
/// more than one phone number (DG-206 FR4/AC4).
///
/// Renders as a circular badge at the bottom-right of the avatar showing
/// "+N" where N is the number of *additional* phones (total - 1). Hidden when
/// [phoneCount] <= 1.
///
/// Usage:
/// ```dart
/// Stack(
///   alignment: Alignment.bottomRight,
///   children: [
///     CircleAvatar(child: Text(customer.name[0])),
///     PhoneCountBadge(phoneCount: customer.phones.length),
///   ],
/// )
/// ```
class PhoneCountBadge extends StatelessWidget {
  const PhoneCountBadge({super.key, required this.phoneCount});

  /// Total number of phones the customer has. The badge shows
  /// `phoneCount - 1` as the "+N" value. When <= 1 the badge renders nothing.
  final int phoneCount;

  @override
  Widget build(BuildContext context) {
    if (phoneCount <= 1) return const SizedBox.shrink();

    final extra = phoneCount - 1;
    final theme = Theme.of(context);
    return Tooltip(
      message: CustomersLabels.phoneCountBadgeTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.surface,
            width: 1.5,
          ),
        ),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
        child: Text(
          '+$extra',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
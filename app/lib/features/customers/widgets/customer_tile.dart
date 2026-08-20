import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/customer.dart';
import '../../../shared/utils/date_formatting.dart';
import 'phone_count_badge.dart';

/// A single customer row in the customer list.
///
/// Shows the customer avatar (first letter of the name) with a
/// [PhoneCountBadge] when the customer has multiple phones, the name, and a
/// subtitle joining the primary phone and the formatted creation date.
/// Tapping the row navigates to `/customers/<id>`.
///
/// Extracted from `customer_list_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.customer});

  final Customer customer;

  /// Returns the primary phone number to display in the tile subtitle.
  ///
  /// Prefers the primary entry in [Customer.phones] (multi-phone support,
  /// DG-205 Phase 6); falls back to the legacy denormalized [Customer.phone]
  /// for backward compatibility with pre-v58 data or older API responses.
  String get _primaryPhone {
    if (customer.phones.isEmpty) return customer.phone;
    final primary = customer.phones.firstWhere(
      (p) => p.isPrimary,
      orElse: () => customer.phones.first,
    );
    return primary.phone;
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (_primaryPhone.isNotEmpty) _primaryPhone,
      formatDisplayDate(customer.createdAt),
    ];
    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            child: Text(customer.name.isEmpty ? '?' : customer.name[0]),
          ),
          PhoneCountBadge(phoneCount: customer.phones.length),
        ],
      ),
      title: Text(customer.name),
      subtitle: Text(subtitleParts.join(' • ')),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}
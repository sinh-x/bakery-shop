import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/customer.dart';
import '../../../providers/customers_provider.dart';
import '../../../shared/utils/phone_formatter.dart';
import '../../customers/widgets/customer_profile_card.dart';
import '../../customers/widgets/customer_search_field.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class OrderCustomerSection extends ConsumerWidget {
  const OrderCustomerSection({
    super.key,
    this.linkedCustomerId,
    this.selectedCustomer,
    this.customerTouched = false,
    this.onSelected,
    this.onClearSelection,
    this.nameCtrl,
    this.phoneCtrl,
    this.mode = OrderCustomerSectionMode.editable,
    this.customerName,
    this.customerPhone,
  });

  final int? linkedCustomerId;
  final Customer? selectedCustomer;
  final bool customerTouched;
  final ValueChanged<Customer?>? onSelected;
  final VoidCallback? onClearSelection;
  final TextEditingController? nameCtrl;
  final TextEditingController? phoneCtrl;
  final OrderCustomerSectionMode mode;
  final String? customerName;
  final String? customerPhone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = selectedCustomer ??
        (customerTouched || linkedCustomerId == null
            ? null
            : ref.watch(customerProvider(linkedCustomerId!)).value);

    if (mode == OrderCustomerSectionMode.readOnly) {
      return _buildReadOnly(context, customer);
    }

    return _buildEditable(context, ref, customer);
  }

  Widget _buildReadOnly(BuildContext context, Customer? customer) {
    if (customer != null) {
      return CustomerProfileCard(
        customer: customer,
        mode: CustomerProfileCardMode.compact,
        onTap: () => context.push('/customers/${customer.id}'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (customerName != null && customerName!.isNotEmpty)
          _buildInfoRow(context, Icons.person_outline, VN.customerName, customerName!),
        if (customerPhone != null && customerPhone!.isNotEmpty)
          _buildInfoRow(context, Icons.phone_outlined, VN.customerPhone, customerPhone!),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildEditable(BuildContext context, WidgetRef ref, Customer? customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomerSearchField(
          initialCustomer: customer,
          onSelected: onSelected,
        ),
        if (customer != null) ...[
          const SizedBox(height: 8),
          CustomerProfileCard(
            customer: customer,
            mode: CustomerProfileCardMode.compact,
            onTap: () => context.push('/customers/${customer.id}'),
          ),
        ],
        if (nameCtrl != null && phoneCtrl != null) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: VN.customerName,
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
            onChanged: (_) => onClearSelection?.call(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phoneCtrl,
            decoration: const InputDecoration(
              labelText: VN.customerPhone,
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
          ),
        ],
      ],
    );
  }
}

enum OrderCustomerSectionMode { editable, readOnly }

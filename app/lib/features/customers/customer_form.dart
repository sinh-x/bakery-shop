import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/customer.dart';
import '../../providers/customers_provider.dart';
import 'package:bakery_app/shared/labels/customers.dart';

/// Show the add/edit customer bottom sheet.
///
/// Pass [customer] for edit mode; omit for add mode. Returns `true` when the
/// mutation succeeded so callers can refresh their list.
Future<bool?> showCustomerForm(
  BuildContext context, {
  Customer? customer,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _CustomerForm(customer: customer),
  );
}

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;
  List<Customer> _sharedPhone = const [];

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    // Pre-fill shared-phone list with whatever the existing customer already
    // had surfaced (only meaningful in edit mode with a known phone).
    _sharedPhone = const [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _sharedPhone = const [];
    });
    final service = ref.read(customerServiceProvider);
    try {
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final CustomerMutationResult result;
      if (_isEditing) {
        result = await service.updateCustomer(
          widget.customer!.id,
          name: name,
          phone: phone,
        );
      } else {
        result = await service.createCustomer(name: name, phone: phone);
      }
      if (!mounted) return;
      setState(() => _sharedPhone = result.sharedPhoneCustomers);
      // Invalidate the customer list so the parent screen refreshes.
      ref.invalidate(customerListProvider);
      if (_isEditing) {
        ref.invalidate(customerProvider(widget.customer!.id));
      }
      showTopSnackBar(
        context,
        _isEditing ? VN.customerUpdated : VN.customerCreated,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? VN.editCustomer : VN.addCustomer,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: VN.customerNameField,
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(20),
                ],
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: VN.customerPhoneField,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_sharedPhone.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SharedPhoneBanner(customers: _sharedPhone),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text(VN.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(VN.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Surfaces other customers sharing the same phone number (FR2a/AC6/AC8).
class _SharedPhoneBanner extends StatelessWidget {
  const _SharedPhoneBanner({required this.customers});

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
                VN.customerSharedPhoneTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            VN.customerSharedPhoneHint,
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
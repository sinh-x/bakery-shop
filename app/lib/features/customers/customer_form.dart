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

/// A single editable phone row (controller + primary flag).
class _PhoneEntry {
  _PhoneEntry({required this.controller, this.isPrimary = false});

  final TextEditingController controller;
  bool isPrimary;

  void dispose() => controller.dispose();
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
  final List<_PhoneEntry> _phones = [];
  bool _saving = false;
  List<Customer> _sharedPhone = const [];

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    // Pre-populate phone fields from customer.phones (multi-phone). Falls back
    // to the legacy single `phone` field when the API returns no phones list,
    // keeping backward compatibility for customers created before v58.
    final phones = c?.phones ?? const <CustomerPhone>[];
    if (phones.isNotEmpty) {
      for (final p in phones) {
        _phones.add(
          _PhoneEntry(
            controller: TextEditingController(text: p.phone),
            isPrimary: p.isPrimary,
          ),
        );
      }
    } else {
      final legacy = c?.phone ?? '';
      _phones.add(
        _PhoneEntry(
          controller: TextEditingController(text: legacy),
          isPrimary: legacy.isNotEmpty,
        ),
      );
    }
    // Ensure at least one entry is marked primary if any phone is non-empty.
    if (!_phones.any((e) => e.isPrimary)) {
      _phones.first.isPrimary = true;
    }
    _sharedPhone = const [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final entry in _phones) {
      entry.dispose();
    }
    super.dispose();
  }

  void _addPhone() {
    setState(() {
      _phones.add(_PhoneEntry(controller: TextEditingController()));
    });
  }

  void _removePhone(int index) {
    if (_phones.length <= 1) return;
    final wasPrimary = _phones[index].isPrimary;
    setState(() {
      _phones[index].dispose();
      _phones.removeAt(index);
      // If the removed entry was primary, reassign to the first remaining row.
      if (wasPrimary && _phones.isNotEmpty) {
        _phones.first.isPrimary = true;
      }
    });
  }

  void _setPrimary(int index) {
    setState(() {
      for (var i = 0; i < _phones.length; i++) {
        _phones[i].isPrimary = i == index;
      }
    });
  }

  /// Collect validated, trimmed phones for submission. Returns null when the
  /// form-level phone validation fails. When duplicates are detected, sets
  /// [_duplicateError] so [_save] can surface the VN label to the user.
  String? _duplicateError;

  List<CustomerPhone>? _collectPhones() {
    // Require at least one non-empty phone.
    final trimmed = _phones
        .map((e) => e.controller.text.trim())
        .toList(growable: false);
    final hasAny = trimmed.any((p) => p.isNotEmpty);
    if (!hasAny) {
      _duplicateError = null;
      return null;
    }
    // Detect duplicate non-empty phone numbers.
    final seen = <String>{};
    for (final phone in trimmed) {
      if (phone.isEmpty) continue;
      if (!seen.add(phone)) {
        _duplicateError = VN.customerPhoneDuplicate;
        return null;
      }
    }
    _duplicateError = null;
    // Require exactly one primary among the non-empty phones; ensure one is
    // selected automatically if none is.
    if (!_phones.any((e) => e.isPrimary && e.controller.text.trim().isNotEmpty)) {
      // Auto-pick the first non-empty entry as primary before sending.
      final firstNonEmptyIdx = _phones.indexWhere(
        (e) => e.controller.text.trim().isNotEmpty,
      );
      if (firstNonEmptyIdx < 0) return null;
      _setPrimary(firstNonEmptyIdx);
    }
    final out = <CustomerPhone>[];
    for (var i = 0; i < _phones.length; i++) {
      final phone = trimmed[i];
      if (phone.isEmpty) continue;
      out.add(CustomerPhone(phone: phone, isPrimary: _phones[i].isPrimary));
    }
    return out;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final phones = _collectPhones();
    if (phones == null) {
      showTopSnackBar(
        context,
        _duplicateError ?? VN.customerPhoneRequired,
      );
      return;
    }
    if (!phones.any((p) => p.isPrimary)) {
      showTopSnackBar(context, VN.customerPhonePrimaryRequired);
      return;
    }
    setState(() {
      _saving = true;
      _sharedPhone = const [];
    });
    final service = ref.read(customerServiceProvider);
    try {
      final name = _nameCtrl.text.trim();
      final CustomerMutationResult result;
      if (_isEditing) {
        result = await service.updateCustomer(
          widget.customer!.id,
          name: name,
          phones: phones,
        );
      } else {
        result = await service.createCustomer(name: name, phones: phones);
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
              for (var i = 0; i < _phones.length; i++)
                _PhoneRow(
                  key: ValueKey('phone-$i-${_phones.length}'),
                  entry: _phones[i],
                  canRemove: _phones.length > 1,
                  onRemove: () => _removePhone(i),
                  onSetPrimary: () => _setPrimary(i),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _addPhone,
                  icon: const Icon(Icons.add),
                  label: const Text(VN.customerAddPhone),
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

/// A single phone row: text field + primary radio + remove button.
class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    super.key,
    required this.entry,
    required this.canRemove,
    required this.onRemove,
    required this.onSetPrimary,
  });

  final _PhoneEntry entry;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: entry.controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: VN.customerPhoneField,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Primary radio toggle. Selecting this row deselects all others.
          Tooltip(
            message: VN.customerPrimaryPhone,
            child: IconButton(
              onPressed: onSetPrimary,
              icon: Icon(
                entry.isPrimary ? Icons.star : Icons.star_border,
              ),
              color: entry.isPrimary
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            onPressed: canRemove ? onRemove : null,
            tooltip: VN.customerRemovePhone,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
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
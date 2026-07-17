import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/customer.dart';
import '../../providers/customers_provider.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/utils/phone_formatter.dart';
import 'widgets/phone_entry_row.dart';

/// Show the add/edit customer bottom sheet.
///
/// Pass [customer] for edit mode; omit for add mode. Returns `true` when the
/// mutation succeeded so callers can refresh their list.
///
/// In add mode, when the typed name (diacritic-insensitive) or any typed
/// phone digits match an existing customer, a duplicate-warning dialog is
/// shown before the create call (FR8/AC6). The user can pick an existing
/// customer (reported via [onUseExisting]), proceed with the create
/// ("create anyway"), or cancel. Pass [onUseExisting] to be notified when
/// the user chooses an existing customer; the bottom sheet closes itself in
/// that case.
Future<bool?> showCustomerForm(
  BuildContext context, {
  Customer? customer,
  ValueChanged<Customer>? onUseExisting,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _CustomerForm(
      customer: customer,
      onUseExisting: onUseExisting,
    ),
  );
}

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer, this.onUseExisting});

  final Customer? customer;
  final ValueChanged<Customer>? onUseExisting;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final List<PhoneEntry> _phones = [];
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
          PhoneEntry(
            controller: TextEditingController(text: formatPhone(p.phone)),
            isPrimary: p.isPrimary,
          ),
        );
      }
    } else {
      final legacy = c?.phone ?? '';
      _phones.add(
        PhoneEntry(
          controller: TextEditingController(text: formatPhone(legacy)),
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
      _phones.add(PhoneEntry(controller: TextEditingController()));
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
    // Detect duplicate non-empty phone numbers. Compare on digit-only key so
    // that a prefilled raw value (e.g. 11 digits shown unformatted) and the
    // same digits typed (dash-formatted by PhoneInputFormatter) are still
    // flagged as duplicates.
    final seen = <String>{};
    for (final phone in trimmed) {
      if (phone.isEmpty) continue;
      final key = phone.replaceAll(RegExp(r'\D'), '');
      if (!seen.add(key)) {
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
    final name = _nameCtrl.text.trim();
    // FR8/AC6: in add mode, warn when name or any phone matches an existing
    // customer before hitting the create endpoint. The user can pick an
    // existing customer ("use existing"), proceed ("create anyway"), or
    // cancel. Edit mode skips this check — the customer is already linked.
    if (!_isEditing) {
      setState(() => _saving = true);
      final matches = await _findDuplicateCandidates(name, phones);
      if (!mounted) return;
      if (matches.isNotEmpty) {
        setState(() => _saving = false);
        final choice = await _showDuplicateWarningDialog(matches);
        if (!mounted || choice == null) {
          // User cancelled the dialog.
          setState(() => _saving = false);
          return;
        }
        if (choice.useExisting != null) {
          final existing = choice.useExisting!;
          widget.onUseExisting?.call(existing);
          // The parent now owns the existing-customer handoff (e.g. navigate
          // to the detail screen). Close the form without creating.
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        // choice.createAnyway == true → fall through to the create call.
      } else {
        setState(() => _saving = false);
      }
    }
    setState(() {
      _saving = true;
      _sharedPhone = const [];
    });
    final service = ref.read(customerServiceProvider);
    try {
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

  /// Find existing customers whose name (diacritic-insensitive contains) or
  /// any phone digits match the typed [name] or any of [phones]. Backend
  /// `GET /api/customers?search=` already does diacritic-insensitive partial
  /// matching on `search_name` and phone digits, so we issue one query per
  /// distinct query term (name + each non-empty phone) and dedupe by id.
  /// Returns the merged candidate list, excluding any in-progress edits.
  Future<List<Customer>> _findDuplicateCandidates(
    String name,
    List<CustomerPhone> phones,
  ) async {
    final service = ref.read(customerServiceProvider);
    final queries = <String>{};
    if (name.isNotEmpty) queries.add(name);
    for (final p in phones) {
      final digits = p.phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 2) queries.add(digits);
    }
    if (queries.isEmpty) return const [];
    final byId = <int, Customer>{};
    for (final q in queries) {
      try {
        final results = await service.listCustomers(search: q);
        for (final c in results) {
          byId[c.id] = c;
        }
      } catch (_) {
        // Search failures are non-fatal: skip this query and continue. The
        // create call below will still surface its own backend errors.
      }
    }
    return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Show the duplicate-warning dialog (FR8/AC6) and wait for the user's
  /// choice. Returns `null` when cancelled, otherwise a record indicating
  /// either a chosen existing customer (`useExisting`) or a request to
  /// proceed with the create (`createAnyway`).
  Future<_DuplicateChoice?> _showDuplicateWarningDialog(
    List<Customer> matches,
  ) {
    return showDialog<_DuplicateChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DuplicateWarningDialog(matches: matches),
    );
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
                PhoneEntryRow(
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

/// Choice returned by the duplicate-warning dialog (FR8/AC6).
///
/// Either [useExisting] is set (the user picked an existing customer) or
/// [createAnyway] is true (the user chose to proceed with the new create).
typedef _DuplicateChoice =
    ({Customer? useExisting, bool createAnyway});

/// Duplicate-warning dialog shown before a manual customer create when the
/// typed name or any phone matches an existing customer (DG-252 Phase 6 —
/// FR8/AC6). Lists each match with name + primary phone and offers three
/// actions: "use existing" (selects a match), "create anyway" (proceeds
/// with the create), or cancel.
class _DuplicateWarningDialog extends StatelessWidget {
  const _DuplicateWarningDialog({required this.matches});

  final List<Customer> matches;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(CustomersLabels.duplicateWarningTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(CustomersLabels.duplicateWarningHint),
            const SizedBox(height: 12),
            for (final c in matches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(c.name),
                subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                onTap: () => Navigator.of(context).pop<_DuplicateChoice>(
                  (useExisting: c, createAnyway: false),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(CustomersLabels.duplicateWarningCancel),
        ),
        FilledButton.tonal(
          onPressed: matches.isEmpty
              ? null
              : () => Navigator.of(context).pop<_DuplicateChoice>(
                    (useExisting: matches.first, createAnyway: false),
                  ),
          child: const Text(CustomersLabels.duplicateWarningUseExisting),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop<_DuplicateChoice>(
            const (useExisting: null, createAnyway: true),
          ),
          child: const Text(CustomersLabels.duplicateWarningCreateAnyway),
        ),
      ],
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
// EXEMPT: 300-line screen threshold exceeded because the pre-existing customer
// form owns multi-phone controller lifecycle, duplicate resolution, and submit
// orchestration. Draft synchronization is kept beside those controllers to
// avoid duplicating mutable controller state. Reviewed 2026-08-23.
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/customer.dart';
import '../../data/providers/customers_provider.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/models/form_draft_context.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/services/session_cache.dart';
import 'package:bakery_app/shared/utils/phone_formatter.dart';
import 'providers/customer_form_notifier.dart';
import 'widgets/duplicate_warning_dialog.dart';
import 'widgets/phone_entry_row.dart';
import 'widgets/shared_phone_banner.dart';
import 'package:bakery_app/shared/labels/shared.dart';

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
    builder: (ctx) =>
        _CustomerForm(customer: customer, onUseExisting: onUseExisting),
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

  bool get _isEditing => widget.customer != null;
  late final FormDraftContext _draftContext;
  NotifierProvider<CustomerFormNotifier, CustomerFormState> get _provider =>
      contextualCustomerFormProvider(_draftContext);

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _draftContext = FormDraftContext(
      formType: 'customer',
      mode: _isEditing ? FormDraftMode.edit : FormDraftMode.create,
      entityId: c?.id.toString(),
    );
    final draftState = ref.read(_provider);
    final draft = draftState.newDraft;
    final restore = ref.read(_provider.notifier).hasRetainedDraft;
    _nameCtrl = TextEditingController(
      text: restore ? draft.name : c?.name ?? '',
    );
    _nameCtrl.addListener(_persistNewDraft);
    // Pre-populate phone fields from customer.phones (multi-phone). Falls back
    // to the legacy single `phone` field when the API returns no phones list,
    // keeping backward compatibility for customers created before v58.
    final phones = restore
        ? draft.phones
        : c?.phones ?? const <CustomerPhone>[];
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
    for (final entry in _phones) {
      entry.controller.addListener(_persistNewDraft);
    }
    // Ensure at least one entry is marked primary if any phone is non-empty.
    if (!_phones.any((e) => e.isPrimary)) {
      _phones.first.isPrimary = true;
    }
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(_provider.notifier)
          .initialize(
            CustomerFormDraft(
              name: _nameCtrl.text,
              phones: [
                for (final entry in _phones)
                  CustomerPhone(
                    phone: entry.controller.text,
                    isPrimary: entry.isPrimary,
                  ),
              ],
            ),
          );
    });
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
    final entry = PhoneEntry(controller: TextEditingController());
    entry.controller.addListener(_persistNewDraft);
    _phones.add(entry);
    _persistNewDraft();
    ref.read(_provider.notifier).rebuild();
  }

  void _removePhone(int index) {
    if (_phones.length <= 1) return;
    final wasPrimary = _phones[index].isPrimary;
    _phones[index].dispose();
    _phones.removeAt(index);
    // If the removed entry was primary, reassign to the first remaining row.
    if (wasPrimary && _phones.isNotEmpty) {
      _phones.first.isPrimary = true;
    }
    _persistNewDraft();
    ref.read(_provider.notifier).rebuild();
  }

  void _setPrimary(int index) {
    for (var i = 0; i < _phones.length; i++) {
      _phones[i].isPrimary = i == index;
    }
    _persistNewDraft();
    ref.read(_provider.notifier).rebuild();
  }

  void _persistNewDraft() {
    ref
        .read(_provider.notifier)
        .updateNewDraft(
          name: _nameCtrl.text,
          phones: [
            for (final entry in _phones)
              CustomerPhone(
                phone: entry.controller.text,
                isPrimary: entry.isPrimary,
              ),
          ],
        );
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
        _duplicateError = CustomersLabels.customerPhoneDuplicate;
        return null;
      }
    }
    _duplicateError = null;
    // Require exactly one primary among the non-empty phones; ensure one is
    // selected automatically if none is.
    if (!_phones.any(
      (e) => e.isPrimary && e.controller.text.trim().isNotEmpty,
    )) {
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
        _duplicateError ?? CustomersLabels.customerPhoneRequired,
      );
      return;
    }
    if (!phones.any((p) => p.isPrimary)) {
      showTopSnackBar(context, CustomersLabels.customerPhonePrimaryRequired);
      return;
    }
    final name = _nameCtrl.text.trim();
    final formNotifier = ref.read(_provider.notifier);
    final submittedDraft = formNotifier.draftSnapshot;
    final service = ref.read(customerServiceProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final sessionCache = ref.read(sessionCacheProvider);
    // FR8/AC6: in add mode, warn when name or any phone matches an existing
    // customer before hitting the create endpoint. The user can pick an
    // existing customer ("use existing"), proceed ("create anyway"), or
    // cancel. Edit mode skips this check — the customer is already linked.
    if (!_isEditing) {
      formNotifier.setSaving(true);
      final matches = await _findDuplicateCandidates(name, phones);
      if (!mounted) {
        formNotifier.clearSaving();
        return;
      }
      if (matches.isNotEmpty) {
        formNotifier.setSaving(false);
        final choice = await _showDuplicateWarningDialog(matches);
        if (!mounted) return;
        if (choice == null) return;
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
        formNotifier.setSaving(false);
      }
    }
    formNotifier.startSubmit();
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
      formNotifier.clearAfterSuccess(submittedDraft);
      formNotifier.clearSaving();
      if (!mounted) return;
      formNotifier.setSharedPhone(result.sharedPhoneCustomers);
      // Invalidate the customer list so the parent screen refreshes.
      container.invalidate(customerListProvider);
      // DG-409 Phase 5 (FR13, AC6): invalidate the session cache so the
      // paginated customer list re-fetches on the next visit.
      sessionCache.invalidateEntityType(SessionCacheEntity.customers);
      if (_isEditing) {
        container.invalidate(customerProvider(widget.customer!.id));
      }
      showTopSnackBar(
        context,
        _isEditing
            ? CustomersLabels.customerUpdated
            : CustomersLabels.customerCreated,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      formNotifier.clearSaving();
      if (!mounted) return;
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
  Future<DuplicateChoice?> _showDuplicateWarningDialog(List<Customer> matches) {
    return showDialog<DuplicateChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DuplicateWarningDialog(matches: matches),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the form state so the widget rebuilds when saving/sharedPhone
    // change, and when the rebuild counter bumps (phone-list structural
    // changes driven by _addPhone/_removePhone/_setPrimary).
    final form = ref.watch(_provider);
    final saving = form.saving;
    final sharedPhone = form.sharedPhone;
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
                _isEditing
                    ? CustomersLabels.editCustomer
                    : CustomersLabels.addCustomer,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: CustomersLabels.customerNameField,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? SharedLabels.fieldRequired
                    : null,
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
                  onPressed: saving ? null : _addPhone,
                  icon: const Icon(Icons.add),
                  label: const Text(CustomersLabels.customerAddPhone),
                ),
              ),
              if (sharedPhone.isNotEmpty) ...[
                const SizedBox(height: 16),
                SharedPhoneBanner(customers: sharedPhone),
              ],
              DiscardFormDraftAction(
                isDirty: ref
                    .watch(formDraftSessionProvider)
                    .containsKey(_draftContext),
                onDiscard: () {
                  ref.read(_provider.notifier).clearNewDraft();
                  Navigator.of(context).pop(false);
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text(SharedLabels.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(SharedLabels.save),
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

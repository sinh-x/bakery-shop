import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Debt settlement screen (DG-212 Phase 4 — FR4, AC3).
///
/// Loads a single debt expense (via [EventService.getEvent]) so the user
/// can record a settlement against it. On submit, calls [settleDebt] which
/// POSTs to ``/api/expenses/{id}/settle`` with amount, payment method,
/// payment source, and an optional note. The backend creates the
/// settlement journal entry (DR 2500 / CR Asset) and returns the updated
/// remaining balance + status.
///
/// The screen accepts optional [loadEvent] / [submitSettlement] callbacks
/// for widget tests; production wiring uses [eventServiceProvider] and
/// [settleDebt].
class DebtSettlementScreen extends ConsumerStatefulWidget {
  const DebtSettlementScreen({
    super.key,
    required this.eventId,
    this.loadEvent,
    this.submitSettlement,
  });

  final int eventId;

  /// Optional override for fetching the debt [BakeryEvent]. When ``null``,
  /// the screen uses [EventService.getEvent] via [eventServiceProvider].
  final Future<BakeryEvent> Function(int eventId, WidgetRef ref)? loadEvent;

  /// Optional override for submitting the settlement. Receives [eventId],
  /// [amount], [paymentMethod], [paymentSource], [note], [settledBy]. Returns
  /// the parsed backend response.
  final Future<Map<String, dynamic>> Function({
    required int eventId,
    required int amount,
    required String paymentMethod,
    required String paymentSource,
    required String note,
    required String settledBy,
  })?
      submitSettlement;

  @override
  ConsumerState<DebtSettlementScreen> createState() =>
      _DebtSettlementScreenState();
}

class _DebtSettlementScreenState extends ConsumerState<DebtSettlementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _paymentMethod = VN.methodCash;
  String _paymentSource = VN.paymentSourceShopCash;
  bool _loading = false;
  bool _submitting = false;
  String? _loadError;
  BakeryEvent? _event;
  int _totalDebt = 0;
  int _settledSoFar = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebt());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDebt() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loader = widget.loadEvent;
      final event = loader != null
          ? await loader(widget.eventId, ref)
          : await ref.read(eventServiceProvider).getEvent(widget.eventId);
      final data = event.data;
      final amount = data['amount_vnd'];
      final total = amount is int ? amount : int.tryParse('$amount') ?? 0;
      final settlements = data['settlements'] as List? ?? const <dynamic>[];
      final settled = settlements.fold<int>(
        0,
        (sum, entry) {
          if (entry is! Map) return sum;
          final value = entry['amount'];
          final parsed = value is int ? value : int.tryParse('$value') ?? 0;
          return sum + parsed;
        },
      );
      if (!mounted) return;
      setState(() {
        _event = event;
        _totalDebt = total;
        _settledSoFar = settled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is DioException
            ? (e.message ?? VN.debtSettlementFailure)
            : VN.debtSettlementFailure;
        _loading = false;
      });
    }
  }

  int get _remaining {
    final r = _totalDebt - _settledSoFar;
    return r < 0 ? 0 : r;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final settledBy = ref.read(loggedByProvider);
      final submit = widget.submitSettlement;
      if (submit != null) {
        await submit(
          eventId: widget.eventId,
          amount: amount,
          paymentMethod: _paymentMethod,
          paymentSource: _paymentSource,
          note: _noteCtrl.text.trim(),
          settledBy: settledBy,
        );
      } else {
        await ref.read(eventServiceProvider).settleDebt(
              eventId: widget.eventId,
              amount: amount,
              paymentMethod: _paymentMethod,
              paymentSource: _paymentSource,
              note: _noteCtrl.text.trim(),
              settledBy: settledBy,
            );
      }
      if (!mounted) return;
      showTopSnackBar(context, VN.debtSettlementSuccess);
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(
        context,
        e is DioException
            ? (e.message ?? VN.debtSettlementFailure)
            : VN.debtSettlementFailure,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(VN.debtSettlementTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_loadError!),
                )
              : _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final remaining = _remaining;
    final creditor = '${_event?.data['vendor'] ?? ''}';
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(VN.debtSettlementSummary, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('${VN.debtSettlementCreditor}: $creditor'),
                  Text('${VN.debtSettlementTotalDebt}: ${formatVND(_totalDebt.toDouble())}'),
                  Text('${VN.debtSettlementSettledSoFar}: ${formatVND(_settledSoFar.toDouble())}'),
                  Text('${VN.debtSettlementRemainingLabel}: ${formatVND(remaining.toDouble())}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: VN.debtSettlementAmountLabel,
              hintText: VN.debtSettlementAmountHint,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final raw = value?.trim() ?? '';
              if (raw.isEmpty) return VN.debtSettlementAmountRequired;
              final parsed = int.tryParse(raw);
              if (parsed == null || parsed <= 0) {
                return VN.debtSettlementAmountInvalid;
              }
              if (parsed > remaining) {
                return VN.debtSettlementAmountExceedsRemaining;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: VN.debtSettlementPaymentMethodLabel,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: VN.methodCash, child: Text(VN.methodCash)),
              DropdownMenuItem(
                value: VN.methodTransfer,
                child: Text(VN.methodTransfer),
              ),
            ],
            onChanged: (value) =>
                setState(() => _paymentMethod = value ?? VN.methodCash),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentSource,
            decoration: const InputDecoration(
              labelText: VN.debtSettlementPaymentSourceLabel,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final source in expensePaymentSources)
                DropdownMenuItem(value: source, child: Text(source)),
            ],
            validator: (value) =>
                (value == null || value.isEmpty)
                    ? VN.debtSettlementPaymentSourceRequired
                    : null,
            onChanged: (value) =>
                setState(() => _paymentSource = value ?? VN.paymentSourceShopCash),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: VN.debtSettlementNoteLabel,
              hintText: VN.debtSettlementNoteHint,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.debtSettlementSaveAction),
          ),
        ],
      ),
    );
  }
}

import 'package:bakery_app/shared/utils.dart' show formatVND, showTopSnackBar;
import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/providers/debt_settlement_notifier.dart';
import 'package:bakery_app/shared/providers/logged_by_provider.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:bakery_app/shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
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
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late final FormDraftContext _draftContext;
  NotifierProvider<DebtSettlementNotifier, DebtSettlementState> get _provider =>
      contextualDebtSettlementProvider(_draftContext);

  @override
  void initState() {
    super.initState();
    _draftContext = FormDraftContext(
      formType: 'debt-settlement',
      mode: FormDraftMode.action,
      entityId: widget.eventId.toString(),
    );
    final notifier = ref.read(_provider.notifier);
    _amountCtrl = TextEditingController(text: notifier.draft.amount)
      ..addListener(() => notifier.setAmount(_amountCtrl.text));
    _noteCtrl = TextEditingController(text: notifier.draft.note)
      ..addListener(() => notifier.setNote(_noteCtrl.text));
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
    final notifier = ref.read(_provider.notifier);
    notifier.startLoading();
    try {
      final loader = widget.loadEvent;
      final event = loader != null
          ? await loader(widget.eventId, ref)
          : await ref.read(eventServiceProvider).getEvent(widget.eventId);
      final data = event.data;
      final amount = data['amount_vnd'];
      final total = amount is int ? amount : int.tryParse('$amount') ?? 0;
      final settlements = data['settlements'] as List? ?? const <dynamic>[];
      final settled = settlements.fold<int>(0, (sum, entry) {
        if (entry is! Map) return sum;
        final value = entry['amount'];
        final parsed = value is int ? value : int.tryParse('$value') ?? 0;
        return sum + parsed;
      });
      if (!mounted) return;
      notifier.setLoadedEvent(
        event: event,
        totalDebt: total,
        settledSoFar: settled,
      );
    } catch (e) {
      if (!mounted) return;
      notifier.setLoadError(
        e is DioException
            ? (e.message ?? ExpensesLabels.debtSettlementFailure)
            : ExpensesLabels.debtSettlementFailure,
      );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;
    if (!mounted) return;
    final notifier = ref.read(_provider.notifier);
    final state = ref.read(_provider);
    final submittedDraft = notifier.draftSnapshot;
    notifier.setSubmitting(true);
    try {
      final settledBy = ref.read(loggedByProvider);
      final submit = widget.submitSettlement;
      if (submit != null) {
        await submit(
          eventId: widget.eventId,
          amount: amount,
          paymentMethod: state.paymentMethod,
          paymentSource: state.paymentSource,
          note: _noteCtrl.text.trim(),
          settledBy: settledBy,
        );
      } else {
        await ref
            .read(eventServiceProvider)
            .settleDebt(
              eventId: widget.eventId,
              amount: amount,
              paymentMethod: state.paymentMethod,
              paymentSource: state.paymentSource,
              note: _noteCtrl.text.trim(),
              settledBy: settledBy,
            );
      }
      if (!mounted) return;
      notifier.clearAfterSuccess(submittedDraft);
      showTopSnackBar(context, ExpensesLabels.debtSettlementSuccess);
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(
        context,
        e is DioException
            ? (e.message ?? ExpensesLabels.debtSettlementFailure)
            : ExpensesLabels.debtSettlementFailure,
      );
    } finally {
      notifier.setSubmitting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(ExpensesLabels.debtSettlementTitle),
        actions: [
          DiscardFormDraftAction(
            isDirty: ref
                .watch(formDraftSessionProvider)
                .containsKey(_draftContext),
            onDiscard: () {
              notifier.clearDraft();
              context.pop(false);
            },
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.loadError != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(state.loadError!),
            )
          : _buildForm(theme, state, notifier),
    );
  }

  Widget _buildForm(
    ThemeData theme,
    DebtSettlementState state,
    DebtSettlementNotifier notifier,
  ) {
    final remaining = state.remaining;
    final creditor = '${state.event?.data['vendor'] ?? ''}';
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
                  Text(
                    ExpensesLabels.debtSettlementSummary,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text('${ExpensesLabels.debtSettlementCreditor}: $creditor'),
                  Text(
                    '${ExpensesLabels.debtSettlementTotalDebt}: ${formatVND(state.totalDebt.toDouble())}',
                  ),
                  Text(
                    '${ExpensesLabels.debtSettlementSettledSoFar}: ${formatVND(state.settledSoFar.toDouble())}',
                  ),
                  Text(
                    '${ExpensesLabels.debtSettlementRemainingLabel}: ${formatVND(remaining.toDouble())}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: ExpensesLabels.debtSettlementAmountLabel,
              hintText: ExpensesLabels.debtSettlementAmountHint,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final raw = value?.trim() ?? '';
              if (raw.isEmpty) {
                return ExpensesLabels.debtSettlementAmountRequired;
              }
              final parsed = int.tryParse(raw);
              if (parsed == null || parsed <= 0) {
                return ExpensesLabels.debtSettlementAmountInvalid;
              }
              if (parsed > remaining) {
                return ExpensesLabels.debtSettlementAmountExceedsRemaining;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.paymentMethod,
            decoration: const InputDecoration(
              labelText: ExpensesLabels.debtSettlementPaymentMethodLabel,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: OrdersLabels.methodCash,
                child: Text(OrdersLabels.methodCash),
              ),
              DropdownMenuItem(
                value: OrdersLabels.methodTransfer,
                child: Text(OrdersLabels.methodTransfer),
              ),
            ],
            onChanged: (value) =>
                notifier.setPaymentMethod(value ?? OrdersLabels.methodCash),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.paymentSource,
            decoration: const InputDecoration(
              labelText: ExpensesLabels.debtSettlementPaymentSourceLabel,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final source in expensePaymentSources)
                DropdownMenuItem(value: source, child: Text(source)),
            ],
            validator: (value) => (value == null || value.isEmpty)
                ? ExpensesLabels.debtSettlementPaymentSourceRequired
                : null,
            onChanged: (value) => notifier.setPaymentSource(
              value ?? ExpensesLabels.paymentSourceDrawerCash,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: ExpensesLabels.debtSettlementNoteLabel,
              hintText: ExpensesLabels.debtSettlementNoteHint,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: state.submitting ? null : _submit,
            child: state.submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(ExpensesLabels.debtSettlementSaveAction),
          ),
        ],
      ),
    );
  }
}

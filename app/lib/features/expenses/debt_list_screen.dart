import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:bakery_app/features/expenses/providers/debt_list_notifier.dart';
import 'package:bakery_app/features/expenses/widgets/creditor_group_card.dart';
import 'package:bakery_app/features/expenses/widgets/debt_status_filter_strip.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/data/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Outstanding debts list screen (DG-212 Phase 4 — FR5).
///
/// Displays debts grouped by creditor with per-creditor totals and a grand
/// total owed. Supports a debt status filter chip strip (FR7). Tapping a
/// debt row opens the settlement screen at ``/expenses/:id/settle``.
///
/// The screen accepts optional [loadDebts] / [onOpenSettlement] callbacks
/// for widget tests; production wiring uses [debtsProvider] and go_router.
class DebtListScreen extends ConsumerStatefulWidget {
  const DebtListScreen({
    super.key,
    this.loadDebts,
    this.onOpenSettlement,
  });

  /// Optional override for fetching debts. Receives the active [status]
  /// filter value (``all``/``unpaid``/``partial``/``paid`` or empty for
  /// all). Returns the parsed backend response (``creditors``, ``total_owed``,
  /// ``count``).
  final Future<Map<String, dynamic>> Function({String? status})? loadDebts;

  /// Optional override for navigating to the settlement screen. Receives
  /// the debt ``event_id``. When ``null``, the screen uses go_router.
  final void Function(int eventId)? onOpenSettlement;

  @override
  ConsumerState<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends ConsumerState<DebtListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final notifier = ref.read(debtListProvider.notifier);
    final status = ref.read(debtListProvider).status;
    notifier.startReload();
    final statusApi = expenseDebtStatusFilterApiValue(status);
    try {
      final data = widget.loadDebts != null
          ? await widget.loadDebts!(status: statusApi.isEmpty ? null : statusApi)
          : await ref.read(debtsProvider.notifier).reload(
                status: statusApi.isEmpty ? null : statusApi,
              );
      if (!mounted) return;
      notifier.setData(data);
    } catch (e) {
      if (!mounted) return;
      notifier.setError(
        e is DioException
            ? (e.message ?? ExpensesLabels.debtListLoadError)
            : ExpensesLabels.debtListLoadError,
      );
    }
  }

  void _setStatus(ExpenseDebtStatusFilter value) {
    if (!mounted) return;
    ref.read(debtListProvider.notifier).setStatus(value);
    _reload();
  }

  void _openSettlement(int eventId) {
    final cb = widget.onOpenSettlement;
    if (cb != null) {
      cb(eventId);
      return;
    }
    context.push('/expenses/$eventId/settle');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(debtListProvider);
    final creditors = (state.data['creditors'] as List?) ?? const <dynamic>[];
    final totalOwed = (state.data['total_owed'] as num?)?.toDouble() ?? 0.0;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(ExpensesLabels.debtListTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DebtStatusFilterStrip(status: state.status, onChanged: _setStatus),
          const SizedBox(height: 8),
          if (state.loading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (state.error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(state.error!),
              ),
            )
          else if (creditors.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(ExpensesLabels.debtListEmpty),
              ),
            )
          else ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${ExpensesLabels.debtListTotalOwed}: ${formatVND(totalOwed)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final creditor in creditors)
              CreditorGroupCard(
                creditor: creditor as Map<String, dynamic>,
                onOpenSettlement: _openSettlement,
              ),
          ],
        ],
      ),
    );
  }
}
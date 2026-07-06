import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
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
  ExpenseDebtStatusFilter _status = ExpenseDebtStatusFilter.all;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {
    'creditors': <Map<String, dynamic>>[],
    'total_owed': 0.0,
    'count': 0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final statusApi = expenseDebtStatusFilterApiValue(_status);
    try {
      final data = widget.loadDebts != null
          ? await widget.loadDebts!(status: statusApi.isEmpty ? null : statusApi)
          : await ref.read(debtsProvider.notifier).reload(
                status: statusApi.isEmpty ? null : statusApi,
              );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DioException ? (e.message ?? VN.debtListLoadError) : VN.debtListLoadError;
        _loading = false;
      });
    }
  }

  void _setStatus(ExpenseDebtStatusFilter value) {
    if (!mounted) return;
    setState(() => _status = value);
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
    final creditors = (_data['creditors'] as List?) ?? const <dynamic>[];
    final totalOwed = (_data['total_owed'] as num?)?.toDouble() ?? 0.0;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(VN.debtListTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusFilterStrip(status: _status, onChanged: _setStatus),
          const SizedBox(height: 8),
          if (_loading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            )
          else if (creditors.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(VN.debtListEmpty),
              ),
            )
          else ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${VN.debtListTotalOwed}: ${formatVND(totalOwed)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final creditor in creditors)
              _CreditorGroupCard(
                creditor: creditor as Map<String, dynamic>,
                onOpenSettlement: _openSettlement,
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusFilterStrip extends StatelessWidget {
  const _StatusFilterStrip({required this.status, required this.onChanged});

  final ExpenseDebtStatusFilter status;
  final ValueChanged<ExpenseDebtStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 9),
            child: Text(
              VN.debtListFilterStatusLabel,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final value in ExpenseDebtStatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(expenseDebtStatusFilterLabel(value)),
                selected: status == value,
                onSelected: (_) => onChanged(value),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _CreditorGroupCard extends StatelessWidget {
  const _CreditorGroupCard({
    required this.creditor,
    required this.onOpenSettlement,
  });

  final Map<String, dynamic> creditor;
  final void Function(int eventId) onOpenSettlement;

  @override
  Widget build(BuildContext context) {
    final name = '${creditor['creditor'] ?? ''}';
    final debts = (creditor['debts'] as List?) ?? const <dynamic>[];
    final totalOwed = (creditor['total_owed'] as num?)?.toDouble() ?? 0.0;
    final count = (creditor['count'] as num?)?.toInt() ?? debts.length;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium),
            Text(
              '${VN.debtListCreditorTotal}: ${formatVND(totalOwed)} • ${VN.debtListDebtCount}: $count',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final debt in debts)
              _DebtRow(debt: debt as Map<String, dynamic>, onTap: onOpenSettlement),
          ],
        ),
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.debt, required this.onTap});

  final Map<String, dynamic> debt;
  final void Function(int eventId) onTap;

  @override
  Widget build(BuildContext context) {
    final eventId = (debt['event_id'] as num?)?.toInt() ?? 0;
    final amount = (debt['amount_vnd'] as num?)?.toDouble() ?? 0.0;
    final settled = (debt['settled_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (debt['remaining'] as num?)?.toDouble() ?? 0.0;
    final status = '${debt['status'] ?? ''}';
    final timestamp = debt['timestamp'] as String?;
    final summary = '${debt['summary'] ?? ''}';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.isNotEmpty) Text(summary, style: theme.textTheme.bodyMedium),
                Text('${VN.debtListItemAmount}: ${formatVND(amount)}'),
                Text('${VN.debtListItemSettled}: ${formatVND(settled)}'),
                Text('${VN.debtListItemRemaining}: ${formatVND(remaining)}'),
                if (timestamp != null)
                  Text(formatDisplay(parseApiDateTime(timestamp))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusChip(status: status),
              const SizedBox(height: 4),
              if (remaining > 0)
                FilledButton.tonal(
                  onPressed: eventId > 0 ? () => onTap(eventId) : null,
                  child: const Text(VN.debtListOpenSettlement),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'paid' => (VN.debtStatusPaid, Colors.green.shade100),
      'partial' => (VN.debtStatusPartial, Colors.amber.shade100),
      _ => (VN.debtStatusUnpaid, Colors.orange.shade100),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

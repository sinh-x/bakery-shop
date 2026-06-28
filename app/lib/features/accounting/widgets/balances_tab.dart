import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/accounting_provider.dart';
import '../../../shared/utils/account_type_helper.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import '../../../data/models/account_balance.dart';
import 'empty_state.dart';

class BalancesTab extends ConsumerWidget {
  const BalancesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(accountBalancesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(accountBalancesProvider),
      child: balancesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(accountBalancesProvider),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (balances) {
          if (balances.isEmpty) {
            return const AccountingEmptyState(text: VN.accountingNoBalances);
          }
          final grouped = _groupByType(balances);
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: grouped.length,
            itemBuilder: (context, index) => _BalanceGroup(
              type: grouped[index].$1,
              balances: grouped[index].$2,
            ),
          );
        },
      ),
    );
  }

  List<(String, List<AccountBalance>)> _groupByType(
    List<AccountBalance> balances,
  ) {
    const typeOrder = ['asset', 'liability', 'equity', 'income', 'expense'];
    final groups = <(String, List<AccountBalance>)>[];
    for (final type in typeOrder) {
      final items = balances.where((b) => b.type == type).toList();
      if (items.isNotEmpty) {
        groups.add((type, items));
      }
    }
    return groups;
  }
}

class _BalanceGroup extends StatelessWidget {
  const _BalanceGroup({required this.type, required this.balances});

  final String type;
  final List<AccountBalance> balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = accountTypeColor(type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                accountTypeLabel(type),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: typeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Card(
            child: Column(
              children: balances.map((b) => _BalanceRow(balance: b)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = balance.balance >= 0;
    final balanceColor =
        isPositive ? Colors.green.shade700 : Colors.red.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              balance.code,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              balance.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatVND(balance.balance.abs()),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: balanceColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isPositive ? '' : '(Âm)',
            style: theme.textTheme.labelSmall?.copyWith(color: balanceColor),
          ),
        ],
      ),
    );
  }
}
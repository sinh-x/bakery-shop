import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/accounting_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import '../../../data/models/account.dart';

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(accountsProvider),
      child: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(accountsProvider),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const _EmptyState(text: VN.accountingNoAccounts);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: accounts.length,
            itemBuilder: (context, index) =>
                _AccountTile(account: accounts[index], depth: 0),
          );
        },
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.depth});

  final Account account;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(account.type);

    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: typeColor.withAlpha(120)),
            ),
            child: Text(
              account.code,
              style: theme.textTheme.labelMedium?.copyWith(
                color: typeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              account.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (!account.isActive)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.visibility_off, size: 16, color: Colors.grey.shade400),
            ),
        ],
      ),
      subtitle: Text(
        _typeLabel(account.type),
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
      children: account.children.isEmpty
          ? const []
          : account.children
              .map((child) => _AccountTile(account: child, depth: depth + 1))
              .toList(),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'asset':
        return Colors.blue;
      case 'liability':
        return Colors.orange;
      case 'equity':
        return Colors.purple;
      case 'income':
        return Colors.green;
      case 'expense':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'asset':
        return 'Tài sản';
      case 'liability':
        return 'Nợ phải trả';
      case 'equity':
        return 'Vốn chủ sở hữu';
      case 'income':
        return 'Doanh thu';
      case 'expense':
        return 'Chi phí';
      default:
        return type;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ),
      ],
    );
  }
}
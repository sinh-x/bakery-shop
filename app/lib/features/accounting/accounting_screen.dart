import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/accounts_tab.dart';
import 'widgets/journal_tab.dart';
import 'widgets/balances_tab.dart';

class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});

  @override
  ConsumerState<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.accountingTitle),
        actions: const [AppBarOverflowMenu()],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.account_tree), text: VN.accountingTabAccounts),
            Tab(icon: Icon(Icons.receipt_long), text: VN.accountingTabJournal),
            Tab(icon: Icon(Icons.account_balance), text: VN.accountingTabBalances),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AccountsTab(),
          JournalTab(),
          BalancesTab(),
        ],
      ),
    );
  }
}
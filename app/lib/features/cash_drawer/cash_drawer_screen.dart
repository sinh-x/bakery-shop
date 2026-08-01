import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cash_drawer_service.dart';
import '../../data/models/cash_drawer.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'widgets/cash_drawer_action_dialogs.dart';
import 'widgets/cash_drawer_history_list.dart';
import 'widgets/cash_drawer_status_card.dart';

/// Tracks whether a cash-drawer mutation (open / cash-in / cash-out / close)
/// is in-flight so the action buttons can be disabled and a snackbar shown.
///
/// Sync state per §4 of docs/flutter-coding-standards.md → `Notifier<bool>`.
class _CashDrawerMutationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> run(
    BuildContext context,
    Future<CashDrawer> Function() action,
    String successMessage,
    WidgetRef ref,
  ) async {
    state = true;
    try {
      await action();
      ref.invalidate(cashDrawerStatusProvider);
      ref.invalidate(cashDrawerHistoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
      }
    } finally {
      state = false;
    }
  }
}

final _mutationInProgressProvider =
    NotifierProvider<_CashDrawerMutationNotifier, bool>(
  _CashDrawerMutationNotifier.new,
);

class CashDrawerScreen extends ConsumerStatefulWidget {
  const CashDrawerScreen({super.key});

  @override
  ConsumerState<CashDrawerScreen> createState() => _CashDrawerScreenState();
}

class _CashDrawerScreenState extends ConsumerState<CashDrawerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(cashDrawerStatusProvider);
    final historyAsync =
        ref.watch(cashDrawerHistoryProvider(const CashDrawerHistoryFilter()));
    final mutating = ref.watch(_mutationInProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.cashDrawerTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: () {
              ref.invalidate(cashDrawerStatusProvider);
              ref.invalidate(cashDrawerHistoryProvider);
            },
          ),
          const AppBarOverflowMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.point_of_sale), text: VN.cashDrawerStatusOpen),
            Tab(icon: Icon(Icons.history), text: VN.cashDrawerHistory),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ActiveTab(
            statusAsync: statusAsync,
            mutating: mutating,
            onOpen: () => _handleOpen(context),
            onCashIn: () => _handleCashIn(context),
            onCashOut: () => _handleCashOut(context),
            onClose: () => _handleClose(context),
          ),
          _HistoryTab(historyAsync: historyAsync),
        ],
      ),
    );
  }

  Future<void> _handleOpen(BuildContext context) async {
    final result = await showOpenDrawerDialog(context);
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref
              .read(cashDrawerServiceProvider)
              .openDrawer(openingBalance: result.amount, note: result.note),
          VN.cashDrawerOpenSuccess,
          ref,
        );
  }

  Future<void> _handleCashIn(BuildContext context) async {
    final result = await showCashInDialog(context);
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref
              .read(cashDrawerServiceProvider)
              .cashIn(amount: result.amount, note: result.note),
          VN.cashDrawerCashInSuccess,
          ref,
        );
  }

  Future<void> _handleCashOut(BuildContext context) async {
    final result = await showCashOutDialog(context);
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref
              .read(cashDrawerServiceProvider)
              .cashOut(amount: result.amount, note: result.note),
          VN.cashDrawerCashOutSuccess,
          ref,
        );
  }

  Future<void> _handleClose(BuildContext context) async {
    final drawer = ref.read(cashDrawerStatusProvider).value;
    if (drawer == null) return;
    final result = await showCloseDrawerDialog(
      context,
      expectedBalance: drawer.expectedBalance,
    );
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref
              .read(cashDrawerServiceProvider)
              .closeDrawer(countedAmount: result.amount, note: result.note),
          VN.cashDrawerCloseSuccess,
          ref,
        );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({
    required this.statusAsync,
    required this.mutating,
    required this.onOpen,
    required this.onCashIn,
    required this.onCashOut,
    required this.onClose,
  });

  final AsyncValue<CashDrawer?> statusAsync;
  final bool mutating;
  final Future<void> Function() onOpen;
  final Future<void> Function() onCashIn;
  final Future<void> Function() onCashOut;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onOpen,
              child: const Text(VN.retry),
            ),
          ],
        ),
      ),
      data: (drawer) {
        if (drawer == null) {
          return _EmptyActiveView(onOpen: onOpen, mutating: mutating);
        }
        return ListView(
          children: [
            CashDrawerStatusCard(drawer: drawer),
            const SizedBox(height: 8),
            _ActionBar(
              isOpen: drawer.isOpen,
              mutating: mutating,
              onOpen: onOpen,
              onCashIn: onCashIn,
              onCashOut: onCashOut,
              onClose: onClose,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _EmptyActiveView extends StatelessWidget {
  const _EmptyActiveView({required this.onOpen, required this.mutating});

  final Future<void> Function() onOpen;
  final bool mutating;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(VN.cashDrawerNoActive),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: mutating ? null : onOpen,
              icon: const Icon(Icons.lock_open),
              label: const Text(VN.cashDrawerOpen),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isOpen,
    required this.mutating,
    required this.onOpen,
    required this.onCashIn,
    required this.onCashOut,
    required this.onClose,
  });

  final bool isOpen;
  final bool mutating;
  final Future<void> Function() onOpen;
  final Future<void> Function() onCashIn;
  final Future<void> Function() onCashOut;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: mutating ? null : onCashIn,
            icon: const Icon(Icons.south_west),
            label: const Text(VN.cashDrawerCashIn),
          ),
          FilledButton.tonalIcon(
            onPressed: mutating ? null : onCashOut,
            icon: const Icon(Icons.north_east),
            label: const Text(VN.cashDrawerCashOut),
          ),
          FilledButton.tonalIcon(
            onPressed: mutating ? null : onClose,
            icon: const Icon(Icons.lock_outline),
            label: const Text(VN.cashDrawerClose),
          ),
          if (!isOpen)
            FilledButton.icon(
              onPressed: mutating ? null : onOpen,
              icon: const Icon(Icons.lock_open),
              label: const Text(VN.cashDrawerOpen),
            ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.historyAsync});

  final AsyncValue<CashDrawerHistoryResponse> historyAsync;

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {},
              child: const Text(VN.retry),
            ),
          ],
        ),
      ),
      data: (resp) => SingleChildScrollView(
        child: CashDrawerHistoryList(items: resp.items),
      ),
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cash_drawer_service.dart';
import '../../data/api/staff_service.dart';
import '../../data/models/cash_drawer.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/staff_provider.dart';
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
  // DG-331 FR11/AC11: polls the cash drawer status every 30 seconds while
  // the screen is visible. Cancelled in [dispose] to avoid firing after the
  // widget is gone.
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // DG-331 FR10/AC10: auto-refresh the cash drawer status on entering the
    // screen so the "Tiền tại quầy" amount is current (not a stale cache).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(cashDrawerStatusProvider);
      ref.invalidate(cashDrawerHistoryProvider);
    });
    // DG-331 FR11/AC11: poll every 30 seconds while the screen is visible.
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted) return;
        ref.invalidate(cashDrawerStatusProvider);
      },
    );
  }

  @override
  void dispose() {
    // DG-331 FR11/AC11: cancel the polling timer when the screen is removed.
    _statusPollTimer?.cancel();
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
    // DG-331 FR9/AC8: surface the previous close counted amount ("Số dư sau
    // khi đóng quỹ lần trước") in the open dialog as a reference. The 1101
    // accounting reference balance is only revealed by the backend on a 409
    // proposal (see TransferProposalException/ExcessProposalException below),
    // so it is not passed here upfront.
    final previousClose = ref.read(cashDrawerPreviousCloseProvider).value;
    final result = await showOpenDrawerDialog(
      context,
      previousCloseCountedAmount: previousClose,
    );
    if (result == null || !context.mounted) return;

    bool carryOverConfirmed = false;
    bool transferConfirmed = false;
    bool stockReconciliationConfirmed = false;
    bool unidentifiedSaleConfirmed = false;
    bool ownerCapitalConfirmed = false;

    while (true) {
      try {
        await ref.read(cashDrawerServiceProvider).openDrawer(
              openingBalance: result.amount,
              note: result.note,
              carryOverConfirmed: carryOverConfirmed,
              transferConfirmed: transferConfirmed,
              stockReconciliationConfirmed: stockReconciliationConfirmed,
              unidentifiedSaleConfirmed: unidentifiedSaleConfirmed,
              ownerCapitalConfirmed: ownerCapitalConfirmed,
            );
        if (!context.mounted) return;
        _onOpenSuccess(context);
        return;
      } on CarryOverProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showCarryOverConfirmationDialog(
          context,
          carryOverAmount: e.amount,
        );
        if (decision == null || !context.mounted) return;
        carryOverConfirmed = true;
      } on TransferProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showTransferConfirmationDialog(
          context,
          referenceBalance: e.referenceBalance,
          openingBalance: e.openingBalance,
          excess: e.excess,
        );
        if (decision == null || !context.mounted) return;
        transferConfirmed = true;
        break;
      } on ExcessProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showStockReconciliationDialog(
          context,
          referenceBalance: e.referenceBalance,
          openingBalance: e.openingBalance,
          excess: e.excess,
        );
        if (decision == null || !context.mounted) return;
        if (decision == StockReconDecision.accept) {
          stockReconciliationConfirmed = true;
          final saleDecision = await showUnidentifiedSaleDialog(
            context,
            excess: e.excess,
          );
          if (saleDecision == null || !context.mounted) return;
          if (saleDecision == UnidentifiedSaleDecision.accept) {
            unidentifiedSaleConfirmed = true;
          }
        } else if (decision == StockReconDecision.ownerCapital) {
          ownerCapitalConfirmed = true;
        }
        break;
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
        return;
      }
    }
    // Re-issue the final call with confirmation flags (outside the loop
    // for transfer/excess — these don't loop like carry-over).
    try {
      await ref.read(_mutationInProgressProvider.notifier).run(
            context,
            () => ref.read(cashDrawerServiceProvider).openDrawer(
                  openingBalance: result.amount,
                  note: result.note,
                  carryOverConfirmed: carryOverConfirmed,
                  transferConfirmed: transferConfirmed,
                  stockReconciliationConfirmed: stockReconciliationConfirmed,
                  unidentifiedSaleConfirmed: unidentifiedSaleConfirmed,
                  ownerCapitalConfirmed: ownerCapitalConfirmed,
                ),
            VN.cashDrawerOpenSuccess,
            ref,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${VN.apiError}: $e')),
      );
    }
  }

  void _onOpenSuccess(BuildContext context) {
    ref.invalidate(cashDrawerStatusProvider);
    ref.invalidate(cashDrawerHistoryProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(VN.cashDrawerOpenSuccess)),
      );
    }
  }

  Future<void> _handleCashIn(BuildContext context) async {
    final staff = ref.read(staffListProvider).value ?? const <StaffMember>[];
    final result = await showCashInDialog(context, staff: staff);
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref.read(cashDrawerServiceProvider).cashIn(
                amount: result.amount,
                note: result.note,
                source: result.source ?? 'equity',
                staffName: result.staffName,
              ),
          VN.cashDrawerCashInSuccess,
          ref,
        );
  }

  Future<void> _handleCashOut(BuildContext context) async {
    final staff = ref.read(staffListProvider).value ?? const <StaffMember>[];
    final result = await showCashOutDialog(context, staff: staff);
    if (result == null || !context.mounted) return;
    await ref.read(_mutationInProgressProvider.notifier).run(
          context,
          () => ref.read(cashDrawerServiceProvider).cashOut(
                amount: result.amount,
                note: result.note,
                destination: result.destination ?? 'owner',
                staffName: result.staffName,
              ),
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

    // DG-331 AC9: the first close attempt may raise a 409 surplus/shortage
    // proposal. Loop so the owner can confirm the nature of the discrepancy
    // and re-send the close with the matching confirmation flag + source.
    // The loop runs at most twice: first call → 409 proposal, second call
    // → confirmed close (or cancel). No carry-over style re-loop here — the
    // close confirmation is a single round-trip per the plan.
    bool surplusConfirmed = false;
    String? surplusSource;
    bool shortageConfirmed = false;
    String? shortageSource;
    while (true) {
      try {
        await ref.read(_mutationInProgressProvider.notifier).run(
              context,
              () => ref.read(cashDrawerServiceProvider).closeDrawer(
                    countedAmount: result.amount,
                    note: result.note,
                    surplusConfirmed: surplusConfirmed,
                    surplusSource: surplusSource,
                    shortageConfirmed: shortageConfirmed,
                    shortageSource: shortageSource,
                  ),
              VN.cashDrawerCloseSuccess,
              ref,
            );
        return;
      } on CloseSurplusProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showCloseSurplusDialog(
          context,
          expectedBalance: e.expectedBalance,
          countedAmount: e.countedAmount,
          surplus: e.surplus,
        );
        if (decision == null || !context.mounted) return;
        surplusConfirmed = true;
        surplusSource = decision == CloseSurplusDecision.ownerCash
            ? 'owner_cash'
            : 'unidentified_sale';
      } on CloseShortageProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showCloseShortageDialog(
          context,
          expectedBalance: e.expectedBalance,
          countedAmount: e.countedAmount,
          shortage: e.shortage,
        );
        if (decision == null || !context.mounted) return;
        shortageConfirmed = true;
        shortageSource = decision == CloseShortageDecision.ownerWithdraw
            ? 'owner_withdraw'
            : 'equity_loss';
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
        return;
      }
    }
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
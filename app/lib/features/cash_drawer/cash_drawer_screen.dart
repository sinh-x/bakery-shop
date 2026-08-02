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
    // khi đóng quỹ lần trước") in the open dialog as a reference. Phase 4.1
    // F3: also surface the 1101 accounting balance upfront (before any 409
    // proposal) so the owner can reconcile immediately. The 1101 balance is
    // still passed through by the 409 proposal paths below.
    final previousClose = ref.read(cashDrawerPreviousCloseProvider).value;
    final accountingBalance1101 =
        ref.read(cashDrawerAccountingBalance1101Provider).value ?? 0;
    final result = await showOpenDrawerDialog(
      context,
      referenceBalance: accountingBalance1101,
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
    // Phase 4.1 F5: show the current expected balance as helper text so the
    // owner knows how much is already in the drawer.
    final drawer = ref.read(cashDrawerStatusProvider).value;
    final expectedBalance = drawer?.expectedBalance ?? 0;
    final result = await showCashInDialog(
      context,
      staff: staff,
      expectedBalance: expectedBalance,
    );
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
    // Phase 4.1 F6: show the current expected balance as helper text so the
    // owner knows how much they can withdraw.
    final drawer = ref.read(cashDrawerStatusProvider).value;
    final expectedBalance = drawer?.expectedBalance ?? 0;
    final result = await showCashOutDialog(
      context,
      staff: staff,
      expectedBalance: expectedBalance,
    );
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
    // Phase 4.1 F4: surface the 1101 accounting balance below the expected
    // balance for reconciliation reference.
    final result = await showCloseDrawerDialog(
      context,
      expectedBalance: drawer.expectedBalance,
      accountingBalance1101: drawer.accountingBalance1101,
    );
    if (result == null || !context.mounted) return;

    // DG-331 AC9: close may return a 409 surplus/shortage proposal instead
    // of 200. The mutation notifier's generic catch-all swallows typed
    // exceptions, so the first call goes directly to the service. The
    // typed `on` handlers surface the confirmation dialog. After the owner
    // chooses the nature of the discrepancy, the second call goes through
    // the mutation notifier so the success snackbar + invalidation fire.
    bool surplusConfirmed = false;
    String? surplusSource;
    bool shortageConfirmed = false;
    String? shortageSource;
    while (true) {
      try {
        final service = ref.read(cashDrawerServiceProvider);
        final drawer = await service.closeDrawer(
          countedAmount: result.amount,
          note: result.note,
          surplusConfirmed: surplusConfirmed,
          surplusSource: surplusSource,
          shortageConfirmed: shortageConfirmed,
          shortageSource: shortageSource,
        );
        // Confirmed close succeeded — show success via the notifier pattern.
        ref.invalidate(cashDrawerStatusProvider);
        ref.invalidate(cashDrawerHistoryProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text(VN.cashDrawerCloseSuccess)),
          );
        }
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
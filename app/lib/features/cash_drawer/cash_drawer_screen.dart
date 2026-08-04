import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cash_drawer_service.dart';
import '../../data/api/staff_service.dart';
import '../../data/models/cash_drawer.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/staff_provider.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'widgets/cash_drawer_action_dialogs.dart';
import 'widgets/cash_drawer_history_list.dart';
import 'widgets/cash_drawer_status_card.dart';
import 'widgets/cash_drawer_transaction_list.dart';

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
      // CQ-1: invalidate the active drawer's first transaction page so the
      // "Chi tiết giao dịch" tab shows fresh data immediately after a
      // cash-in / cash-out / close mutation instead of waiting for the 30s
      // poll cycle.
      final activeDrawer = ref.read(cashDrawerStatusProvider).value;
      final activeDrawerId = activeDrawer == null
          ? null
          : int.tryParse(activeDrawer.id);
      if (activeDrawerId != null) {
        ref.invalidate(cashDrawerTransactionsProvider(
          CashDrawerTransactionsFilter(drawerId: activeDrawerId),
        ));
      }
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
  // DG-343 Phase 3 FR3/AC4: the index of the "Chi tiết giao dịch" tab. When
  // the user is on this tab and a drawer is open, the 30s poll also
  // invalidates [cashDrawerTransactionsProvider] for the active drawer so
  // the list refreshes within 30 seconds of a new transaction.
  static const _transactionsTabIndex = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // DG-343 Phase 3 FR3: prevent the user from settling on the transaction
    // tab when no drawer is open. We listen for tab changes and snap back to
    // the status tab (index 0) if the transaction tab was selected while
    // disabled. The visual disabled state is handled in [build] via the
    // TabBar's enabled state per-tab.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      if (_tabController.index == _transactionsTabIndex && !_transactionsTabEnabled) {
        // Defer the snap-back so the TabBar finishes its current notification
        // round-trip before we mutate the controller.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tabController.index = 0;
        });
      }
    });
    // DG-331 FR10/AC10: auto-refresh the cash drawer status on entering the
    // screen so the "Tiền tại quầy" amount is current (not a stale cache).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(cashDrawerStatusProvider);
      ref.invalidate(cashDrawerHistoryProvider);
    });
    // DG-331 FR11/AC11: poll every 30 seconds while the screen is visible.
    // DG-343 CQ-2: only invalidate the status provider here. The transaction
    // tab's full refresh cycle is handled by the widget-level timer in
    // [CashDrawerTransactionList(poll: true)], so a second screen-level
    // invalidation of [cashDrawerTransactionsProvider] would be redundant.
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted) return;
        ref.invalidate(cashDrawerStatusProvider);
      },
    );
  }

  /// Whether the "Chi tiết giao dịch" tab is currently enabled (FR3): only
  /// when the active drawer status has resolved to a non-null drawer.
  bool get _transactionsTabEnabled {
    final status = ref.read(cashDrawerStatusProvider);
    return status.value != null;
  }

  /// The active drawer's numeric id, or `null` when no drawer is open.
  /// Used to invalidate the transaction provider during the 30s poll and to
  /// build the transaction tab content.
  int? get _activeDrawerId {
    final drawer = ref.read(cashDrawerStatusProvider).value;
    if (drawer == null) return null;
    return int.tryParse(drawer.id);
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
    final accountingBalance1101Async =
        ref.watch(cashDrawerAccountingBalance1101Provider);
    final previousCloseAsync = ref.watch(cashDrawerPreviousCloseProvider);

    // DG-343 Phase 3 FR3: the "Chi tiết giao dịch" tab is disabled (greyed
    // out, not tappable) when no drawer is open. We watch the active drawer
    // id so the tab state rebuilds when the status resolves/invalidates.
    final activeDrawerId = _activeDrawerId;
    final transactionsEnabled = activeDrawerId != null;

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
              // DG-343 Phase 3 FR3: refresh the active drawer's transactions
              // too so the manual refresh button updates both views.
              if (activeDrawerId != null) {
                ref.invalidate(cashDrawerTransactionsProvider(
                  CashDrawerTransactionsFilter(drawerId: activeDrawerId),
                ));
              }
            },
          ),
          const AppBarOverflowMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          // DG-343 Phase 3 FR3: the 3rd tab is greyed out when no drawer is
          // open. Material's TabBar doesn't natively disable individual
          // tabs, so we override the label/unselected label color per-tab
          // via [labelColor]/[unselectedLabelColor] combined with the
          // snap-back listener in [initState] that prevents settling on
          // the disabled tab.
          tabs: [
            const Tab(
              icon: Icon(Icons.point_of_sale),
              text: VN.cashDrawerStatusOpen,
            ),
            const Tab(icon: Icon(Icons.history), text: VN.cashDrawerHistory),
            Tab(
              icon: Icon(
                Icons.receipt_long,
                color: transactionsEnabled ? null : Theme.of(context).disabledColor,
              ),
              text: VN.cashDrawerTransactionsTab,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ActiveTab(
            statusAsync: statusAsync,
            mutating: mutating,
            accountingBalance1101Async: accountingBalance1101Async,
            previousCloseAsync: previousCloseAsync,
            onOpen: () => _handleOpen(context),
            onCashIn: () => _handleCashIn(context),
            onCashOut: () => _handleCashOut(context),
            onClose: () => _handleClose(context),
          ),
          _HistoryTab(
            historyAsync: historyAsync,
            onTapClosedDrawer: _navigateToDrawerTransactions,
          ),
          // DG-343 Phase 3 FR3/AC1: the transaction list for the active
          // drawer. When no drawer is open, the tab is disabled by the
          // snap-back listener; this body is rendered but unreachable. We
          // still show a placeholder so the TabBarView has 3 children
          // (required by the TabController length).
          activeDrawerId == null
              ? const _DisabledTransactionsPlaceholder()
              : CashDrawerTransactionList(
                  drawerId: activeDrawerId,
                  poll: true,
                ),
        ],
      ),
    );
  }

  /// DG-343 Phase 3 FR4/AC2: navigate to a full-screen transaction detail
  /// view for a closed drawer. Reuses [CashDrawerTransactionList] with
  /// `poll: false` (closed drawers don't change) and infinite-scroll
  /// pagination via the family provider.
  void _navigateToDrawerTransactions(CashDrawer drawer) {
    final id = int.tryParse(drawer.id);
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DrawerTransactionsScreen(drawer: drawer, drawerId: id),
      ),
    );
  }

  Future<void> _handleOpen(BuildContext context) async {
    // FR2: read the balance providers defensively. If either provider is in
    // an error state, `ref.read(...future)` throws — wrapping in try-catch
    // prevents the open dialog from silently failing to appear. On error
    // we fall back to 0 / null so the dialog still opens; the user can see
    // the reference lines as "—" or the default values.
    int accountingBalance1101 = 0;
    int? previousClose;
    try {
      previousClose = await ref.read(cashDrawerPreviousCloseProvider.future);
    } on Exception catch (e, st) {
      debugPrint('cashDrawerPreviousCloseProvider failed: $e\n$st');
      // CQ-4: invalidate the failed async provider so the cached error does
      // not persist until the 30s poll — the next read re-fetches fresh.
      ref.invalidate(cashDrawerPreviousCloseProvider);
      previousClose = null;
    }
    try {
      accountingBalance1101 =
          await ref.read(cashDrawerAccountingBalance1101Provider.future);
    } on Exception catch (e, st) {
      debugPrint('cashDrawerAccountingBalance1101Provider failed: $e\n$st');
      // CQ-4: invalidate the failed async provider so the cached error does
      // not persist until the 30s poll — the next read re-fetches fresh.
      ref.invalidate(cashDrawerAccountingBalance1101Provider);
      accountingBalance1101 = 0;
    }
    if (!context.mounted) return;
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
        await service.closeDrawer(
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
            const SnackBar(content: Text(VN.cashDrawerCloseSuccess)),
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
    required this.accountingBalance1101Async,
    required this.previousCloseAsync,
    required this.onOpen,
    required this.onCashIn,
    required this.onCashOut,
    required this.onClose,
  });

  final AsyncValue<CashDrawer?> statusAsync;
  final bool mutating;
  final AsyncValue<int> accountingBalance1101Async;
  final AsyncValue<int?> previousCloseAsync;
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
          return _EmptyActiveView(
            onOpen: onOpen,
            mutating: mutating,
            accountingBalance1101Async: accountingBalance1101Async,
            previousCloseAsync: previousCloseAsync,
          );
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
  const _EmptyActiveView({
    required this.onOpen,
    required this.mutating,
    required this.accountingBalance1101Async,
    required this.previousCloseAsync,
  });

  final Future<void> Function() onOpen;
  final bool mutating;
  final AsyncValue<int> accountingBalance1101Async;
  final AsyncValue<int?> previousCloseAsync;

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
            // FR1/AC1: render the 1101 reference balance line only when the
            // provider has resolved to a positive value. While loading, show
            // a small inline placeholder so the line does not silently
            // disappear on slow networks (PWA bug root cause). On error, the
            // line is omitted rather than crashing the whole screen.
            accountingBalance1101Async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (balance1101) {
                if (balance1101 <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${VN.cashDrawerReferenceBalance}: ${formatVND(balance1101.toDouble())}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              },
            ),
            previousCloseAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (previousClose) {
                if (previousClose == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${VN.cashDrawerPreviousCloseBalance}: ${formatVND(previousClose.toDouble())}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              },
            ),
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
  const _HistoryTab({required this.historyAsync, this.onTapClosedDrawer});

  final AsyncValue<CashDrawerHistoryResponse> historyAsync;

  /// DG-343 Phase 3 FR4/AC2: invoked when the user taps a closed drawer row.
  /// The screen pushes a transaction-detail route for that drawer.
  final void Function(CashDrawer drawer)? onTapClosedDrawer;

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
        child: CashDrawerHistoryList(
          items: resp.items,
          onTapClosedDrawer: onTapClosedDrawer,
        ),
      ),
    );
  }
}

/// DG-343 Phase 3 FR3: placeholder shown in the "Chi tiết giao dịch" tab
/// body when no drawer is open. The tab itself is disabled (snap-back to the
/// status tab via the [TabController] listener in [_CashDrawerScreenState]),
/// so this widget is rendered but not interactive — it exists solely so the
/// [TabBarView] has 3 children matching the [TabController] length.
class _DisabledTransactionsPlaceholder extends StatelessWidget {
  const _DisabledTransactionsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long,
              size: 48,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 12),
            Text(
              VN.cashDrawerNoActive,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DG-343 Phase 3 FR4/AC2: full-screen transaction detail view for a closed
/// drawer. Pushed by [_CashDrawerScreenState._navigateToDrawerTransactions]
/// when the user taps a closed drawer in the History tab. Reuses
/// [CashDrawerTransactionList] with `poll: false` (closed drawers don't
/// change) and infinite-scroll pagination.
class _DrawerTransactionsScreen extends StatelessWidget {
  const _DrawerTransactionsScreen({
    required this.drawer,
    required this.drawerId,
  });

  final CashDrawer drawer;
  final int drawerId;

  @override
  Widget build(BuildContext context) {
    final title = '${VN.cashDrawerTransactionsTab} — ${formatDisplayDate(drawer.openedAt)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: CashDrawerTransactionList(
        drawerId: drawerId,
        poll: false,
      ),
    );
  }
}
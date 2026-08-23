import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cash_drawer_service.dart';
import '../../data/api/staff_service.dart';
import '../../data/models/cash_drawer.dart';
import '../../data/providers/cash_drawer_provider.dart';
import '../../data/providers/staff_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../providers/form_draft_session_notifier.dart';
import 'providers/cash_drawer_selector_notifier.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/cash_drawer_action_dialogs.dart';
import 'widgets/cash_drawer_active_tab.dart';
import 'widgets/cash_drawer_disabled_transactions_placeholder.dart';
import 'widgets/cash_drawer_drawer_transactions_screen.dart';
import 'widgets/cash_drawer_history_tab.dart';
import 'widgets/cash_drawer_transaction_list.dart';

/// Tracks whether a cash-drawer mutation (open / cash-in / cash-out / close)
/// is in-flight so the action buttons can be disabled and a snackbar shown.
///
/// Sync state per §4 of docs/flutter-coding-standards.md → `Notifier<bool>`.
class _CashDrawerMutationNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(formDraftSessionEpochProvider);
    return false;
  }

  Future<bool> run(
    BuildContext context,
    Future<CashDrawer> Function() action,
    String successMessage,
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
        ref.invalidate(
          cashDrawerTransactionsProvider(
            CashDrawerTransactionsFilter(drawerId: activeDrawerId),
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${SharedLabels.apiError}: $e')));
      }
      return false;
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
      if (_tabController.index == _transactionsTabIndex &&
          !_transactionsTabEnabled) {
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
    // DG-359 Phase 2 FR4/AC3: also invalidate the active drawer's first
    // transaction page so the breakdown card on the status tab refreshes
    // within 30 seconds of a new transaction — reusing the same polling
    // cycle (no extra API call beyond the existing transaction fetch).
    _statusPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ref.invalidate(cashDrawerStatusProvider);
      final activeDrawerId = _activeDrawerId;
      if (activeDrawerId != null) {
        ref.invalidate(
          cashDrawerTransactionsProvider(
            CashDrawerTransactionsFilter(drawerId: activeDrawerId),
          ),
        );
      }
    });
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

  /// DG-379 Phase 4.3 (FR7, AC5): whether the active drawer is reconciled.
  /// When `true`, the transaction list hides the edit affordance and shows a
  /// lock-notice snackbar on tap. Defaults to `false` when no drawer is open.
  bool get _activeDrawerReconciled {
    final drawer = ref.read(cashDrawerStatusProvider).value;
    return drawer?.reconciled ?? false;
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
    final historyAsync = ref.watch(
      cashDrawerHistoryProvider(const CashDrawerHistoryFilter()),
    );
    final mutating = ref.watch(_mutationInProgressProvider);
    final accountingBalance1101Async = ref.watch(
      cashDrawerAccountingBalance1101Provider,
    );
    final previousCloseAsync = ref.watch(cashDrawerPreviousCloseProvider);

    // DG-343 Phase 3 FR3: the "Chi tiết giao dịch" tab is disabled (greyed
    // out, not tappable) when no drawer is open. We watch the active drawer
    // id so the tab state rebuilds when the status resolves/invalidates.
    final activeDrawerId = _activeDrawerId;
    final transactionsEnabled = activeDrawerId != null;

    // DG-359 Phase 2 FR6: watch the active drawer's first transaction page so
    // the breakdown card on the status tab rebuilds when the provider is
    // invalidated (30s poll, manual refresh, mutation). NFR2: no extra API
    // call — reuses the same `cashDrawerTransactionsProvider` page the
    // transaction tab would fetch.
    final transactionsResponseAsync = activeDrawerId == null
        ? null
        : ref.watch(
            cashDrawerTransactionsProvider(
              CashDrawerTransactionsFilter(drawerId: activeDrawerId),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text(CashDrawerLabels.cashDrawerTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: SharedLabels.lamMoi,
            onPressed: () {
              ref.invalidate(cashDrawerStatusProvider);
              ref.invalidate(cashDrawerHistoryProvider);
              // DG-343 Phase 3 FR3: refresh the active drawer's transactions
              // too so the manual refresh button updates both views.
              if (activeDrawerId != null) {
                ref.invalidate(
                  cashDrawerTransactionsProvider(
                    CashDrawerTransactionsFilter(drawerId: activeDrawerId),
                  ),
                );
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
              text: CashDrawerLabels.cashDrawerStatusOpen,
            ),
            const Tab(
              icon: Icon(Icons.history),
              text: CashDrawerLabels.cashDrawerHistory,
            ),
            Tab(
              icon: Icon(
                Icons.receipt_long,
                color: transactionsEnabled
                    ? null
                    : Theme.of(context).disabledColor,
              ),
              text: CashDrawerLabels.cashDrawerTransactionsTab,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CashDrawerActiveTab(
            statusAsync: statusAsync,
            transactionsResponseAsync: transactionsResponseAsync,
            mutating: mutating,
            accountingBalance1101Async: accountingBalance1101Async,
            previousCloseAsync: previousCloseAsync,
            onOpen: () => _handleOpen(context),
            onCashIn: () => _handleCashIn(context),
            onCashOut: () => _handleCashOut(context),
            onClose: () => _handleClose(context),
          ),
          CashDrawerHistoryTab(
            historyAsync: historyAsync,
            onTapClosedDrawer: _navigateToDrawerTransactions,
          ),
          // DG-343 Phase 3 FR3/AC1: the transaction list for the active
          // drawer. When no drawer is open, the tab is disabled by the
          // snap-back listener; this body is rendered but unreachable. We
          // still show a placeholder so the TabBarView has 3 children
          // (required by the TabController length).
          activeDrawerId == null
              ? const CashDrawerDisabledTransactionsPlaceholder()
              : CashDrawerTransactionList(
                  drawerId: activeDrawerId,
                  poll: true,
                  reconciled: _activeDrawerReconciled,
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
        builder: (_) =>
            CashDrawerDrawerTransactionsScreen(drawer: drawer, drawerId: id),
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
      accountingBalance1101 = await ref.read(
        cashDrawerAccountingBalance1101Provider.future,
      );
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
      ref,
      referenceBalance: accountingBalance1101,
      previousCloseCountedAmount: previousClose,
    );
    if (result == null || !context.mounted) return;

    // DG-360 Phase 2 FR7: the open flow now mirrors the close flow's
    // surplus/shortage proposal pattern. The backend raises 409 with a
    // `surplusProposal` (opening > 1101 reference) or `shortageProposal`
    // (opening < 1101 reference); the service decodes these into
    // [CloseSurplusProposalException]/[CloseShortageProposalException] so
    // we can reuse the existing close confirmation dialogs. The old
    // transfer/excess/unidentified-sale flags are gone — the backend's
    // `OpenDrawerRequest` now accepts `surplusConfirmed`/`surplusSource`/
    // `shortageConfirmed`/`shortageSource`, matching `CloseDrawerRequest`.
    bool carryOverConfirmed = false;
    bool surplusConfirmed = false;
    String? surplusSource;
    bool shortageConfirmed = false;
    String? shortageSource;

    while (true) {
      try {
        await ref
            .read(cashDrawerServiceProvider)
            .openDrawer(
              openingBalance: result.amount,
              note: result.note,
              carryOverConfirmed: carryOverConfirmed,
              surplusConfirmed: surplusConfirmed,
              surplusSource: surplusSource,
              shortageConfirmed: shortageConfirmed,
              shortageSource: shortageSource,
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
        // CQ-4: the flag confirms awareness of the carry-over, not
        // acceptance — sending `true` on both accept and decline avoids
        // re-looping the 409 proposal.
        carryOverConfirmed = true;
      } on CloseSurplusProposalException catch (e) {
        if (!context.mounted) return;
        final decision = await showCloseSurplusDialog(
          context,
          expectedBalance: e.expectedBalance,
          countedAmount: e.countedAmount,
          surplus: e.surplus,
          openFlow: true,
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
          openFlow: true,
        );
        if (decision == null || !context.mounted) return;
        shortageConfirmed = true;
        shortageSource = decision == CloseShortageDecision.ownerWithdraw
            ? 'owner_withdraw'
            : 'equity_loss';
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${SharedLabels.apiError}: $e')));
        return;
      }
    }
  }

  void _onOpenSuccess(BuildContext context) {
    ref.invalidate(cashDrawerStatusProvider);
    ref.invalidate(cashDrawerHistoryProvider);
    ref.invalidate(cashDrawerAccountingBalance1101Provider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(CashDrawerLabels.cashDrawerOpenSuccess)),
      );
    }
  }

  Future<void> _handleCashIn(BuildContext context) async {
    final staff = ref.read(staffListProvider).value ?? const <StaffMember>[];
    // Phase 4.1 F5: show the current expected balance as helper text so the
    // owner knows how much is already in the drawer.
    final drawer = ref.read(cashDrawerStatusProvider).value;
    final draftContext = cashDrawerActionContext(
      drawer?.id ?? 'active',
      'cash-in',
    );
    final expectedBalance = drawer?.expectedBalance ?? 0;
    final result = await showCashInDialog(
      context,
      ref,
      staff: staff,
      expectedBalance: expectedBalance,
      drawerId: drawer?.id ?? 'active',
    );
    if (result == null || !context.mounted) return;
    final operation = ref.read(_mutationInProgressProvider.notifier);
    final service = ref.read(cashDrawerServiceProvider);
    final registry = ref.read(formDraftSessionProvider.notifier);
    final submittedDraft =
        ref.read(formDraftSessionProvider)[draftContext]
            as CashDrawerSelectorState?;
    final succeeded = await operation.run(
      context,
      () => service.cashIn(
        amount: result.amount,
        note: result.note,
        source: result.source ?? 'equity',
        staffName: result.staffName,
      ),
      CashDrawerLabels.cashDrawerCashInSuccess,
    );
    if (succeeded && submittedDraft != null) {
      registry.clearDraftIfUnchanged(draftContext, submittedDraft);
    }
  }

  Future<void> _handleCashOut(BuildContext context) async {
    final staff = ref.read(staffListProvider).value ?? const <StaffMember>[];
    // Phase 4.1 F6: show the current expected balance as helper text so the
    // owner knows how much they can withdraw.
    final drawer = ref.read(cashDrawerStatusProvider).value;
    final draftContext = cashDrawerActionContext(
      drawer?.id ?? 'active',
      'cash-out',
    );
    final expectedBalance = drawer?.expectedBalance ?? 0;
    final result = await showCashOutDialog(
      context,
      ref,
      staff: staff,
      expectedBalance: expectedBalance,
      drawerId: drawer?.id ?? 'active',
    );
    if (result == null || !context.mounted) return;
    final operation = ref.read(_mutationInProgressProvider.notifier);
    final service = ref.read(cashDrawerServiceProvider);
    final registry = ref.read(formDraftSessionProvider.notifier);
    final submittedDraft =
        ref.read(formDraftSessionProvider)[draftContext]
            as CashDrawerSelectorState?;
    final succeeded = await operation.run(
      context,
      () => service.cashOut(
        amount: result.amount,
        note: result.note,
        destination: result.destination ?? 'owner',
        staffName: result.staffName,
      ),
      CashDrawerLabels.cashDrawerCashOutSuccess,
    );
    if (succeeded && submittedDraft != null) {
      registry.clearDraftIfUnchanged(draftContext, submittedDraft);
    }
  }

  Future<void> _handleClose(BuildContext context) async {
    final drawer = ref.read(cashDrawerStatusProvider).value;
    if (drawer == null) return;
    // Phase 4.1 F4: surface the 1101 accounting balance below the expected
    // balance for reconciliation reference.
    final result = await showCloseDrawerDialog(
      context,
      ref,
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
        ref.invalidate(cashDrawerAccountingBalance1101Provider);
        ref.invalidate(cashDrawerPreviousCloseProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(CashDrawerLabels.cashDrawerCloseSuccess),
            ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${SharedLabels.apiError}: $e')));
        return;
      }
    }
  }
}

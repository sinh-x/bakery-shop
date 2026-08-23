import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/labels/shared.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Order print-checklist dialog state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_printInternal`, `_printCustomer`, `_printing`, and
/// `_statusText` fields previously mutated via `setState` inside
/// `_OrderPrintChecklistDialogState`. The widget reads
/// [orderPrintChecklistProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderPrintChecklistState {
  const OrderPrintChecklistState({
    this.printInternal = true,
    this.printCustomer = true,
    this.printing = false,
    this.statusText = '',
  });

  final bool printInternal;
  final bool printCustomer;
  final bool printing;
  final String statusText;

  bool get isDirty => !printInternal || !printCustomer;

  OrderPrintChecklistState copyWith({
    bool? printInternal,
    bool? printCustomer,
    bool? printing,
    String? statusText,
  }) => OrderPrintChecklistState(
    printInternal: printInternal ?? this.printInternal,
    printCustomer: printCustomer ?? this.printCustomer,
    printing: printing ?? this.printing,
    statusText: statusText ?? this.statusText,
  );
}

class OrderPrintChecklistNotifier extends Notifier<OrderPrintChecklistState> {
  OrderPrintChecklistNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderPrintChecklistState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderPrintChecklistState(),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const OrderPrintChecklistState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<OrderPrintChecklistState>(context) ??
        const OrderPrintChecklistState();
  }

  void _setDraft(OrderPrintChecklistState next) {
    state = next;
    final drafts = ref.read(formDraftSessionProvider.notifier);
    if (next.isDirty) {
      drafts.retainDraft(
        context,
        next.copyWith(printing: false, statusText: ''),
      );
    } else {
      drafts.clearDraft(context);
    }
  }

  void setPrintInternal(bool value) =>
      _setDraft(state.copyWith(printInternal: value));

  void setPrintCustomer(bool value) =>
      _setDraft(state.copyWith(printCustomer: value));

  /// Auto-disable the internal-receipt checkbox when there are no main items
  /// to print. Mirrors the inline `_printInternal = false` write that
  /// previously ran in `build`.
  void autoDisableInternalIfNoMainItems(bool hasMainItems) {
    if (!hasMainItems && state.printInternal) {
      _setDraft(state.copyWith(printInternal: false));
    }
  }

  void startPrinting() =>
      state = state.copyWith(printing: true, statusText: '');

  void setStatusText(String text) => state = state.copyWith(statusText: text);

  void finishPrinting() => state = state.copyWith(printing: false);

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const OrderPrintChecklistState();
  }
}

final orderPrintChecklistProvider =
    NotifierProvider.family<
      OrderPrintChecklistNotifier,
      OrderPrintChecklistState,
      FormDraftContext
    >(OrderPrintChecklistNotifier.new);

/// Internal-receipt print dialog (post-confirm work-item prompt) state
/// (DG-404 Phase 4.6 / FR2). Same shape as the checklist dialog but without
/// the checkboxes.
class OrderInternalPrintNotifier extends Notifier<OrderPrintChecklistState> {
  OrderInternalPrintNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderPrintChecklistState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderPrintChecklistState(),
    );
    return const OrderPrintChecklistState();
  }

  void startPrinting() => state = state.copyWith(
    printing: true,
    statusText: SharedLabels.printingInternalReceipt,
  );

  void setStatusText(String text) => state = state.copyWith(statusText: text);

  void finishPrinting() => state = state.copyWith(printing: false);
}

final orderInternalPrintProvider =
    NotifierProvider.family<
      OrderInternalPrintNotifier,
      OrderPrintChecklistState,
      FormDraftContext
    >(OrderInternalPrintNotifier.new);

/// Generic single-item internal print dialog state (used by the
/// `OrderInternalPrintDialog` in `widgets/order_detail/`). Same shape as
/// the checklist variant — kept as a separate provider so the two dialogs
/// do not share state when both are mounted.
class OrderWorkItemPrintNotifier extends Notifier<OrderPrintChecklistState> {
  OrderWorkItemPrintNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderPrintChecklistState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderPrintChecklistState(),
    );
    return const OrderPrintChecklistState();
  }

  void startPrinting() => state = state.copyWith(
    printing: true,
    statusText: SharedLabels.printingInternalReceipt,
  );

  void setStatusText(String text) => state = state.copyWith(statusText: text);

  void finishPrinting() => state = state.copyWith(printing: false);
}

final orderWorkItemPrintProvider =
    NotifierProvider.family<
      OrderWorkItemPrintNotifier,
      OrderPrintChecklistState,
      FormDraftContext
    >(OrderWorkItemPrintNotifier.new);

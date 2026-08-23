import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/form_draft_context.dart';
import '../../../providers/form_draft_session_notifier.dart';

class OrderFormOperationState {
  const OrderFormOperationState({this.busy = false, this.error});

  final bool busy;
  final Object? error;
}

class OrderFormOperationNotifier extends Notifier<OrderFormOperationState> {
  OrderFormOperationNotifier(this.context);

  final FormDraftContext context;
  int _generation = 0;

  @override
  OrderFormOperationState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      _generation++;
      state = const OrderFormOperationState();
    });
    return const OrderFormOperationState();
  }

  int start() {
    state = const OrderFormOperationState(busy: true);
    return ++_generation;
  }

  void fail(Object error) => state = OrderFormOperationState(error: error);

  void failIfCurrent(int generation, Object error) {
    if (generation == _generation) fail(error);
  }

  bool isCurrent(int generation) => generation == _generation;

  void finish() => state = const OrderFormOperationState();

  void finishIfCurrent(int generation) {
    if (generation == _generation) finish();
  }
}

final orderFormOperationProvider =
    NotifierProvider.family<
      OrderFormOperationNotifier,
      OrderFormOperationState,
      FormDraftContext
    >(OrderFormOperationNotifier.new);

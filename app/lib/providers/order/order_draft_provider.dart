import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order_draft.dart';

class OrderDraftNotifier extends Notifier<OrderDraft?> {
  @override
  OrderDraft? build() => null;

  void save(OrderDraft draft) => state = draft;
  void clear() => state = null;
}

final orderDraftProvider = NotifierProvider<OrderDraftNotifier, OrderDraft?>(
  OrderDraftNotifier.new,
);

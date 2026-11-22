import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentDestinationQueryNotifier extends Notifier<(String, int)> {
  @override
  (String, int) build() => ('', 0);

  void search(String value) => state = (value.trim(), 0);
  void nextPage() => state = (state.$1, state.$2 + 50);
  void previousPage() => state = (state.$1, (state.$2 - 50).clamp(0, state.$2));
}

final paymentDestinationQueryProvider =
    NotifierProvider.autoDispose<
      PaymentDestinationQueryNotifier,
      (String, int)
    >(PaymentDestinationQueryNotifier.new);

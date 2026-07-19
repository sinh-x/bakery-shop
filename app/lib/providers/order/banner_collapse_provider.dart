import 'package:flutter_riverpod/flutter_riverpod.dart';

final urgencyBannerCollapsedProvider =
    NotifierProvider<_UrgencyBannerCollapsedNotifier, bool>(
  _UrgencyBannerCollapsedNotifier.new,
);

class _UrgencyBannerCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final incompleteBannerCollapsedProvider =
    NotifierProvider<_IncompleteBannerCollapsedNotifier, bool>(
  _IncompleteBannerCollapsedNotifier.new,
);

class _IncompleteBannerCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

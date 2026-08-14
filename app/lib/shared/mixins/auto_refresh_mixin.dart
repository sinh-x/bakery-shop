import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A mixin that provides manual (button-triggered) data refresh for
/// data-list screens.
///
/// Auto-refresh is disabled app-wide: the 15-second [Timer.periodic], the
/// app-resume refresh, and the navigate-back refresh were removed. Screens
/// now refresh only when the user taps the refresh button, which invokes
/// [onAutoRefreshTriggered].
///
/// Screens apply this mixin to their `ConsumerState` and override:
/// - [invalidateProviders] to call `ref.invalidate(...)` on the screen's
///   Riverpod providers (or [onAutoRefresh] for screens with local state).
/// - [screenRoutePath] to return the screen's GoRouter path (retained for
///   API compatibility; no longer used by this mixin).
///
/// The lifecycle hooks [initAutoRefresh], [setupAutoRefreshRouteListener],
/// and [disposeAutoRefresh] are retained as documented no-ops so existing
/// screens compile unchanged without starting any timer or listener.
mixin AutoRefreshMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  /// Invalidates the screen's Riverpod providers on each refresh tick.
  ///
  /// Override this in screens backed by Riverpod and call `ref.invalidate`
  /// for each provider that should refresh. Screens that use local state may
  /// leave this as a no-op and set [onAutoRefresh] instead.
  void invalidateProviders() {}

  /// The GoRouter path that identifies this screen.
  ///
  /// Retained for API compatibility; no longer used to detect navigation.
  String screenRoutePath();

  /// Optional callback for screens with local state (e.g. ExpenseScreen).
  ///
  /// When non-null, it is invoked when the user taps the refresh button
  /// instead of [invalidateProviders].
  void Function()? onAutoRefresh;

  /// Hook invoked when the user taps the refresh button.
  ///
  /// The default implementation invokes [onAutoRefresh] when set, otherwise
  /// calls [invalidateProviders].
  @mustCallSuper
  void onAutoRefreshTriggered() {
    final cb = onAutoRefresh;
    if (cb != null) {
      cb();
      return;
    }
    invalidateProviders();
  }

  /// No-op — auto-refresh (timer + lifecycle observer) is disabled app-wide.
  @mustCallSuper
  void initAutoRefresh() {}

  /// No-op — the GoRouter route-change listener is disabled app-wide.
  @mustCallSuper
  void setupAutoRefreshRouteListener() {}

  /// No-op — no app-lifecycle refresh (manual refresh only).
  @mustCallSuper
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  /// No-op — nothing to tear down (auto-refresh is disabled).
  @mustCallSuper
  void disposeAutoRefresh() {}
}

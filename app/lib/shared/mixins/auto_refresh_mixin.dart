import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A mixin that provides automatic data refresh for data-list screens.
///
/// Screens apply this mixin to their `ConsumerState` and override:
/// - [invalidateProviders] to call `ref.invalidate(...)` on the screen's
///   Riverpod providers (or [onAutoRefresh] for screens with local state).
/// - [screenRoutePath] to return the screen's GoRouter path so the mixin can
///   detect navigate-away / return transitions.
///
/// The mixin manages three refresh triggers:
/// 1. A 15-second [Timer.periodic] that fires while the screen is visible.
/// 2. A [WidgetsBindingObserver] that refreshes on `AppLifecycleState.resumed`
///    and cancels the timer on `paused`.
/// 3. A GoRouter listener that refreshes when the user navigates back to this
///    screen and cancels the timer when navigating away.
///
/// Screens that use local state instead of Riverpod providers (e.g.
/// ExpenseScreen) may set [onAutoRefresh] — when non-null, it is invoked
/// instead of [invalidateProviders].
///
/// The timer is cancelled on navigate-away, on app background, and in
/// [dispose], guaranteeing no timer leaks (NFR3).
mixin AutoRefreshMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  static const Duration refreshInterval = Duration(seconds: 15);

  Timer? _autoRefreshTimer;
  GoRouter? _goRouter;
  bool _wasNavigatedAway = false;
  bool _isLifecyclePaused = false;

  /// Invalidates the screen's Riverpod providers on each refresh tick.
  ///
  /// Override this in screens backed by Riverpod and call `ref.invalidate`
  /// for each provider that should refresh. Screens that use local state may
  /// leave this as a no-op and set [onAutoRefresh] instead.
  void invalidateProviders() {}

  /// The GoRouter path that identifies this screen.
  ///
  /// Used to detect when the user navigates back to this screen.
  String screenRoutePath();

  /// Optional callback for screens with local state (e.g. ExpenseScreen).
  ///
  /// When non-null, it is invoked on each refresh tick instead of
  /// [invalidateProviders].
  void Function()? onAutoRefresh;

  /// Hook invoked on each refresh tick (timer, route return, app resume).
  ///
  /// The default implementation invokes [onAutoRefresh] when set, otherwise
  /// calls [invalidateProviders]. Screens rarely need to override this.
  @mustCallSuper
  void onAutoRefreshTriggered() {
    final cb = onAutoRefresh;
    if (cb != null) {
      cb();
      return;
    }
    invalidateProviders();
  }

  /// Starts the 15-second periodic timer.
  ///
  /// Safe to call multiple times — an existing timer is cancelled first.
  void startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) {
      if (!mounted) return;
      onAutoRefreshTriggered();
    });
  }

  /// Cancels the periodic timer without touching listeners.
  void stopAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// Wires up the WidgetsBindingObserver and GoRouter route-change listener.
  ///
  /// Call from the screen's `initState` via `super` chain, or invoke
  /// directly. Starts the periodic timer immediately.
  @mustCallSuper
  void initAutoRefresh() {
    WidgetsBinding.instance.addObserver(this);
    startAutoRefreshTimer();
  }

  /// Wires up the GoRouter route-change listener.
  ///
  /// Call from the screen's `didChangeDependencies` via `super` chain, or
  /// invoke directly.
  @mustCallSuper
  void setupAutoRefreshRouteListener() {
    try {
      final router = GoRouter.of(context);
      if (_goRouter != router) {
        _goRouter?.routerDelegate.removeListener(_handleRouteChange);
        _goRouter = router;
        _goRouter?.routerDelegate.addListener(_handleRouteChange);
      }
    } catch (_) {
      // No GoRouter in context (e.g. test environment) — skip route listener.
      // Timer and lifecycle observer still function.
    }
  }

  /// Handles app lifecycle transitions.
  ///
  /// - `paused` → cancel timer.
  /// - `resumed` → immediate refresh + restart timer.
  @mustCallSuper
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isLifecyclePaused = true;
      stopAutoRefreshTimer();
    } else if (state == AppLifecycleState.resumed) {
      if (_isLifecyclePaused) {
        _isLifecyclePaused = false;
        if (mounted) {
          onAutoRefreshTriggered();
          startAutoRefreshTimer();
        }
      }
    }
  }

  /// Tears down the timer and listeners.
  ///
  /// Call from the screen's `dispose` via `super` chain, or invoke directly.
  @mustCallSuper
  void disposeAutoRefresh() {
    _goRouter?.routerDelegate.removeListener(_handleRouteChange);
    _goRouter = null;
    stopAutoRefreshTimer();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _handleRouteChange() {
    if (!mounted) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == screenRoutePath() && _wasNavigatedAway) {
      _wasNavigatedAway = false;
      onAutoRefreshTriggered();
      startAutoRefreshTimer();
    } else if (path != screenRoutePath()) {
      _wasNavigatedAway = true;
      stopAutoRefreshTimer();
    }
  }
}
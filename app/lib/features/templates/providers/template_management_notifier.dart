import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the template management screen (DG-404 Phase 4.3 / FR2).
///
/// Owns the currently selected tab index (0 = system, 1 = personal)
/// previously re-read via `_tabController.index` and an empty
/// `setState(() {})` rebuild inside `_TemplateManagementScreenState`. The
/// widget reads [templateManagementProvider] and rebuilds on change — no
/// `setState` is required.
class TemplateManagementState {
  const TemplateManagementState({this.tabIndex = 0});

  /// 0 = system templates tab, 1 = personal templates tab.
  final int tabIndex;

  bool get isSystemTab => tabIndex == 0;

  TemplateManagementState copyWith({int? tabIndex}) =>
      TemplateManagementState(tabIndex: tabIndex ?? this.tabIndex);
}

/// `Notifier` that owns the template-management screen state
/// (DG-404 Phase 4.3 / FR2).
///
/// All mutations that previously triggered `setState` rebuilds inside
/// `_TemplateManagementScreenState` are now exposed as notifier methods.
/// The widget reads the state via [templateManagementProvider] and
/// rebuilds on change — no `setState` is required.
class TemplateManagementNotifier extends Notifier<TemplateManagementState> {
  @override
  TemplateManagementState build() => const TemplateManagementState();

  /// Update the selected tab index (driven by `TabBar.onTap`).
  void setTabIndex(int index) =>
      state = state.copyWith(tabIndex: index);
}

/// Provider for the template-management screen state. The widget reads
/// this and calls the notifier's mutators; no `setState` is required.
final templateManagementProvider = NotifierProvider<TemplateManagementNotifier,
    TemplateManagementState>(TemplateManagementNotifier.new);
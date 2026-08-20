import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the template picker modal (DG-404 Phase 4.3 / FR2).
///
/// Owns the currently expanded template id and the per-template
/// "copied" flag previously held as `setState` fields inside
/// `_TemplatePickerModalState`. The widget reads
/// [templatePickerProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class TemplatePickerState {
  const TemplatePickerState({this.expandedId, this.copiedId});

  /// The id of the template whose preview is expanded, or `null` when
  /// no preview is open.
  final int? expandedId;

  /// The id of the template whose body was just copied to the clipboard
  /// (drives the check icon / "Đã sao chép" label), or `null` when no
  /// copy is active.
  final int? copiedId;

  bool isExpanded(int id) => expandedId == id;
  bool isCopied(int id) => copiedId == id && expandedId == id;

  TemplatePickerState copyWith({int? expandedId, int? copiedId}) =>
      TemplatePickerState(
        expandedId: expandedId ?? this.expandedId,
        copiedId: copiedId ?? this.copiedId,
      );
}

/// `Notifier` that owns the template-picker modal state (DG-404 Phase
/// 4.3 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_TemplatePickerModalState` are now exposed as notifier methods. The
/// widget reads the state via [templatePickerProvider] and rebuilds on
/// change — no `setState` is required.
class TemplatePickerNotifier extends Notifier<TemplatePickerState> {
  @override
  TemplatePickerState build() => const TemplatePickerState();

  /// Toggle the expanded preview for [id]; collapses when tapping the
  /// already-expanded row. Resets the copied flag.
  void toggleExpanded(int id) {
    final next = state.expandedId == id ? null : id;
    state = TemplatePickerState(expandedId: next);
  }

  /// Mark [id] as just copied (drives the check icon on the copy
  /// button). The copied flag is cleared on the next expand toggle.
  void markCopied(int id) =>
      state = state.copyWith(copiedId: id);
}

/// Provider for the template-picker modal state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final templatePickerProvider = NotifierProvider<TemplatePickerNotifier,
    TemplatePickerState>(TemplatePickerNotifier.new);
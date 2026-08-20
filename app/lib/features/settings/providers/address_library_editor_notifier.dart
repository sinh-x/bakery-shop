import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the address-library editor dialog (DG-404 Phase 4.7).
///
/// Owns the inline validation errors (`addressError`, `linkError`) and
/// the `saving` flag previously held as `setState` fields inside
/// `_AddressLibraryEditorDialogState`. The widget reads
/// [addressLibraryEditorProvider] and invokes the notifier's mutators;
/// no `setState` is required.
class AddressLibraryEditorState {
  const AddressLibraryEditorState({
    this.addressError,
    this.linkError,
    this.saving = false,
  });

  final String? addressError;
  final String? linkError;
  final bool saving;

  AddressLibraryEditorState copyWith({
    String? addressError,
    String? linkError,
    bool? saving,
    bool clearAddressError = false,
    bool clearLinkError = false,
  }) {
    return AddressLibraryEditorState(
      addressError:
          clearAddressError ? null : (addressError ?? this.addressError),
      linkError: clearLinkError ? null : (linkError ?? this.linkError),
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the address-library editor dialog state
/// (DG-404 Phase 4.7). Sync state because all mutations are local.
class AddressLibraryEditorNotifier
    extends Notifier<AddressLibraryEditorState> {
  @override
  AddressLibraryEditorState build() => const AddressLibraryEditorState();

  void setAddressError(String? value) {
    if (value == null) {
      state = state.copyWith(clearAddressError: true);
    } else {
      state = state.copyWith(addressError: value);
    }
  }

  void setLinkError(String? value) {
    if (value == null) {
      state = state.copyWith(clearLinkError: true);
    } else {
      state = state.copyWith(linkError: value);
    }
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the address-library editor dialog state. The widget
/// reads this and calls the notifier's mutators; no `setState` is
/// required.
final addressLibraryEditorProvider =
    NotifierProvider<AddressLibraryEditorNotifier, AddressLibraryEditorState>(
  AddressLibraryEditorNotifier.new,
);
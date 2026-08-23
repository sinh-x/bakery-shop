import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

FormDraftContext addressLibraryEditorContext(int? entryId) => FormDraftContext(
  formType: 'address-library',
  mode: entryId == null ? FormDraftMode.create : FormDraftMode.edit,
  entityId: entryId?.toString(),
);

/// State for the address-library editor dialog (DG-404 Phase 4.7).
///
/// Owns the inline validation errors (`addressError`, `linkError`) and
/// the `saving` flag previously held as `setState` fields inside
/// `_AddressLibraryEditorDialogState`. The widget reads
/// [addressLibraryEditorProvider] and invokes the notifier's mutators;
/// no `setState` is required.
class AddressLibraryEditorState {
  const AddressLibraryEditorState({
    this.address = '',
    this.googleMapsUrl = '',
    this.addressError,
    this.linkError,
    this.saving = false,
  });

  final String address;
  final String googleMapsUrl;
  final String? addressError;
  final String? linkError;
  final bool saving;

  bool get isDirty => address.isNotEmpty || googleMapsUrl.isNotEmpty;

  AddressLibraryEditorState copyWith({
    String? address,
    String? googleMapsUrl,
    String? addressError,
    String? linkError,
    bool? saving,
    bool clearAddressError = false,
    bool clearLinkError = false,
  }) {
    return AddressLibraryEditorState(
      address: address ?? this.address,
      googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
      addressError: clearAddressError
          ? null
          : (addressError ?? this.addressError),
      linkError: clearLinkError ? null : (linkError ?? this.linkError),
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the address-library editor dialog state
/// (DG-404 Phase 4.7). Sync state because all mutations are local.
class AddressLibraryEditorNotifier extends Notifier<AddressLibraryEditorState> {
  AddressLibraryEditorNotifier(this.context);

  final FormDraftContext context;

  @override
  AddressLibraryEditorState build() {
    ref.watch(formDraftSessionEpochProvider);
    final drafts = ref.read(formDraftSessionProvider);
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const AddressLibraryEditorState();
      }
    });
    return drafts[context] as AddressLibraryEditorState? ??
        const AddressLibraryEditorState();
  }

  bool get hasRetainedDraft =>
      ref.read(formDraftSessionProvider).containsKey(context);

  void setAddress(String value) => _retain(state.copyWith(address: value));

  void setGoogleMapsUrl(String value) =>
      _retain(state.copyWith(googleMapsUrl: value));

  void updateDraft({
    required String address,
    required String googleMapsUrl,
    required bool isDirty,
  }) {
    final next = state.copyWith(address: address, googleMapsUrl: googleMapsUrl);
    state = next;
    final registry = ref.read(formDraftSessionProvider.notifier);
    if (isDirty) {
      registry.retainDraft(
        context,
        next.copyWith(
          saving: false,
          clearAddressError: true,
          clearLinkError: true,
        ),
      );
    } else {
      registry.clearDraft(context);
    }
  }

  void _retain(AddressLibraryEditorState next) {
    state = next;
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(
          context,
          next.copyWith(
            saving: false,
            clearAddressError: true,
            clearLinkError: true,
          ),
        );
  }

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

  void clear() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const AddressLibraryEditorState();
  }

  void resetOperation() => state = state.copyWith(
    saving: false,
    clearAddressError: true,
    clearLinkError: true,
  );
}

/// Provider for the address-library editor dialog state. The widget
/// reads this and calls the notifier's mutators; no `setState` is
/// required.
final addressLibraryEditorProvider =
    NotifierProvider.family<
      AddressLibraryEditorNotifier,
      AddressLibraryEditorState,
      FormDraftContext
    >(AddressLibraryEditorNotifier.new);

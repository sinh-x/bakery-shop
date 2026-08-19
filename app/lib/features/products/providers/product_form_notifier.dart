import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Form state for the product add/edit screen (DG-404 Phase 4.7 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_ProductFormScreenState`: `category`, `rutTien`, `trungBay`,
/// `tangKem`, `pickedPhoto`, `saving`, plus a `rebuildTick` counter
/// that drives rebuilds when the price-chip rows or enum-section rows
/// mutate their internal controller-backed state (the controllers stay
/// on the widget as acceptable-use; the notifier just signals rebuild).
class ProductFormState {
  const ProductFormState({
    this.category = 'banh_kem',
    this.rutTien = false,
    this.trungBay = false,
    this.tangKem = false,
    this.pickedPhoto,
    this.saving = false,
    this.rebuildTick = 0,
  });

  final String category;
  final bool rutTien;
  final bool trungBay;
  final bool tangKem;
  final XFile? pickedPhoto;
  final bool saving;
  final int rebuildTick;

  ProductFormState copyWith({
    String? category,
    bool? rutTien,
    bool? trungBay,
    bool? tangKem,
    XFile? pickedPhoto,
    bool? saving,
    int? rebuildTick,
  }) {
    return ProductFormState(
      category: category ?? this.category,
      rutTien: rutTien ?? this.rutTien,
      trungBay: trungBay ?? this.trungBay,
      tangKem: tangKem ?? this.tangKem,
      pickedPhoto: pickedPhoto ?? this.pickedPhoto,
      saving: saving ?? this.saving,
      rebuildTick: rebuildTick ?? this.rebuildTick,
    );
  }
}

/// `Notifier` that owns the product-form state (DG-404 Phase 4.7 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_ProductFormScreenState` are now exposed as notifier methods. The
/// widget reads the state via [productFormProvider] and rebuilds on
/// change — no `setState` is required. `TextEditingController`-backed
/// fields (name/price/cost/notes/code, plus price-chip and enum-section
/// row controllers) stay on the widget because their lifecycle is an
/// acceptable-use case per the DG-404 guardrails.
class ProductFormNotifier extends Notifier<ProductFormState> {
  @override
  ProductFormState build() => const ProductFormState();

  /// Seed the initial form state from the (optional) values supplied
  /// by the screen's `initState`. Called once before any mutation.
  void seed({
    String? initialCategory,
    bool? rutTien,
    bool? trungBay,
    bool? tangKem,
  }) {
    state = ProductFormState(
      category: initialCategory ?? 'banh_kem',
      rutTien: rutTien ?? false,
      trungBay: trungBay ?? false,
      tangKem: tangKem ?? false,
    );
  }

  void setCategory(String value) => state = state.copyWith(category: value);

  void setRutTien(bool value) => state = state.copyWith(rutTien: value);

  void setTrungBay(bool value) => state = state.copyWith(trungBay: value);

  void setTangKem(bool value) => state = state.copyWith(tangKem: value);

  void setPickedPhoto(XFile? file) =>
      state = state.copyWith(pickedPhoto: file);

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Bump the rebuild counter so the widget re-reads the
  /// controller-backed price-chip / enum-section row state. Replaces
  /// the pre-migration empty `setState(() {})` calls that drove
  /// rebuilds after the rows mutated their own state.
  void rebuild() => state = state.copyWith(rebuildTick: state.rebuildTick + 1);
}

/// Provider for the product-form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final productFormProvider =
    NotifierProvider<ProductFormNotifier, ProductFormState>(
        ProductFormNotifier.new);
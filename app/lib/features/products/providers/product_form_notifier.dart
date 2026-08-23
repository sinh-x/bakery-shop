import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const _unset = Object();

class ProductNewDraft {
  const ProductNewDraft({
    this.name = '',
    this.price = '',
    this.cost = '',
    this.notes = '',
    this.code = '',
    this.category = 'banh_kem',
    this.rutTien = false,
    this.trungBay = false,
    this.tangKem = false,
    this.priceChips = const <ProductPriceChipDraft>[],
    this.pickedPhoto,
    this.enumSections = const <ProductEnumSectionDraft>[],
  });

  final String name;
  final String price;
  final String cost;
  final String notes;
  final String code;
  final String category;
  final bool rutTien;
  final bool trungBay;
  final bool tangKem;
  final List<ProductPriceChipDraft> priceChips;
  final XFile? pickedPhoto;
  final List<ProductEnumSectionDraft> enumSections;

  ProductNewDraft copyWith({
    String? name,
    String? price,
    String? cost,
    String? notes,
    String? code,
    String? category,
    bool? rutTien,
    bool? trungBay,
    bool? tangKem,
    List<ProductPriceChipDraft>? priceChips,
    Object? pickedPhoto = _unset,
    List<ProductEnumSectionDraft>? enumSections,
  }) => ProductNewDraft(
    name: name ?? this.name,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    notes: notes ?? this.notes,
    code: code ?? this.code,
    category: category ?? this.category,
    rutTien: rutTien ?? this.rutTien,
    trungBay: trungBay ?? this.trungBay,
    tangKem: tangKem ?? this.tangKem,
    priceChips: priceChips ?? this.priceChips,
    pickedPhoto: identical(pickedPhoto, _unset)
        ? this.pickedPhoto
        : pickedPhoto as XFile?,
    enumSections: enumSections ?? this.enumSections,
  );
}

class ProductPriceChipDraft {
  const ProductPriceChipDraft({required this.label, required this.price});

  final String label;
  final String price;
}

class ProductEnumSectionDraft {
  const ProductEnumSectionDraft({
    required this.attributeType,
    required this.rows,
  });

  final String attributeType;
  final List<ProductEnumOptionDraft> rows;
}

class ProductEnumOptionDraft {
  const ProductEnumOptionDraft({
    required this.id,
    required this.value,
    required this.sortOrder,
    required this.active,
    required this.isDefault,
    required this.removed,
  });

  final int? id;
  final String value;
  final int sortOrder;
  final int active;
  final bool isDefault;
  final bool removed;
}

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
    this.editing = false,
  });

  final String category;
  final bool rutTien;
  final bool trungBay;
  final bool tangKem;
  final XFile? pickedPhoto;
  final bool saving;
  final int rebuildTick;
  final bool editing;

  ProductFormState copyWith({
    String? category,
    bool? rutTien,
    bool? trungBay,
    bool? tangKem,
    Object? pickedPhoto = _unset,
    bool? saving,
    int? rebuildTick,
    bool? editing,
  }) {
    return ProductFormState(
      category: category ?? this.category,
      rutTien: rutTien ?? this.rutTien,
      trungBay: trungBay ?? this.trungBay,
      tangKem: tangKem ?? this.tangKem,
      pickedPhoto: identical(pickedPhoto, _unset)
          ? this.pickedPhoto
          : pickedPhoto as XFile?,
      saving: saving ?? this.saving,
      rebuildTick: rebuildTick ?? this.rebuildTick,
      editing: editing ?? this.editing,
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
  ProductFormNotifier([this.context]);

  final FormDraftContext? context;
  ProductNewDraft _newDraft = const ProductNewDraft();
  bool _newDraftInitialized = false;
  bool _contextInitialized = false;

  ProductNewDraft get newDraft => _newDraft;
  ProductNewDraft get draftSnapshot => _newDraft;
  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);

  @override
  ProductFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDraft = const ProductNewDraft();
    _newDraftInitialized = false;
    _contextInitialized = false;
    if (context != null) {
      _newDraft =
          ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<ProductNewDraft>(context!) ??
          const ProductNewDraft();
      _newDraftInitialized = hasRetainedDraft;
      _contextInitialized = hasRetainedDraft;
    }
    return ProductFormState(
      category: _newDraft.category,
      rutTien: _newDraft.rutTien,
      trungBay: _newDraft.trungBay,
      tangKem: _newDraft.tangKem,
      pickedPhoto: _newDraft.pickedPhoto,
      editing: context?.mode == FormDraftMode.edit,
    );
  }

  /// Seed the initial form state from the (optional) values supplied
  /// by the screen's `initState`. Called once before any mutation.
  void seed({
    String? initialCategory,
    bool? rutTien,
    bool? trungBay,
    bool? tangKem,
    bool editing = false,
  }) {
    if (hasRetainedDraft) return;
    if (!editing) {
      if (!_newDraftInitialized) {
        _newDraft = _newDraft.copyWith(category: initialCategory ?? 'banh_kem');
        _newDraftInitialized = true;
      }
      state = ProductFormState(
        category: _newDraft.category,
        rutTien: _newDraft.rutTien,
        trungBay: _newDraft.trungBay,
        tangKem: _newDraft.tangKem,
      );
      _contextInitialized = true;
      return;
    }
    if (context != null) {
      _newDraft = _newDraft.copyWith(
        category: initialCategory ?? 'banh_kem',
        rutTien: rutTien ?? false,
        trungBay: trungBay ?? false,
        tangKem: tangKem ?? false,
      );
    }
    state = ProductFormState(
      category: initialCategory ?? 'banh_kem',
      rutTien: rutTien ?? false,
      trungBay: trungBay ?? false,
      tangKem: tangKem ?? false,
      editing: true,
    );
    _contextInitialized = true;
  }

  void updateNewDraft({
    String? name,
    String? price,
    String? cost,
    String? notes,
    String? code,
    List<ProductPriceChipDraft>? priceChips,
    List<ProductEnumSectionDraft>? enumSections,
  }) {
    _newDraft = _newDraft.copyWith(
      name: name,
      price: price,
      cost: cost,
      notes: notes,
      code: code,
      priceChips: priceChips,
      enumSections: enumSections,
    );
    _newDraftInitialized = true;
    _retain();
  }

  void clearNewDraft() {
    _newDraft = const ProductNewDraft();
    _newDraftInitialized = false;
    state = const ProductFormState();
    if (context != null && _contextInitialized) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(ProductNewDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _newDraft = const ProductNewDraft();
      _newDraftInitialized = false;
      state = const ProductFormState();
    }
    return cleared;
  }

  void setCategory(String value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(category: value);
      _retain();
    }
    state = state.copyWith(category: value);
  }

  void setRutTien(bool value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(rutTien: value);
      _retain();
    }
    state = state.copyWith(rutTien: value);
  }

  void setTrungBay(bool value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(trungBay: value);
      _retain();
    }
    state = state.copyWith(trungBay: value);
  }

  void setTangKem(bool value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(tangKem: value);
      _retain();
    }
    state = state.copyWith(tangKem: value);
  }

  void setPickedPhoto(XFile? file) {
    _newDraft = _newDraft.copyWith(pickedPhoto: file);
    _retain();
    state = state.copyWith(pickedPhoto: file);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Bump the rebuild counter so the widget re-reads the
  /// controller-backed price-chip / enum-section row state. Replaces
  /// the pre-migration empty `setState(() {})` calls that drove
  /// rebuilds after the rows mutated their own state.
  void rebuild() => state = state.copyWith(rebuildTick: state.rebuildTick + 1);

  void _retain() {
    if (context != null) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(context!, _newDraft);
    }
  }
}

/// Provider for the product-form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final productFormProvider =
    NotifierProvider<ProductFormNotifier, ProductFormState>(
      ProductFormNotifier.new,
    );

final contextualProductFormProvider =
    NotifierProvider.family<
      ProductFormNotifier,
      ProductFormState,
      FormDraftContext
    >(ProductFormNotifier.new);

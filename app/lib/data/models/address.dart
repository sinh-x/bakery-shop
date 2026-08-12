import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'address.freezed.dart';
part 'address.g.dart';

/// One entry returned by ``GET /api/addresses/autocomplete`` (DG-385 Phase 4).
///
/// Mirrors the backend ``AutocompleteSuggestion`` pydantic model from
/// `src/baker/models/address.py`. The backend ranks the caller customer's
/// own addresses first when ``customerId`` is supplied (FR5/AC5), and each
/// entry carries ``googleMapsUrl`` so the frontend can auto-bind the link
/// on selection (FR2/AC2). ``isCustomerAddress`` is true for entries that
/// belong to the selected customer so the UI can badge them.
///
/// DG-388 Phase 1: the autocomplete endpoint will be enhanced (Phase 2) to
/// return a grouped response ``{pastOrders: [...], library: [...]}`` (FR3).
/// [AddressAutocompleteResponse] models that grouped shape; the existing
/// `AddressSuggestion` entries remain the per-item shape so current
/// consumers of the flat list continue to work unchanged. The
/// [googleMapsUrl] field is nullable because library entries and past-order
/// addresses may exist without a known link (F3).
@freezed
sealed class AddressSuggestion with _$AddressSuggestion {
  const factory AddressSuggestion({
    // DG-388 CQ-1: `id` is nullable because `pastOrders` entries are derived
    // from the `orders` table (grouped by raw delivery_address) and have no
    // address-library id by construction. The `library` entries always carry
    // an id. Making `id` nullable lets the same model parse both sections.
    @JsonKey(name: 'id') int? id,
    @JsonKey(name: 'displayAddress') required String displayAddress,
    @JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,
    @JsonKey(name: 'isCustomerAddress') @Default(false) bool isCustomerAddress,
  }) = _AddressSuggestion;

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) =>
      _$AddressSuggestionFromJson(json);
}

/// Grouped autocomplete response returned by the enhanced
/// ``GET /api/addresses/autocomplete`` endpoint (DG-388 Phase 2 / FR3).
///
/// The backend always returns this grouped shape so the frontend renders
/// two labeled sections ("Địa chỉ đã giao" / "Thư viện địa chỉ") in the
/// autocomplete dropdown (FR4). [pastOrders] holds the customer's previously
/// used delivery addresses, and [library] holds the address library
/// matches. Either list may be empty when no matches are found in its
/// group; both default to empty lists so callers can iterate safely.
@freezed
sealed class AddressAutocompleteResponse with _$AddressAutocompleteResponse {
  const factory AddressAutocompleteResponse({
    @JsonKey(name: 'pastOrders') @Default(<AddressSuggestion>[])
    List<AddressSuggestion> pastOrders,
    @JsonKey(name: 'library') @Default(<AddressSuggestion>[])
    List<AddressSuggestion> library,
  }) = _AddressAutocompleteResponse;

  factory AddressAutocompleteResponse.fromJson(Map<String, dynamic> json) =>
      _$AddressAutocompleteResponseFromJson(json);
}

/// One row returned by ``GET /api/addresses/missing-links`` (DG-387 backend,
/// DG-388 Phase 1 client model).
///
/// Mirrors the backend ``list_missing_links`` dict shape from
/// `src/baker/services/address_library.py`: [deliveryAddress] is the raw
/// delivery address text exactly as typed on the order (grouping is on the
/// raw text, not normalized, so staff see the address as written), and
/// [orderCount] is the number of door-delivery orders that reference this
/// address without a Google Maps link. Results are ordered by
/// [orderCount] descending so the most-referenced gap surfaces first
/// (FR1). This model backs the missing-links screen (Phase 3).
@freezed
sealed class MissingLinkItem with _$MissingLinkItem {
  const factory MissingLinkItem({
    @JsonKey(name: 'deliveryAddress') required String deliveryAddress,
    @JsonKey(name: 'orderCount') required int orderCount,
  }) = _MissingLinkItem;

  factory MissingLinkItem.fromJson(Map<String, dynamic> json) =>
      _$MissingLinkItemFromJson(json);
}

/// One row of the address library returned by ``GET /api/addresses/library``
/// and managed via ``POST/PATCH/DELETE /api/addresses/library`` (DG-385
/// Phase 2 backend; consumed by the Phase 5 management screen).
///
/// Mirrors the ``Address.to_api_dict()`` shape from
/// `src/baker/models/address.py`: ``displayAddress`` is the original
/// user-facing text; ``googleMapsUrl`` is nullable because library entries
/// may exist without a known link (FR10).
@freezed
sealed class AddressLibraryEntry with _$AddressLibraryEntry {
  const factory AddressLibraryEntry({
    required int id,
    @JsonKey(name: 'displayAddress') required String displayAddress,
    @JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,
    @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? updatedAt,
  }) = _AddressLibraryEntry;

  factory AddressLibraryEntry.fromJson(Map<String, dynamic> json) =>
      _$AddressLibraryEntryFromJson(json);
}
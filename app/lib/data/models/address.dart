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
@freezed
sealed class AddressSuggestion with _$AddressSuggestion {
  const factory AddressSuggestion({
    required int id,
    @JsonKey(name: 'displayAddress') required String displayAddress,
    @JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,
    @JsonKey(name: 'isCustomerAddress') @Default(false) bool isCustomerAddress,
  }) = _AddressSuggestion;

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) =>
      _$AddressSuggestionFromJson(json);
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
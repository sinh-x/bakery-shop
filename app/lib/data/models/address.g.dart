// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AddressSuggestion _$AddressSuggestionFromJson(Map<String, dynamic> json) =>
    _AddressSuggestion(
      id: (json['id'] as num).toInt(),
      displayAddress: json['displayAddress'] as String,
      googleMapsUrl: json['googleMapsUrl'] as String?,
      isCustomerAddress: json['isCustomerAddress'] as bool? ?? false,
    );

Map<String, dynamic> _$AddressSuggestionToJson(_AddressSuggestion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayAddress': instance.displayAddress,
      'googleMapsUrl': instance.googleMapsUrl,
      'isCustomerAddress': instance.isCustomerAddress,
    };

_AddressAutocompleteResponse _$AddressAutocompleteResponseFromJson(
  Map<String, dynamic> json,
) => _AddressAutocompleteResponse(
  pastOrders:
      (json['pastOrders'] as List<dynamic>?)
          ?.map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <AddressSuggestion>[],
  library:
      (json['library'] as List<dynamic>?)
          ?.map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <AddressSuggestion>[],
);

Map<String, dynamic> _$AddressAutocompleteResponseToJson(
  _AddressAutocompleteResponse instance,
) => <String, dynamic>{
  'pastOrders': instance.pastOrders,
  'library': instance.library,
};

_MissingLinkItem _$MissingLinkItemFromJson(Map<String, dynamic> json) =>
    _MissingLinkItem(
      deliveryAddress: json['deliveryAddress'] as String,
      orderCount: (json['orderCount'] as num).toInt(),
    );

Map<String, dynamic> _$MissingLinkItemToJson(_MissingLinkItem instance) =>
    <String, dynamic>{
      'deliveryAddress': instance.deliveryAddress,
      'orderCount': instance.orderCount,
    };

_AddressLibraryEntry _$AddressLibraryEntryFromJson(Map<String, dynamic> json) =>
    _AddressLibraryEntry(
      id: (json['id'] as num).toInt(),
      displayAddress: json['displayAddress'] as String,
      googleMapsUrl: json['googleMapsUrl'] as String?,
      createdAt: parseApiDateTime(json['createdAt'] as String?),
      updatedAt: parseApiDateTime(json['updatedAt'] as String?),
    );

Map<String, dynamic> _$AddressLibraryEntryToJson(
  _AddressLibraryEntry instance,
) => <String, dynamic>{
  'id': instance.id,
  'displayAddress': instance.displayAddress,
  'googleMapsUrl': instance.googleMapsUrl,
  'createdAt': timestampToJson(instance.createdAt),
  'updatedAt': timestampToJson(instance.updatedAt),
};

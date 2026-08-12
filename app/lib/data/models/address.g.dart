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

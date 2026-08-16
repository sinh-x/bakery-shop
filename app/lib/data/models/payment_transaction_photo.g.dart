// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_transaction_photo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PaymentTransactionPhoto _$PaymentTransactionPhotoFromJson(
  Map<String, dynamic> json,
) => _PaymentTransactionPhoto(
  id: json['id'] as String,
  paymentTransactionId: json['paymentTransactionId'] as String,
  photoId: json['photoId'] as String,
  photoHash: json['photoHash'] as String?,
  createdAt: json['createdAt'] as String?,
);

Map<String, dynamic> _$PaymentTransactionPhotoToJson(
  _PaymentTransactionPhoto instance,
) => <String, dynamic>{
  'id': instance.id,
  'paymentTransactionId': instance.paymentTransactionId,
  'photoId': instance.photoId,
  'photoHash': instance.photoHash,
  'createdAt': instance.createdAt,
};

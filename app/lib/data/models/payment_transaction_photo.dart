import 'package:freezed_annotation/freezed_annotation.dart';

part 'payment_transaction_photo.freezed.dart';
part 'payment_transaction_photo.g.dart';

@freezed
sealed class PaymentTransactionPhoto with _$PaymentTransactionPhoto {
  const factory PaymentTransactionPhoto({
    required String id,
    @JsonKey(name: 'paymentTransactionId') required String paymentTransactionId,
    @JsonKey(name: 'photoId') required String photoId,
    @JsonKey(name: 'photoHash') String? photoHash,
    @JsonKey(name: 'createdAt') String? createdAt,
  }) = _PaymentTransactionPhoto;

  factory PaymentTransactionPhoto.fromJson(Map<String, dynamic> json) =>
      _$PaymentTransactionPhotoFromJson(json);
}
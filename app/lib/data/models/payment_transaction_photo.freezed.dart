// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'payment_transaction_photo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PaymentTransactionPhoto {

 String get id;@JsonKey(name: 'paymentTransactionId') String get paymentTransactionId;@JsonKey(name: 'photoId') String get photoId;@JsonKey(name: 'photoHash') String? get photoHash;@JsonKey(name: 'createdAt') String? get createdAt;
/// Create a copy of PaymentTransactionPhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaymentTransactionPhotoCopyWith<PaymentTransactionPhoto> get copyWith => _$PaymentTransactionPhotoCopyWithImpl<PaymentTransactionPhoto>(this as PaymentTransactionPhoto, _$identity);

  /// Serializes this PaymentTransactionPhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaymentTransactionPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.paymentTransactionId, paymentTransactionId) || other.paymentTransactionId == paymentTransactionId)&&(identical(other.photoId, photoId) || other.photoId == photoId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,paymentTransactionId,photoId,photoHash,createdAt);

@override
String toString() {
  return 'PaymentTransactionPhoto(id: $id, paymentTransactionId: $paymentTransactionId, photoId: $photoId, photoHash: $photoHash, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $PaymentTransactionPhotoCopyWith<$Res>  {
  factory $PaymentTransactionPhotoCopyWith(PaymentTransactionPhoto value, $Res Function(PaymentTransactionPhoto) _then) = _$PaymentTransactionPhotoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'paymentTransactionId') String paymentTransactionId,@JsonKey(name: 'photoId') String photoId,@JsonKey(name: 'photoHash') String? photoHash,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class _$PaymentTransactionPhotoCopyWithImpl<$Res>
    implements $PaymentTransactionPhotoCopyWith<$Res> {
  _$PaymentTransactionPhotoCopyWithImpl(this._self, this._then);

  final PaymentTransactionPhoto _self;
  final $Res Function(PaymentTransactionPhoto) _then;

/// Create a copy of PaymentTransactionPhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? paymentTransactionId = null,Object? photoId = null,Object? photoHash = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,paymentTransactionId: null == paymentTransactionId ? _self.paymentTransactionId : paymentTransactionId // ignore: cast_nullable_to_non_nullable
as String,photoId: null == photoId ? _self.photoId : photoId // ignore: cast_nullable_to_non_nullable
as String,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PaymentTransactionPhoto].
extension PaymentTransactionPhotoPatterns on PaymentTransactionPhoto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PaymentTransactionPhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PaymentTransactionPhoto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PaymentTransactionPhoto value)  $default,){
final _that = this;
switch (_that) {
case _PaymentTransactionPhoto():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PaymentTransactionPhoto value)?  $default,){
final _that = this;
switch (_that) {
case _PaymentTransactionPhoto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'paymentTransactionId')  String paymentTransactionId, @JsonKey(name: 'photoId')  String photoId, @JsonKey(name: 'photoHash')  String? photoHash, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PaymentTransactionPhoto() when $default != null:
return $default(_that.id,_that.paymentTransactionId,_that.photoId,_that.photoHash,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'paymentTransactionId')  String paymentTransactionId, @JsonKey(name: 'photoId')  String photoId, @JsonKey(name: 'photoHash')  String? photoHash, @JsonKey(name: 'createdAt')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _PaymentTransactionPhoto():
return $default(_that.id,_that.paymentTransactionId,_that.photoId,_that.photoHash,_that.createdAt);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'paymentTransactionId')  String paymentTransactionId, @JsonKey(name: 'photoId')  String photoId, @JsonKey(name: 'photoHash')  String? photoHash, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _PaymentTransactionPhoto() when $default != null:
return $default(_that.id,_that.paymentTransactionId,_that.photoId,_that.photoHash,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PaymentTransactionPhoto implements PaymentTransactionPhoto {
  const _PaymentTransactionPhoto({required this.id, @JsonKey(name: 'paymentTransactionId') required this.paymentTransactionId, @JsonKey(name: 'photoId') required this.photoId, @JsonKey(name: 'photoHash') this.photoHash, @JsonKey(name: 'createdAt') this.createdAt});
  factory _PaymentTransactionPhoto.fromJson(Map<String, dynamic> json) => _$PaymentTransactionPhotoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'paymentTransactionId') final  String paymentTransactionId;
@override@JsonKey(name: 'photoId') final  String photoId;
@override@JsonKey(name: 'photoHash') final  String? photoHash;
@override@JsonKey(name: 'createdAt') final  String? createdAt;

/// Create a copy of PaymentTransactionPhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PaymentTransactionPhotoCopyWith<_PaymentTransactionPhoto> get copyWith => __$PaymentTransactionPhotoCopyWithImpl<_PaymentTransactionPhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PaymentTransactionPhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PaymentTransactionPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.paymentTransactionId, paymentTransactionId) || other.paymentTransactionId == paymentTransactionId)&&(identical(other.photoId, photoId) || other.photoId == photoId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,paymentTransactionId,photoId,photoHash,createdAt);

@override
String toString() {
  return 'PaymentTransactionPhoto(id: $id, paymentTransactionId: $paymentTransactionId, photoId: $photoId, photoHash: $photoHash, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$PaymentTransactionPhotoCopyWith<$Res> implements $PaymentTransactionPhotoCopyWith<$Res> {
  factory _$PaymentTransactionPhotoCopyWith(_PaymentTransactionPhoto value, $Res Function(_PaymentTransactionPhoto) _then) = __$PaymentTransactionPhotoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'paymentTransactionId') String paymentTransactionId,@JsonKey(name: 'photoId') String photoId,@JsonKey(name: 'photoHash') String? photoHash,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class __$PaymentTransactionPhotoCopyWithImpl<$Res>
    implements _$PaymentTransactionPhotoCopyWith<$Res> {
  __$PaymentTransactionPhotoCopyWithImpl(this._self, this._then);

  final _PaymentTransactionPhoto _self;
  final $Res Function(_PaymentTransactionPhoto) _then;

/// Create a copy of PaymentTransactionPhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? paymentTransactionId = null,Object? photoId = null,Object? photoHash = freezed,Object? createdAt = freezed,}) {
  return _then(_PaymentTransactionPhoto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,paymentTransactionId: null == paymentTransactionId ? _self.paymentTransactionId : paymentTransactionId // ignore: cast_nullable_to_non_nullable
as String,photoId: null == photoId ? _self.photoId : photoId // ignore: cast_nullable_to_non_nullable
as String,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

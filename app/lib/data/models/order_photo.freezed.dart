// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order_photo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$OrderPhoto {

 int get id;@JsonKey(name: 'order_id') int get orderId;@JsonKey(name: 'photo_hash') String get photoHash; String get tags; int get position;@JsonKey(name: 'work_item_id') int? get workItemId;@JsonKey(name: 'created_at') String? get createdAt;
/// Create a copy of OrderPhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OrderPhotoCopyWith<OrderPhoto> get copyWith => _$OrderPhotoCopyWithImpl<OrderPhoto>(this as OrderPhoto, _$identity);

  /// Serializes this OrderPhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OrderPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.workItemId, workItemId) || other.workItemId == workItemId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,orderId,photoHash,tags,position,workItemId,createdAt);

@override
String toString() {
  return 'OrderPhoto(id: $id, orderId: $orderId, photoHash: $photoHash, tags: $tags, position: $position, workItemId: $workItemId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $OrderPhotoCopyWith<$Res>  {
  factory $OrderPhotoCopyWith(OrderPhoto value, $Res Function(OrderPhoto) _then) = _$OrderPhotoCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'order_id') int orderId,@JsonKey(name: 'photo_hash') String photoHash, String tags, int position,@JsonKey(name: 'work_item_id') int? workItemId,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class _$OrderPhotoCopyWithImpl<$Res>
    implements $OrderPhotoCopyWith<$Res> {
  _$OrderPhotoCopyWithImpl(this._self, this._then);

  final OrderPhoto _self;
  final $Res Function(OrderPhoto) _then;

/// Create a copy of OrderPhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? orderId = null,Object? photoHash = null,Object? tags = null,Object? position = null,Object? workItemId = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as int,photoHash: null == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,workItemId: freezed == workItemId ? _self.workItemId : workItemId // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [OrderPhoto].
extension OrderPhotoPatterns on OrderPhoto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OrderPhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OrderPhoto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OrderPhoto value)  $default,){
final _that = this;
switch (_that) {
case _OrderPhoto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OrderPhoto value)?  $default,){
final _that = this;
switch (_that) {
case _OrderPhoto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'order_id')  int orderId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'work_item_id')  int? workItemId, @JsonKey(name: 'created_at')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OrderPhoto() when $default != null:
return $default(_that.id,_that.orderId,_that.photoHash,_that.tags,_that.position,_that.workItemId,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'order_id')  int orderId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'work_item_id')  int? workItemId, @JsonKey(name: 'created_at')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _OrderPhoto():
return $default(_that.id,_that.orderId,_that.photoHash,_that.tags,_that.position,_that.workItemId,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'order_id')  int orderId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'work_item_id')  int? workItemId, @JsonKey(name: 'created_at')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _OrderPhoto() when $default != null:
return $default(_that.id,_that.orderId,_that.photoHash,_that.tags,_that.position,_that.workItemId,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OrderPhoto implements OrderPhoto {
  const _OrderPhoto({required this.id, @JsonKey(name: 'order_id') required this.orderId, @JsonKey(name: 'photo_hash') required this.photoHash, this.tags = '', this.position = 0, @JsonKey(name: 'work_item_id') this.workItemId, @JsonKey(name: 'created_at') this.createdAt});
  factory _OrderPhoto.fromJson(Map<String, dynamic> json) => _$OrderPhotoFromJson(json);

@override final  int id;
@override@JsonKey(name: 'order_id') final  int orderId;
@override@JsonKey(name: 'photo_hash') final  String photoHash;
@override@JsonKey() final  String tags;
@override@JsonKey() final  int position;
@override@JsonKey(name: 'work_item_id') final  int? workItemId;
@override@JsonKey(name: 'created_at') final  String? createdAt;

/// Create a copy of OrderPhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OrderPhotoCopyWith<_OrderPhoto> get copyWith => __$OrderPhotoCopyWithImpl<_OrderPhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OrderPhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OrderPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.workItemId, workItemId) || other.workItemId == workItemId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,orderId,photoHash,tags,position,workItemId,createdAt);

@override
String toString() {
  return 'OrderPhoto(id: $id, orderId: $orderId, photoHash: $photoHash, tags: $tags, position: $position, workItemId: $workItemId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$OrderPhotoCopyWith<$Res> implements $OrderPhotoCopyWith<$Res> {
  factory _$OrderPhotoCopyWith(_OrderPhoto value, $Res Function(_OrderPhoto) _then) = __$OrderPhotoCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'order_id') int orderId,@JsonKey(name: 'photo_hash') String photoHash, String tags, int position,@JsonKey(name: 'work_item_id') int? workItemId,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class __$OrderPhotoCopyWithImpl<$Res>
    implements _$OrderPhotoCopyWith<$Res> {
  __$OrderPhotoCopyWithImpl(this._self, this._then);

  final _OrderPhoto _self;
  final $Res Function(_OrderPhoto) _then;

/// Create a copy of OrderPhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? orderId = null,Object? photoHash = null,Object? tags = null,Object? position = null,Object? workItemId = freezed,Object? createdAt = freezed,}) {
  return _then(_OrderPhoto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as int,photoHash: null == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,workItemId: freezed == workItemId ? _self.workItemId : workItemId // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

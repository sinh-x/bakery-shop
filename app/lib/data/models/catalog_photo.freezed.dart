// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_photo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CatalogPhoto {

 int get id;@JsonKey(name: 'product_id') int get productId;@JsonKey(name: 'file_path') String get filePath; String get caption; String get tags; int get position;@JsonKey(name: 'created_at') String? get createdAt;@JsonKey(name: 'photo_hash') String? get photoHash;
/// Create a copy of CatalogPhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogPhotoCopyWith<CatalogPhoto> get copyWith => _$CatalogPhotoCopyWithImpl<CatalogPhoto>(this as CatalogPhoto, _$identity);

  /// Serializes this CatalogPhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,filePath,caption,tags,position,createdAt,photoHash);

@override
String toString() {
  return 'CatalogPhoto(id: $id, productId: $productId, filePath: $filePath, caption: $caption, tags: $tags, position: $position, createdAt: $createdAt, photoHash: $photoHash)';
}


}

/// @nodoc
abstract mixin class $CatalogPhotoCopyWith<$Res>  {
  factory $CatalogPhotoCopyWith(CatalogPhoto value, $Res Function(CatalogPhoto) _then) = _$CatalogPhotoCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'product_id') int productId,@JsonKey(name: 'file_path') String filePath, String caption, String tags, int position,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'photo_hash') String? photoHash
});




}
/// @nodoc
class _$CatalogPhotoCopyWithImpl<$Res>
    implements $CatalogPhotoCopyWith<$Res> {
  _$CatalogPhotoCopyWithImpl(this._self, this._then);

  final CatalogPhoto _self;
  final $Res Function(CatalogPhoto) _then;

/// Create a copy of CatalogPhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = null,Object? filePath = null,Object? caption = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,Object? photoHash = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogPhoto].
extension CatalogPhotoPatterns on CatalogPhoto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogPhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogPhoto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogPhoto value)  $default,){
final _that = this;
switch (_that) {
case _CatalogPhoto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogPhoto value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogPhoto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogPhoto() when $default != null:
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash)  $default,) {final _that = this;
switch (_that) {
case _CatalogPhoto():
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash)?  $default,) {final _that = this;
switch (_that) {
case _CatalogPhoto() when $default != null:
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CatalogPhoto implements CatalogPhoto {
  const _CatalogPhoto({required this.id, @JsonKey(name: 'product_id') required this.productId, @JsonKey(name: 'file_path') required this.filePath, this.caption = '', this.tags = '', this.position = 0, @JsonKey(name: 'created_at') this.createdAt, @JsonKey(name: 'photo_hash') this.photoHash});
  factory _CatalogPhoto.fromJson(Map<String, dynamic> json) => _$CatalogPhotoFromJson(json);

@override final  int id;
@override@JsonKey(name: 'product_id') final  int productId;
@override@JsonKey(name: 'file_path') final  String filePath;
@override@JsonKey() final  String caption;
@override@JsonKey() final  String tags;
@override@JsonKey() final  int position;
@override@JsonKey(name: 'created_at') final  String? createdAt;
@override@JsonKey(name: 'photo_hash') final  String? photoHash;

/// Create a copy of CatalogPhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogPhotoCopyWith<_CatalogPhoto> get copyWith => __$CatalogPhotoCopyWithImpl<_CatalogPhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CatalogPhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,filePath,caption,tags,position,createdAt,photoHash);

@override
String toString() {
  return 'CatalogPhoto(id: $id, productId: $productId, filePath: $filePath, caption: $caption, tags: $tags, position: $position, createdAt: $createdAt, photoHash: $photoHash)';
}


}

/// @nodoc
abstract mixin class _$CatalogPhotoCopyWith<$Res> implements $CatalogPhotoCopyWith<$Res> {
  factory _$CatalogPhotoCopyWith(_CatalogPhoto value, $Res Function(_CatalogPhoto) _then) = __$CatalogPhotoCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'product_id') int productId,@JsonKey(name: 'file_path') String filePath, String caption, String tags, int position,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'photo_hash') String? photoHash
});




}
/// @nodoc
class __$CatalogPhotoCopyWithImpl<$Res>
    implements _$CatalogPhotoCopyWith<$Res> {
  __$CatalogPhotoCopyWithImpl(this._self, this._then);

  final _CatalogPhoto _self;
  final $Res Function(_CatalogPhoto) _then;

/// Create a copy of CatalogPhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = null,Object? filePath = null,Object? caption = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,Object? photoHash = freezed,}) {
  return _then(_CatalogPhoto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

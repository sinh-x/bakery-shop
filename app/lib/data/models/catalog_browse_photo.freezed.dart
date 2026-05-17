// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_browse_photo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CatalogBrowsePhoto {

 int get id;@JsonKey(name: 'product_id') int get productId;@JsonKey(name: 'file_path') String get filePath; String get caption; String get tags; int get position;@JsonKey(name: 'created_at') String? get createdAt;@JsonKey(name: 'photo_hash') String? get photoHash;@JsonKey(name: 'product_name') String get productName;
/// Create a copy of CatalogBrowsePhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogBrowsePhotoCopyWith<CatalogBrowsePhoto> get copyWith => _$CatalogBrowsePhotoCopyWithImpl<CatalogBrowsePhoto>(this as CatalogBrowsePhoto, _$identity);

  /// Serializes this CatalogBrowsePhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogBrowsePhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.productName, productName) || other.productName == productName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,filePath,caption,tags,position,createdAt,photoHash,productName);

@override
String toString() {
  return 'CatalogBrowsePhoto(id: $id, productId: $productId, filePath: $filePath, caption: $caption, tags: $tags, position: $position, createdAt: $createdAt, photoHash: $photoHash, productName: $productName)';
}


}

/// @nodoc
abstract mixin class $CatalogBrowsePhotoCopyWith<$Res>  {
  factory $CatalogBrowsePhotoCopyWith(CatalogBrowsePhoto value, $Res Function(CatalogBrowsePhoto) _then) = _$CatalogBrowsePhotoCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'product_id') int productId,@JsonKey(name: 'file_path') String filePath, String caption, String tags, int position,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'photo_hash') String? photoHash,@JsonKey(name: 'product_name') String productName
});




}
/// @nodoc
class _$CatalogBrowsePhotoCopyWithImpl<$Res>
    implements $CatalogBrowsePhotoCopyWith<$Res> {
  _$CatalogBrowsePhotoCopyWithImpl(this._self, this._then);

  final CatalogBrowsePhoto _self;
  final $Res Function(CatalogBrowsePhoto) _then;

/// Create a copy of CatalogBrowsePhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = null,Object? filePath = null,Object? caption = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,Object? photoHash = freezed,Object? productName = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogBrowsePhoto].
extension CatalogBrowsePhotoPatterns on CatalogBrowsePhoto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogBrowsePhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogBrowsePhoto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogBrowsePhoto value)  $default,){
final _that = this;
switch (_that) {
case _CatalogBrowsePhoto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogBrowsePhoto value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogBrowsePhoto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash, @JsonKey(name: 'product_name')  String productName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogBrowsePhoto() when $default != null:
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash,_that.productName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash, @JsonKey(name: 'product_name')  String productName)  $default,) {final _that = this;
switch (_that) {
case _CatalogBrowsePhoto():
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash,_that.productName);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'product_id')  int productId, @JsonKey(name: 'file_path')  String filePath,  String caption,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'photo_hash')  String? photoHash, @JsonKey(name: 'product_name')  String productName)?  $default,) {final _that = this;
switch (_that) {
case _CatalogBrowsePhoto() when $default != null:
return $default(_that.id,_that.productId,_that.filePath,_that.caption,_that.tags,_that.position,_that.createdAt,_that.photoHash,_that.productName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CatalogBrowsePhoto implements CatalogBrowsePhoto {
  const _CatalogBrowsePhoto({required this.id, @JsonKey(name: 'product_id') required this.productId, @JsonKey(name: 'file_path') required this.filePath, this.caption = '', this.tags = '', this.position = 0, @JsonKey(name: 'created_at') this.createdAt, @JsonKey(name: 'photo_hash') this.photoHash, @JsonKey(name: 'product_name') required this.productName});
  factory _CatalogBrowsePhoto.fromJson(Map<String, dynamic> json) => _$CatalogBrowsePhotoFromJson(json);

@override final  int id;
@override@JsonKey(name: 'product_id') final  int productId;
@override@JsonKey(name: 'file_path') final  String filePath;
@override@JsonKey() final  String caption;
@override@JsonKey() final  String tags;
@override@JsonKey() final  int position;
@override@JsonKey(name: 'created_at') final  String? createdAt;
@override@JsonKey(name: 'photo_hash') final  String? photoHash;
@override@JsonKey(name: 'product_name') final  String productName;

/// Create a copy of CatalogBrowsePhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogBrowsePhotoCopyWith<_CatalogBrowsePhoto> get copyWith => __$CatalogBrowsePhotoCopyWithImpl<_CatalogBrowsePhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CatalogBrowsePhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogBrowsePhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.productName, productName) || other.productName == productName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,filePath,caption,tags,position,createdAt,photoHash,productName);

@override
String toString() {
  return 'CatalogBrowsePhoto(id: $id, productId: $productId, filePath: $filePath, caption: $caption, tags: $tags, position: $position, createdAt: $createdAt, photoHash: $photoHash, productName: $productName)';
}


}

/// @nodoc
abstract mixin class _$CatalogBrowsePhotoCopyWith<$Res> implements $CatalogBrowsePhotoCopyWith<$Res> {
  factory _$CatalogBrowsePhotoCopyWith(_CatalogBrowsePhoto value, $Res Function(_CatalogBrowsePhoto) _then) = __$CatalogBrowsePhotoCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'product_id') int productId,@JsonKey(name: 'file_path') String filePath, String caption, String tags, int position,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'photo_hash') String? photoHash,@JsonKey(name: 'product_name') String productName
});




}
/// @nodoc
class __$CatalogBrowsePhotoCopyWithImpl<$Res>
    implements _$CatalogBrowsePhotoCopyWith<$Res> {
  __$CatalogBrowsePhotoCopyWithImpl(this._self, this._then);

  final _CatalogBrowsePhoto _self;
  final $Res Function(_CatalogBrowsePhoto) _then;

/// Create a copy of CatalogBrowsePhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = null,Object? filePath = null,Object? caption = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,Object? photoHash = freezed,Object? productName = null,}) {
  return _then(_CatalogBrowsePhoto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,photoHash: freezed == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String?,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

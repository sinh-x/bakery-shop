// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CatalogTagDef {

 String get category; String get key; String get label; int? get color;
/// Create a copy of CatalogTagDef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogTagDefCopyWith<CatalogTagDef> get copyWith => _$CatalogTagDefCopyWithImpl<CatalogTagDef>(this as CatalogTagDef, _$identity);

  /// Serializes this CatalogTagDef to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogTagDef&&(identical(other.category, category) || other.category == category)&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.color, color) || other.color == color));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,category,key,label,color);

@override
String toString() {
  return 'CatalogTagDef(category: $category, key: $key, label: $label, color: $color)';
}


}

/// @nodoc
abstract mixin class $CatalogTagDefCopyWith<$Res>  {
  factory $CatalogTagDefCopyWith(CatalogTagDef value, $Res Function(CatalogTagDef) _then) = _$CatalogTagDefCopyWithImpl;
@useResult
$Res call({
 String category, String key, String label, int? color
});




}
/// @nodoc
class _$CatalogTagDefCopyWithImpl<$Res>
    implements $CatalogTagDefCopyWith<$Res> {
  _$CatalogTagDefCopyWithImpl(this._self, this._then);

  final CatalogTagDef _self;
  final $Res Function(CatalogTagDef) _then;

/// Create a copy of CatalogTagDef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? category = null,Object? key = null,Object? label = null,Object? color = freezed,}) {
  return _then(_self.copyWith(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogTagDef].
extension CatalogTagDefPatterns on CatalogTagDef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogTagDef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogTagDef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogTagDef value)  $default,){
final _that = this;
switch (_that) {
case _CatalogTagDef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogTagDef value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogTagDef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String category,  String key,  String label,  int? color)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogTagDef() when $default != null:
return $default(_that.category,_that.key,_that.label,_that.color);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String category,  String key,  String label,  int? color)  $default,) {final _that = this;
switch (_that) {
case _CatalogTagDef():
return $default(_that.category,_that.key,_that.label,_that.color);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String category,  String key,  String label,  int? color)?  $default,) {final _that = this;
switch (_that) {
case _CatalogTagDef() when $default != null:
return $default(_that.category,_that.key,_that.label,_that.color);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CatalogTagDef implements CatalogTagDef {
  const _CatalogTagDef({required this.category, required this.key, required this.label, this.color});
  factory _CatalogTagDef.fromJson(Map<String, dynamic> json) => _$CatalogTagDefFromJson(json);

@override final  String category;
@override final  String key;
@override final  String label;
@override final  int? color;

/// Create a copy of CatalogTagDef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogTagDefCopyWith<_CatalogTagDef> get copyWith => __$CatalogTagDefCopyWithImpl<_CatalogTagDef>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CatalogTagDefToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogTagDef&&(identical(other.category, category) || other.category == category)&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.color, color) || other.color == color));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,category,key,label,color);

@override
String toString() {
  return 'CatalogTagDef(category: $category, key: $key, label: $label, color: $color)';
}


}

/// @nodoc
abstract mixin class _$CatalogTagDefCopyWith<$Res> implements $CatalogTagDefCopyWith<$Res> {
  factory _$CatalogTagDefCopyWith(_CatalogTagDef value, $Res Function(_CatalogTagDef) _then) = __$CatalogTagDefCopyWithImpl;
@override @useResult
$Res call({
 String category, String key, String label, int? color
});




}
/// @nodoc
class __$CatalogTagDefCopyWithImpl<$Res>
    implements _$CatalogTagDefCopyWith<$Res> {
  __$CatalogTagDefCopyWithImpl(this._self, this._then);

  final _CatalogTagDef _self;
  final $Res Function(_CatalogTagDef) _then;

/// Create a copy of CatalogTagDef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? category = null,Object? key = null,Object? label = null,Object? color = freezed,}) {
  return _then(_CatalogTagDef(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on

// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'packing_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PackingItem {

 String get name; bool get isChecked;
/// Create a copy of PackingItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackingItemCopyWith<PackingItem> get copyWith => _$PackingItemCopyWithImpl<PackingItem>(this as PackingItem, _$identity);

  /// Serializes this PackingItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackingItem&&(identical(other.name, name) || other.name == name)&&(identical(other.isChecked, isChecked) || other.isChecked == isChecked));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,isChecked);

@override
String toString() {
  return 'PackingItem(name: $name, isChecked: $isChecked)';
}


}

/// @nodoc
abstract mixin class $PackingItemCopyWith<$Res>  {
  factory $PackingItemCopyWith(PackingItem value, $Res Function(PackingItem) _then) = _$PackingItemCopyWithImpl;
@useResult
$Res call({
 String name, bool isChecked
});




}
/// @nodoc
class _$PackingItemCopyWithImpl<$Res>
    implements $PackingItemCopyWith<$Res> {
  _$PackingItemCopyWithImpl(this._self, this._then);

  final PackingItem _self;
  final $Res Function(PackingItem) _then;

/// Create a copy of PackingItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? isChecked = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,isChecked: null == isChecked ? _self.isChecked : isChecked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [PackingItem].
extension PackingItemPatterns on PackingItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PackingItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PackingItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PackingItem value)  $default,){
final _that = this;
switch (_that) {
case _PackingItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PackingItem value)?  $default,){
final _that = this;
switch (_that) {
case _PackingItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  bool isChecked)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PackingItem() when $default != null:
return $default(_that.name,_that.isChecked);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  bool isChecked)  $default,) {final _that = this;
switch (_that) {
case _PackingItem():
return $default(_that.name,_that.isChecked);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  bool isChecked)?  $default,) {final _that = this;
switch (_that) {
case _PackingItem() when $default != null:
return $default(_that.name,_that.isChecked);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PackingItem implements PackingItem {
  const _PackingItem({required this.name, this.isChecked = false});
  factory _PackingItem.fromJson(Map<String, dynamic> json) => _$PackingItemFromJson(json);

@override final  String name;
@override@JsonKey() final  bool isChecked;

/// Create a copy of PackingItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackingItemCopyWith<_PackingItem> get copyWith => __$PackingItemCopyWithImpl<_PackingItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PackingItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackingItem&&(identical(other.name, name) || other.name == name)&&(identical(other.isChecked, isChecked) || other.isChecked == isChecked));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,isChecked);

@override
String toString() {
  return 'PackingItem(name: $name, isChecked: $isChecked)';
}


}

/// @nodoc
abstract mixin class _$PackingItemCopyWith<$Res> implements $PackingItemCopyWith<$Res> {
  factory _$PackingItemCopyWith(_PackingItem value, $Res Function(_PackingItem) _then) = __$PackingItemCopyWithImpl;
@override @useResult
$Res call({
 String name, bool isChecked
});




}
/// @nodoc
class __$PackingItemCopyWithImpl<$Res>
    implements _$PackingItemCopyWith<$Res> {
  __$PackingItemCopyWithImpl(this._self, this._then);

  final _PackingItem _self;
  final $Res Function(_PackingItem) _then;

/// Create a copy of PackingItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? isChecked = null,}) {
  return _then(_PackingItem(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,isChecked: null == isChecked ? _self.isChecked : isChecked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on

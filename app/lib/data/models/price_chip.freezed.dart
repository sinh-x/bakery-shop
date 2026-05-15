// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'price_chip.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PriceChip {

 int get id; String get label; double get price; int get position;@JsonKey(name: 'stock_qty') int? get stockQty;
/// Create a copy of PriceChip
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PriceChipCopyWith<PriceChip> get copyWith => _$PriceChipCopyWithImpl<PriceChip>(this as PriceChip, _$identity);

  /// Serializes this PriceChip to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PriceChip&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.price, price) || other.price == price)&&(identical(other.position, position) || other.position == position)&&(identical(other.stockQty, stockQty) || other.stockQty == stockQty));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,price,position,stockQty);

@override
String toString() {
  return 'PriceChip(id: $id, label: $label, price: $price, position: $position, stockQty: $stockQty)';
}


}

/// @nodoc
abstract mixin class $PriceChipCopyWith<$Res>  {
  factory $PriceChipCopyWith(PriceChip value, $Res Function(PriceChip) _then) = _$PriceChipCopyWithImpl;
@useResult
$Res call({
 int id, String label, double price, int position,@JsonKey(name: 'stock_qty') int? stockQty
});




}
/// @nodoc
class _$PriceChipCopyWithImpl<$Res>
    implements $PriceChipCopyWith<$Res> {
  _$PriceChipCopyWithImpl(this._self, this._then);

  final PriceChip _self;
  final $Res Function(PriceChip) _then;

/// Create a copy of PriceChip
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? price = null,Object? position = null,Object? stockQty = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,stockQty: freezed == stockQty ? _self.stockQty : stockQty // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PriceChip].
extension PriceChipPatterns on PriceChip {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PriceChip value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PriceChip() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PriceChip value)  $default,){
final _that = this;
switch (_that) {
case _PriceChip():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PriceChip value)?  $default,){
final _that = this;
switch (_that) {
case _PriceChip() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String label,  double price,  int position, @JsonKey(name: 'stock_qty') int? stockQty)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PriceChip() when $default != null:
return $default(_that.id,_that.label,_that.price,_that.position,_that.stockQty);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String label,  double price,  int position, @JsonKey(name: 'stock_qty') int? stockQty)  $default,) {final _that = this;
switch (_that) {
case _PriceChip():
return $default(_that.id,_that.label,_that.price,_that.position,_that.stockQty);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String label,  double price,  int position, @JsonKey(name: 'stock_qty')  int? stockQty)?  $default,) {final _that = this;
switch (_that) {
case _PriceChip() when $default != null:
return $default(_that.id,_that.label,_that.price,_that.position,_that.stockQty);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PriceChip implements PriceChip {
  const _PriceChip({required this.id, required this.label, required this.price, this.position = 0, @JsonKey(name: 'stock_qty') this.stockQty});
  factory _PriceChip.fromJson(Map<String, dynamic> json) => _$PriceChipFromJson(json);

@override final  int id;
@override final  String label;
@override final  double price;
@override@JsonKey() final  int position;
@override@JsonKey(name: 'stock_qty') final  int? stockQty;

/// Create a copy of PriceChip
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PriceChipCopyWith<_PriceChip> get copyWith => __$PriceChipCopyWithImpl<_PriceChip>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PriceChipToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PriceChip&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.price, price) || other.price == price)&&(identical(other.position, position) || other.position == position)&&(identical(other.stockQty, stockQty) || other.stockQty == stockQty));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,price,position,stockQty);

@override
String toString() {
  return 'PriceChip(id: $id, label: $label, price: $price, position: $position, stockQty: $stockQty)';
}


}

/// @nodoc
abstract mixin class _$PriceChipCopyWith<$Res> implements $PriceChipCopyWith<$Res> {
  factory _$PriceChipCopyWith(_PriceChip value, $Res Function(_PriceChip) _then) = __$PriceChipCopyWithImpl;
@override @useResult
$Res call({
 int id, String label, double price, int position,@JsonKey(name: 'stock_qty') int? stockQty
});




}
/// @nodoc
class __$PriceChipCopyWithImpl<$Res>
    implements _$PriceChipCopyWith<$Res> {
  __$PriceChipCopyWithImpl(this._self, this._then);

  final _PriceChip _self;
  final $Res Function(_PriceChip) _then;

/// Create a copy of PriceChip
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? price = null,Object? position = null,Object? stockQty = freezed,}) {
  return _then(_PriceChip(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,stockQty: freezed == stockQty ? _self.stockQty : stockQty // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on

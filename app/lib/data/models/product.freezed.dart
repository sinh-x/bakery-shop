// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Product {

 int get id; String get name; String get category;@JsonKey(name: 'base_price') double get basePrice; double get cost;@JsonKey(name: 'recipe_notes') String get recipeNotes; int get active;@JsonKey(name: 'photo_path') String get photoPath;@JsonKey(name: 'product_code') String get productCode; Map<String, String> get attributes;
/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCopyWith<Product> get copyWith => _$ProductCopyWithImpl<Product>(this as Product, _$identity);

  /// Serializes this Product to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Product&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.basePrice, basePrice) || other.basePrice == basePrice)&&(identical(other.cost, cost) || other.cost == cost)&&(identical(other.recipeNotes, recipeNotes) || other.recipeNotes == recipeNotes)&&(identical(other.active, active) || other.active == active)&&(identical(other.photoPath, photoPath) || other.photoPath == photoPath)&&(identical(other.productCode, productCode) || other.productCode == productCode)&&const DeepCollectionEquality().equals(other.attributes, attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,category,basePrice,cost,recipeNotes,active,photoPath,productCode,const DeepCollectionEquality().hash(attributes));

@override
String toString() {
  return 'Product(id: $id, name: $name, category: $category, basePrice: $basePrice, cost: $cost, recipeNotes: $recipeNotes, active: $active, photoPath: $photoPath, productCode: $productCode, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class $ProductCopyWith<$Res>  {
  factory $ProductCopyWith(Product value, $Res Function(Product) _then) = _$ProductCopyWithImpl;
@useResult
$Res call({
 int id, String name, String category,@JsonKey(name: 'base_price') double basePrice, double cost,@JsonKey(name: 'recipe_notes') String recipeNotes, int active,@JsonKey(name: 'photo_path') String photoPath,@JsonKey(name: 'product_code') String productCode, Map<String, String> attributes
});




}
/// @nodoc
class _$ProductCopyWithImpl<$Res>
    implements $ProductCopyWith<$Res> {
  _$ProductCopyWithImpl(this._self, this._then);

  final Product _self;
  final $Res Function(Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? category = null,Object? basePrice = null,Object? cost = null,Object? recipeNotes = null,Object? active = null,Object? photoPath = null,Object? productCode = null,Object? attributes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,basePrice: null == basePrice ? _self.basePrice : basePrice // ignore: cast_nullable_to_non_nullable
as double,cost: null == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as double,recipeNotes: null == recipeNotes ? _self.recipeNotes : recipeNotes // ignore: cast_nullable_to_non_nullable
as String,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as int,photoPath: null == photoPath ? _self.photoPath : photoPath // ignore: cast_nullable_to_non_nullable
as String,productCode: null == productCode ? _self.productCode : productCode // ignore: cast_nullable_to_non_nullable
as String,attributes: null == attributes ? _self.attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [Product].
extension ProductPatterns on Product {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Product value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Product value)  $default,){
final _that = this;
switch (_that) {
case _Product():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Product value)?  $default,){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  String category, @JsonKey(name: 'base_price')  double basePrice,  double cost, @JsonKey(name: 'recipe_notes')  String recipeNotes,  int active, @JsonKey(name: 'photo_path')  String photoPath, @JsonKey(name: 'product_code')  String productCode,  Map<String, String> attributes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.name,_that.category,_that.basePrice,_that.cost,_that.recipeNotes,_that.active,_that.photoPath,_that.productCode,_that.attributes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  String category, @JsonKey(name: 'base_price')  double basePrice,  double cost, @JsonKey(name: 'recipe_notes')  String recipeNotes,  int active, @JsonKey(name: 'photo_path')  String photoPath, @JsonKey(name: 'product_code')  String productCode,  Map<String, String> attributes)  $default,) {final _that = this;
switch (_that) {
case _Product():
return $default(_that.id,_that.name,_that.category,_that.basePrice,_that.cost,_that.recipeNotes,_that.active,_that.photoPath,_that.productCode,_that.attributes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  String category, @JsonKey(name: 'base_price')  double basePrice,  double cost, @JsonKey(name: 'recipe_notes')  String recipeNotes,  int active, @JsonKey(name: 'photo_path')  String photoPath, @JsonKey(name: 'product_code')  String productCode,  Map<String, String> attributes)?  $default,) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.name,_that.category,_that.basePrice,_that.cost,_that.recipeNotes,_that.active,_that.photoPath,_that.productCode,_that.attributes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Product implements Product {
  const _Product({required this.id, required this.name, this.category = 'bread', @JsonKey(name: 'base_price') this.basePrice = 0, this.cost = 0, @JsonKey(name: 'recipe_notes') this.recipeNotes = '', this.active = 1, @JsonKey(name: 'photo_path') this.photoPath = '', @JsonKey(name: 'product_code') this.productCode = '', final  Map<String, String> attributes = const {}}): _attributes = attributes;
  factory _Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);

@override final  int id;
@override final  String name;
@override@JsonKey() final  String category;
@override@JsonKey(name: 'base_price') final  double basePrice;
@override@JsonKey() final  double cost;
@override@JsonKey(name: 'recipe_notes') final  String recipeNotes;
@override@JsonKey() final  int active;
@override@JsonKey(name: 'photo_path') final  String photoPath;
@override@JsonKey(name: 'product_code') final  String productCode;
 final  Map<String, String> _attributes;
@override@JsonKey() Map<String, String> get attributes {
  if (_attributes is EqualUnmodifiableMapView) return _attributes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_attributes);
}


/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCopyWith<_Product> get copyWith => __$ProductCopyWithImpl<_Product>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Product&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.basePrice, basePrice) || other.basePrice == basePrice)&&(identical(other.cost, cost) || other.cost == cost)&&(identical(other.recipeNotes, recipeNotes) || other.recipeNotes == recipeNotes)&&(identical(other.active, active) || other.active == active)&&(identical(other.photoPath, photoPath) || other.photoPath == photoPath)&&(identical(other.productCode, productCode) || other.productCode == productCode)&&const DeepCollectionEquality().equals(other._attributes, _attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,category,basePrice,cost,recipeNotes,active,photoPath,productCode,const DeepCollectionEquality().hash(_attributes));

@override
String toString() {
  return 'Product(id: $id, name: $name, category: $category, basePrice: $basePrice, cost: $cost, recipeNotes: $recipeNotes, active: $active, photoPath: $photoPath, productCode: $productCode, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class _$ProductCopyWith<$Res> implements $ProductCopyWith<$Res> {
  factory _$ProductCopyWith(_Product value, $Res Function(_Product) _then) = __$ProductCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, String category,@JsonKey(name: 'base_price') double basePrice, double cost,@JsonKey(name: 'recipe_notes') String recipeNotes, int active,@JsonKey(name: 'photo_path') String photoPath,@JsonKey(name: 'product_code') String productCode, Map<String, String> attributes
});




}
/// @nodoc
class __$ProductCopyWithImpl<$Res>
    implements _$ProductCopyWith<$Res> {
  __$ProductCopyWithImpl(this._self, this._then);

  final _Product _self;
  final $Res Function(_Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? category = null,Object? basePrice = null,Object? cost = null,Object? recipeNotes = null,Object? active = null,Object? photoPath = null,Object? productCode = null,Object? attributes = null,}) {
  return _then(_Product(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,basePrice: null == basePrice ? _self.basePrice : basePrice // ignore: cast_nullable_to_non_nullable
as double,cost: null == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as double,recipeNotes: null == recipeNotes ? _self.recipeNotes : recipeNotes // ignore: cast_nullable_to_non_nullable
as String,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as int,photoPath: null == photoPath ? _self.photoPath : photoPath // ignore: cast_nullable_to_non_nullable
as String,productCode: null == productCode ? _self.productCode : productCode // ignore: cast_nullable_to_non_nullable
as String,attributes: null == attributes ? _self._attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on

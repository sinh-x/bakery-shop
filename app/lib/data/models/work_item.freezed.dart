// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'work_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorkItem {

 String get id; String get orderId; String get productId; String get productName; int get quantity; double get unitPrice; String get notes; String get status; String? get dueDate; String? get dueTime; String? get deliveryType; String? get deliveryAddress; int get position; bool get isBirthday; bool get isExtra; bool get isGift; int? get age; String? get createdAt; String? get updatedAt; Map<String, dynamic> get attributes;
/// Create a copy of WorkItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkItemCopyWith<WorkItem> get copyWith => _$WorkItemCopyWithImpl<WorkItem>(this as WorkItem, _$identity);

  /// Serializes this WorkItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkItem&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unitPrice, unitPrice) || other.unitPrice == unitPrice)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.status, status) || other.status == status)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.dueTime, dueTime) || other.dueTime == dueTime)&&(identical(other.deliveryType, deliveryType) || other.deliveryType == deliveryType)&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.position, position) || other.position == position)&&(identical(other.isBirthday, isBirthday) || other.isBirthday == isBirthday)&&(identical(other.isExtra, isExtra) || other.isExtra == isExtra)&&(identical(other.isGift, isGift) || other.isGift == isGift)&&(identical(other.age, age) || other.age == age)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.attributes, attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,orderId,productId,productName,quantity,unitPrice,notes,status,dueDate,dueTime,deliveryType,deliveryAddress,position,isBirthday,isExtra,isGift,age,createdAt,updatedAt,const DeepCollectionEquality().hash(attributes)]);

@override
String toString() {
  return 'WorkItem(id: $id, orderId: $orderId, productId: $productId, productName: $productName, quantity: $quantity, unitPrice: $unitPrice, notes: $notes, status: $status, dueDate: $dueDate, dueTime: $dueTime, deliveryType: $deliveryType, deliveryAddress: $deliveryAddress, position: $position, isBirthday: $isBirthday, isExtra: $isExtra, isGift: $isGift, age: $age, createdAt: $createdAt, updatedAt: $updatedAt, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class $WorkItemCopyWith<$Res>  {
  factory $WorkItemCopyWith(WorkItem value, $Res Function(WorkItem) _then) = _$WorkItemCopyWithImpl;
@useResult
$Res call({
 String id, String orderId, String productId, String productName, int quantity, double unitPrice, String notes, String status, String? dueDate, String? dueTime, String? deliveryType, String? deliveryAddress, int position, bool isBirthday, bool isExtra, bool isGift, int? age, String? createdAt, String? updatedAt, Map<String, dynamic> attributes
});




}
/// @nodoc
class _$WorkItemCopyWithImpl<$Res>
    implements $WorkItemCopyWith<$Res> {
  _$WorkItemCopyWithImpl(this._self, this._then);

  final WorkItem _self;
  final $Res Function(WorkItem) _then;

/// Create a copy of WorkItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? orderId = null,Object? productId = null,Object? productName = null,Object? quantity = null,Object? unitPrice = null,Object? notes = null,Object? status = null,Object? dueDate = freezed,Object? dueTime = freezed,Object? deliveryType = freezed,Object? deliveryAddress = freezed,Object? position = null,Object? isBirthday = null,Object? isExtra = null,Object? isGift = null,Object? age = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? attributes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as int,unitPrice: null == unitPrice ? _self.unitPrice : unitPrice // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,dueTime: freezed == dueTime ? _self.dueTime : dueTime // ignore: cast_nullable_to_non_nullable
as String?,deliveryType: freezed == deliveryType ? _self.deliveryType : deliveryType // ignore: cast_nullable_to_non_nullable
as String?,deliveryAddress: freezed == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,isBirthday: null == isBirthday ? _self.isBirthday : isBirthday // ignore: cast_nullable_to_non_nullable
as bool,isExtra: null == isExtra ? _self.isExtra : isExtra // ignore: cast_nullable_to_non_nullable
as bool,isGift: null == isGift ? _self.isGift : isGift // ignore: cast_nullable_to_non_nullable
as bool,age: freezed == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,attributes: null == attributes ? _self.attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkItem].
extension WorkItemPatterns on WorkItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkItem value)  $default,){
final _that = this;
switch (_that) {
case _WorkItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkItem value)?  $default,){
final _that = this;
switch (_that) {
case _WorkItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String orderId,  String productId,  String productName,  int quantity,  double unitPrice,  String notes,  String status,  String? dueDate,  String? dueTime,  String? deliveryType,  String? deliveryAddress,  int position,  bool isBirthday,  bool isExtra,  bool isGift,  int? age,  String? createdAt,  String? updatedAt,  Map<String, dynamic> attributes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkItem() when $default != null:
return $default(_that.id,_that.orderId,_that.productId,_that.productName,_that.quantity,_that.unitPrice,_that.notes,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.position,_that.isBirthday,_that.isExtra,_that.isGift,_that.age,_that.createdAt,_that.updatedAt,_that.attributes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String orderId,  String productId,  String productName,  int quantity,  double unitPrice,  String notes,  String status,  String? dueDate,  String? dueTime,  String? deliveryType,  String? deliveryAddress,  int position,  bool isBirthday,  bool isExtra,  bool isGift,  int? age,  String? createdAt,  String? updatedAt,  Map<String, dynamic> attributes)  $default,) {final _that = this;
switch (_that) {
case _WorkItem():
return $default(_that.id,_that.orderId,_that.productId,_that.productName,_that.quantity,_that.unitPrice,_that.notes,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.position,_that.isBirthday,_that.isExtra,_that.isGift,_that.age,_that.createdAt,_that.updatedAt,_that.attributes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String orderId,  String productId,  String productName,  int quantity,  double unitPrice,  String notes,  String status,  String? dueDate,  String? dueTime,  String? deliveryType,  String? deliveryAddress,  int position,  bool isBirthday,  bool isExtra,  bool isGift,  int? age,  String? createdAt,  String? updatedAt,  Map<String, dynamic> attributes)?  $default,) {final _that = this;
switch (_that) {
case _WorkItem() when $default != null:
return $default(_that.id,_that.orderId,_that.productId,_that.productName,_that.quantity,_that.unitPrice,_that.notes,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.position,_that.isBirthday,_that.isExtra,_that.isGift,_that.age,_that.createdAt,_that.updatedAt,_that.attributes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkItem implements WorkItem {
  const _WorkItem({required this.id, required this.orderId, this.productId = '', required this.productName, this.quantity = 1, this.unitPrice = 0.0, this.notes = '', this.status = 'pending', this.dueDate, this.dueTime, this.deliveryType, this.deliveryAddress, this.position = 0, this.isBirthday = false, this.isExtra = false, this.isGift = false, this.age, this.createdAt, this.updatedAt, final  Map<String, dynamic> attributes = const {}}): _attributes = attributes;
  factory _WorkItem.fromJson(Map<String, dynamic> json) => _$WorkItemFromJson(json);

@override final  String id;
@override final  String orderId;
@override@JsonKey() final  String productId;
@override final  String productName;
@override@JsonKey() final  int quantity;
@override@JsonKey() final  double unitPrice;
@override@JsonKey() final  String notes;
@override@JsonKey() final  String status;
@override final  String? dueDate;
@override final  String? dueTime;
@override final  String? deliveryType;
@override final  String? deliveryAddress;
@override@JsonKey() final  int position;
@override@JsonKey() final  bool isBirthday;
@override@JsonKey() final  bool isExtra;
@override@JsonKey() final  bool isGift;
@override final  int? age;
@override final  String? createdAt;
@override final  String? updatedAt;
 final  Map<String, dynamic> _attributes;
@override@JsonKey() Map<String, dynamic> get attributes {
  if (_attributes is EqualUnmodifiableMapView) return _attributes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_attributes);
}


/// Create a copy of WorkItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkItemCopyWith<_WorkItem> get copyWith => __$WorkItemCopyWithImpl<_WorkItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkItem&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unitPrice, unitPrice) || other.unitPrice == unitPrice)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.status, status) || other.status == status)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.dueTime, dueTime) || other.dueTime == dueTime)&&(identical(other.deliveryType, deliveryType) || other.deliveryType == deliveryType)&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.position, position) || other.position == position)&&(identical(other.isBirthday, isBirthday) || other.isBirthday == isBirthday)&&(identical(other.isExtra, isExtra) || other.isExtra == isExtra)&&(identical(other.isGift, isGift) || other.isGift == isGift)&&(identical(other.age, age) || other.age == age)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._attributes, _attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,orderId,productId,productName,quantity,unitPrice,notes,status,dueDate,dueTime,deliveryType,deliveryAddress,position,isBirthday,isExtra,isGift,age,createdAt,updatedAt,const DeepCollectionEquality().hash(_attributes)]);

@override
String toString() {
  return 'WorkItem(id: $id, orderId: $orderId, productId: $productId, productName: $productName, quantity: $quantity, unitPrice: $unitPrice, notes: $notes, status: $status, dueDate: $dueDate, dueTime: $dueTime, deliveryType: $deliveryType, deliveryAddress: $deliveryAddress, position: $position, isBirthday: $isBirthday, isExtra: $isExtra, isGift: $isGift, age: $age, createdAt: $createdAt, updatedAt: $updatedAt, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class _$WorkItemCopyWith<$Res> implements $WorkItemCopyWith<$Res> {
  factory _$WorkItemCopyWith(_WorkItem value, $Res Function(_WorkItem) _then) = __$WorkItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String orderId, String productId, String productName, int quantity, double unitPrice, String notes, String status, String? dueDate, String? dueTime, String? deliveryType, String? deliveryAddress, int position, bool isBirthday, bool isExtra, bool isGift, int? age, String? createdAt, String? updatedAt, Map<String, dynamic> attributes
});




}
/// @nodoc
class __$WorkItemCopyWithImpl<$Res>
    implements _$WorkItemCopyWith<$Res> {
  __$WorkItemCopyWithImpl(this._self, this._then);

  final _WorkItem _self;
  final $Res Function(_WorkItem) _then;

/// Create a copy of WorkItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? orderId = null,Object? productId = null,Object? productName = null,Object? quantity = null,Object? unitPrice = null,Object? notes = null,Object? status = null,Object? dueDate = freezed,Object? dueTime = freezed,Object? deliveryType = freezed,Object? deliveryAddress = freezed,Object? position = null,Object? isBirthday = null,Object? isExtra = null,Object? isGift = null,Object? age = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? attributes = null,}) {
  return _then(_WorkItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as int,unitPrice: null == unitPrice ? _self.unitPrice : unitPrice // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,dueTime: freezed == dueTime ? _self.dueTime : dueTime // ignore: cast_nullable_to_non_nullable
as String?,deliveryType: freezed == deliveryType ? _self.deliveryType : deliveryType // ignore: cast_nullable_to_non_nullable
as String?,deliveryAddress: freezed == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,isBirthday: null == isBirthday ? _self.isBirthday : isBirthday // ignore: cast_nullable_to_non_nullable
as bool,isExtra: null == isExtra ? _self.isExtra : isExtra // ignore: cast_nullable_to_non_nullable
as bool,isGift: null == isGift ? _self.isGift : isGift // ignore: cast_nullable_to_non_nullable
as bool,age: freezed == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,attributes: null == attributes ? _self._attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on

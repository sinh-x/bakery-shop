// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Order {

 String get id; String get orderRef; String get publicOrderCode; String get customerName; String get customerPhone; String get deliveryPhone; int? get customerId; List<OrderItem> get items; double get totalPrice; String get status; String? get dueDate; String? get dueTime; String get deliveryType; String get deliveryAddress; double get shippingFee; String get notes; String get source; String get createdBy; double get amountPaid; bool get isPaid; List<PackingItem> get packingChecklist; String? get workTicketPrintedAt; String? get workTicketPrintedBy; String get urgency; String? get acknowledgedAt;@JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime get createdAt;@JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime get updatedAt;
/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OrderCopyWith<Order> get copyWith => _$OrderCopyWithImpl<Order>(this as Order, _$identity);

  /// Serializes this Order to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Order&&(identical(other.id, id) || other.id == id)&&(identical(other.orderRef, orderRef) || other.orderRef == orderRef)&&(identical(other.publicOrderCode, publicOrderCode) || other.publicOrderCode == publicOrderCode)&&(identical(other.customerName, customerName) || other.customerName == customerName)&&(identical(other.customerPhone, customerPhone) || other.customerPhone == customerPhone)&&(identical(other.deliveryPhone, deliveryPhone) || other.deliveryPhone == deliveryPhone)&&(identical(other.customerId, customerId) || other.customerId == customerId)&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.totalPrice, totalPrice) || other.totalPrice == totalPrice)&&(identical(other.status, status) || other.status == status)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.dueTime, dueTime) || other.dueTime == dueTime)&&(identical(other.deliveryType, deliveryType) || other.deliveryType == deliveryType)&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.shippingFee, shippingFee) || other.shippingFee == shippingFee)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.amountPaid, amountPaid) || other.amountPaid == amountPaid)&&(identical(other.isPaid, isPaid) || other.isPaid == isPaid)&&const DeepCollectionEquality().equals(other.packingChecklist, packingChecklist)&&(identical(other.workTicketPrintedAt, workTicketPrintedAt) || other.workTicketPrintedAt == workTicketPrintedAt)&&(identical(other.workTicketPrintedBy, workTicketPrintedBy) || other.workTicketPrintedBy == workTicketPrintedBy)&&(identical(other.urgency, urgency) || other.urgency == urgency)&&(identical(other.acknowledgedAt, acknowledgedAt) || other.acknowledgedAt == acknowledgedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,orderRef,publicOrderCode,customerName,customerPhone,deliveryPhone,customerId,const DeepCollectionEquality().hash(items),totalPrice,status,dueDate,dueTime,deliveryType,deliveryAddress,shippingFee,notes,source,createdBy,amountPaid,isPaid,const DeepCollectionEquality().hash(packingChecklist),workTicketPrintedAt,workTicketPrintedBy,urgency,acknowledgedAt,createdAt,updatedAt]);

@override
String toString() {
  return 'Order(id: $id, orderRef: $orderRef, publicOrderCode: $publicOrderCode, customerName: $customerName, customerPhone: $customerPhone, deliveryPhone: $deliveryPhone, customerId: $customerId, items: $items, totalPrice: $totalPrice, status: $status, dueDate: $dueDate, dueTime: $dueTime, deliveryType: $deliveryType, deliveryAddress: $deliveryAddress, shippingFee: $shippingFee, notes: $notes, source: $source, createdBy: $createdBy, amountPaid: $amountPaid, isPaid: $isPaid, packingChecklist: $packingChecklist, workTicketPrintedAt: $workTicketPrintedAt, workTicketPrintedBy: $workTicketPrintedBy, urgency: $urgency, acknowledgedAt: $acknowledgedAt, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $OrderCopyWith<$Res>  {
  factory $OrderCopyWith(Order value, $Res Function(Order) _then) = _$OrderCopyWithImpl;
@useResult
$Res call({
 String id, String orderRef, String publicOrderCode, String customerName, String customerPhone, String deliveryPhone, int? customerId, List<OrderItem> items, double totalPrice, String status, String? dueDate, String? dueTime, String deliveryType, String deliveryAddress, double shippingFee, String notes, String source, String createdBy, double amountPaid, bool isPaid, List<PackingItem> packingChecklist, String? workTicketPrintedAt, String? workTicketPrintedBy, String urgency, String? acknowledgedAt,@JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime updatedAt
});




}
/// @nodoc
class _$OrderCopyWithImpl<$Res>
    implements $OrderCopyWith<$Res> {
  _$OrderCopyWithImpl(this._self, this._then);

  final Order _self;
  final $Res Function(Order) _then;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? orderRef = null,Object? publicOrderCode = null,Object? customerName = null,Object? customerPhone = null,Object? deliveryPhone = null,Object? customerId = freezed,Object? items = null,Object? totalPrice = null,Object? status = null,Object? dueDate = freezed,Object? dueTime = freezed,Object? deliveryType = null,Object? deliveryAddress = null,Object? shippingFee = null,Object? notes = null,Object? source = null,Object? createdBy = null,Object? amountPaid = null,Object? isPaid = null,Object? packingChecklist = null,Object? workTicketPrintedAt = freezed,Object? workTicketPrintedBy = freezed,Object? urgency = null,Object? acknowledgedAt = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderRef: null == orderRef ? _self.orderRef : orderRef // ignore: cast_nullable_to_non_nullable
as String,publicOrderCode: null == publicOrderCode ? _self.publicOrderCode : publicOrderCode // ignore: cast_nullable_to_non_nullable
as String,customerName: null == customerName ? _self.customerName : customerName // ignore: cast_nullable_to_non_nullable
as String,customerPhone: null == customerPhone ? _self.customerPhone : customerPhone // ignore: cast_nullable_to_non_nullable
as String,deliveryPhone: null == deliveryPhone ? _self.deliveryPhone : deliveryPhone // ignore: cast_nullable_to_non_nullable
as String,customerId: freezed == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as int?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<OrderItem>,totalPrice: null == totalPrice ? _self.totalPrice : totalPrice // ignore: cast_nullable_to_non_nullable
as double,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,dueTime: freezed == dueTime ? _self.dueTime : dueTime // ignore: cast_nullable_to_non_nullable
as String?,deliveryType: null == deliveryType ? _self.deliveryType : deliveryType // ignore: cast_nullable_to_non_nullable
as String,deliveryAddress: null == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String,shippingFee: null == shippingFee ? _self.shippingFee : shippingFee // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,amountPaid: null == amountPaid ? _self.amountPaid : amountPaid // ignore: cast_nullable_to_non_nullable
as double,isPaid: null == isPaid ? _self.isPaid : isPaid // ignore: cast_nullable_to_non_nullable
as bool,packingChecklist: null == packingChecklist ? _self.packingChecklist : packingChecklist // ignore: cast_nullable_to_non_nullable
as List<PackingItem>,workTicketPrintedAt: freezed == workTicketPrintedAt ? _self.workTicketPrintedAt : workTicketPrintedAt // ignore: cast_nullable_to_non_nullable
as String?,workTicketPrintedBy: freezed == workTicketPrintedBy ? _self.workTicketPrintedBy : workTicketPrintedBy // ignore: cast_nullable_to_non_nullable
as String?,urgency: null == urgency ? _self.urgency : urgency // ignore: cast_nullable_to_non_nullable
as String,acknowledgedAt: freezed == acknowledgedAt ? _self.acknowledgedAt : acknowledgedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Order].
extension OrderPatterns on Order {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Order value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Order() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Order value)  $default,){
final _that = this;
switch (_that) {
case _Order():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Order value)?  $default,){
final _that = this;
switch (_that) {
case _Order() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String orderRef,  String publicOrderCode,  String customerName,  String customerPhone,  String deliveryPhone,  int? customerId,  List<OrderItem> items,  double totalPrice,  String status,  String? dueDate,  String? dueTime,  String deliveryType,  String deliveryAddress,  double shippingFee,  String notes,  String source,  String createdBy,  double amountPaid,  bool isPaid,  List<PackingItem> packingChecklist,  String? workTicketPrintedAt,  String? workTicketPrintedBy,  String urgency,  String? acknowledgedAt, @JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Order() when $default != null:
return $default(_that.id,_that.orderRef,_that.publicOrderCode,_that.customerName,_that.customerPhone,_that.deliveryPhone,_that.customerId,_that.items,_that.totalPrice,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.shippingFee,_that.notes,_that.source,_that.createdBy,_that.amountPaid,_that.isPaid,_that.packingChecklist,_that.workTicketPrintedAt,_that.workTicketPrintedBy,_that.urgency,_that.acknowledgedAt,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String orderRef,  String publicOrderCode,  String customerName,  String customerPhone,  String deliveryPhone,  int? customerId,  List<OrderItem> items,  double totalPrice,  String status,  String? dueDate,  String? dueTime,  String deliveryType,  String deliveryAddress,  double shippingFee,  String notes,  String source,  String createdBy,  double amountPaid,  bool isPaid,  List<PackingItem> packingChecklist,  String? workTicketPrintedAt,  String? workTicketPrintedBy,  String urgency,  String? acknowledgedAt, @JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Order():
return $default(_that.id,_that.orderRef,_that.publicOrderCode,_that.customerName,_that.customerPhone,_that.deliveryPhone,_that.customerId,_that.items,_that.totalPrice,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.shippingFee,_that.notes,_that.source,_that.createdBy,_that.amountPaid,_that.isPaid,_that.packingChecklist,_that.workTicketPrintedAt,_that.workTicketPrintedBy,_that.urgency,_that.acknowledgedAt,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String orderRef,  String publicOrderCode,  String customerName,  String customerPhone,  String deliveryPhone,  int? customerId,  List<OrderItem> items,  double totalPrice,  String status,  String? dueDate,  String? dueTime,  String deliveryType,  String deliveryAddress,  double shippingFee,  String notes,  String source,  String createdBy,  double amountPaid,  bool isPaid,  List<PackingItem> packingChecklist,  String? workTicketPrintedAt,  String? workTicketPrintedBy,  String urgency,  String? acknowledgedAt, @JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Order() when $default != null:
return $default(_that.id,_that.orderRef,_that.publicOrderCode,_that.customerName,_that.customerPhone,_that.deliveryPhone,_that.customerId,_that.items,_that.totalPrice,_that.status,_that.dueDate,_that.dueTime,_that.deliveryType,_that.deliveryAddress,_that.shippingFee,_that.notes,_that.source,_that.createdBy,_that.amountPaid,_that.isPaid,_that.packingChecklist,_that.workTicketPrintedAt,_that.workTicketPrintedBy,_that.urgency,_that.acknowledgedAt,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Order implements Order {
  const _Order({required this.id, required this.orderRef, this.publicOrderCode = '', required this.customerName, this.customerPhone = '', this.deliveryPhone = '', this.customerId, required final  List<OrderItem> items, required this.totalPrice, this.status = 'new', this.dueDate, this.dueTime, this.deliveryType = 'pickup', this.deliveryAddress = '', this.shippingFee = 0.0, this.notes = '', this.source = '', this.createdBy = '', this.amountPaid = 0.0, this.isPaid = false, final  List<PackingItem> packingChecklist = const [], this.workTicketPrintedAt, this.workTicketPrintedBy, this.urgency = 'normal', this.acknowledgedAt, @JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) required this.createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) required this.updatedAt}): _items = items,_packingChecklist = packingChecklist;
  factory _Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

@override final  String id;
@override final  String orderRef;
@override@JsonKey() final  String publicOrderCode;
@override final  String customerName;
@override@JsonKey() final  String customerPhone;
@override@JsonKey() final  String deliveryPhone;
@override final  int? customerId;
 final  List<OrderItem> _items;
@override List<OrderItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  double totalPrice;
@override@JsonKey() final  String status;
@override final  String? dueDate;
@override final  String? dueTime;
@override@JsonKey() final  String deliveryType;
@override@JsonKey() final  String deliveryAddress;
@override@JsonKey() final  double shippingFee;
@override@JsonKey() final  String notes;
@override@JsonKey() final  String source;
@override@JsonKey() final  String createdBy;
@override@JsonKey() final  double amountPaid;
@override@JsonKey() final  bool isPaid;
 final  List<PackingItem> _packingChecklist;
@override@JsonKey() List<PackingItem> get packingChecklist {
  if (_packingChecklist is EqualUnmodifiableListView) return _packingChecklist;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_packingChecklist);
}

@override final  String? workTicketPrintedAt;
@override final  String? workTicketPrintedBy;
@override@JsonKey() final  String urgency;
@override final  String? acknowledgedAt;
@override@JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) final  DateTime createdAt;
@override@JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) final  DateTime updatedAt;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OrderCopyWith<_Order> get copyWith => __$OrderCopyWithImpl<_Order>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OrderToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Order&&(identical(other.id, id) || other.id == id)&&(identical(other.orderRef, orderRef) || other.orderRef == orderRef)&&(identical(other.publicOrderCode, publicOrderCode) || other.publicOrderCode == publicOrderCode)&&(identical(other.customerName, customerName) || other.customerName == customerName)&&(identical(other.customerPhone, customerPhone) || other.customerPhone == customerPhone)&&(identical(other.deliveryPhone, deliveryPhone) || other.deliveryPhone == deliveryPhone)&&(identical(other.customerId, customerId) || other.customerId == customerId)&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.totalPrice, totalPrice) || other.totalPrice == totalPrice)&&(identical(other.status, status) || other.status == status)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.dueTime, dueTime) || other.dueTime == dueTime)&&(identical(other.deliveryType, deliveryType) || other.deliveryType == deliveryType)&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.shippingFee, shippingFee) || other.shippingFee == shippingFee)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.amountPaid, amountPaid) || other.amountPaid == amountPaid)&&(identical(other.isPaid, isPaid) || other.isPaid == isPaid)&&const DeepCollectionEquality().equals(other._packingChecklist, _packingChecklist)&&(identical(other.workTicketPrintedAt, workTicketPrintedAt) || other.workTicketPrintedAt == workTicketPrintedAt)&&(identical(other.workTicketPrintedBy, workTicketPrintedBy) || other.workTicketPrintedBy == workTicketPrintedBy)&&(identical(other.urgency, urgency) || other.urgency == urgency)&&(identical(other.acknowledgedAt, acknowledgedAt) || other.acknowledgedAt == acknowledgedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,orderRef,publicOrderCode,customerName,customerPhone,deliveryPhone,customerId,const DeepCollectionEquality().hash(_items),totalPrice,status,dueDate,dueTime,deliveryType,deliveryAddress,shippingFee,notes,source,createdBy,amountPaid,isPaid,const DeepCollectionEquality().hash(_packingChecklist),workTicketPrintedAt,workTicketPrintedBy,urgency,acknowledgedAt,createdAt,updatedAt]);

@override
String toString() {
  return 'Order(id: $id, orderRef: $orderRef, publicOrderCode: $publicOrderCode, customerName: $customerName, customerPhone: $customerPhone, deliveryPhone: $deliveryPhone, customerId: $customerId, items: $items, totalPrice: $totalPrice, status: $status, dueDate: $dueDate, dueTime: $dueTime, deliveryType: $deliveryType, deliveryAddress: $deliveryAddress, shippingFee: $shippingFee, notes: $notes, source: $source, createdBy: $createdBy, amountPaid: $amountPaid, isPaid: $isPaid, packingChecklist: $packingChecklist, workTicketPrintedAt: $workTicketPrintedAt, workTicketPrintedBy: $workTicketPrintedBy, urgency: $urgency, acknowledgedAt: $acknowledgedAt, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$OrderCopyWith<$Res> implements $OrderCopyWith<$Res> {
  factory _$OrderCopyWith(_Order value, $Res Function(_Order) _then) = __$OrderCopyWithImpl;
@override @useResult
$Res call({
 String id, String orderRef, String publicOrderCode, String customerName, String customerPhone, String deliveryPhone, int? customerId, List<OrderItem> items, double totalPrice, String status, String? dueDate, String? dueTime, String deliveryType, String deliveryAddress, double shippingFee, String notes, String source, String createdBy, double amountPaid, bool isPaid, List<PackingItem> packingChecklist, String? workTicketPrintedAt, String? workTicketPrintedBy, String urgency, String? acknowledgedAt,@JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson) DateTime updatedAt
});




}
/// @nodoc
class __$OrderCopyWithImpl<$Res>
    implements _$OrderCopyWith<$Res> {
  __$OrderCopyWithImpl(this._self, this._then);

  final _Order _self;
  final $Res Function(_Order) _then;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? orderRef = null,Object? publicOrderCode = null,Object? customerName = null,Object? customerPhone = null,Object? deliveryPhone = null,Object? customerId = freezed,Object? items = null,Object? totalPrice = null,Object? status = null,Object? dueDate = freezed,Object? dueTime = freezed,Object? deliveryType = null,Object? deliveryAddress = null,Object? shippingFee = null,Object? notes = null,Object? source = null,Object? createdBy = null,Object? amountPaid = null,Object? isPaid = null,Object? packingChecklist = null,Object? workTicketPrintedAt = freezed,Object? workTicketPrintedBy = freezed,Object? urgency = null,Object? acknowledgedAt = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Order(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderRef: null == orderRef ? _self.orderRef : orderRef // ignore: cast_nullable_to_non_nullable
as String,publicOrderCode: null == publicOrderCode ? _self.publicOrderCode : publicOrderCode // ignore: cast_nullable_to_non_nullable
as String,customerName: null == customerName ? _self.customerName : customerName // ignore: cast_nullable_to_non_nullable
as String,customerPhone: null == customerPhone ? _self.customerPhone : customerPhone // ignore: cast_nullable_to_non_nullable
as String,deliveryPhone: null == deliveryPhone ? _self.deliveryPhone : deliveryPhone // ignore: cast_nullable_to_non_nullable
as String,customerId: freezed == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as int?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<OrderItem>,totalPrice: null == totalPrice ? _self.totalPrice : totalPrice // ignore: cast_nullable_to_non_nullable
as double,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,dueTime: freezed == dueTime ? _self.dueTime : dueTime // ignore: cast_nullable_to_non_nullable
as String?,deliveryType: null == deliveryType ? _self.deliveryType : deliveryType // ignore: cast_nullable_to_non_nullable
as String,deliveryAddress: null == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String,shippingFee: null == shippingFee ? _self.shippingFee : shippingFee // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,amountPaid: null == amountPaid ? _self.amountPaid : amountPaid // ignore: cast_nullable_to_non_nullable
as double,isPaid: null == isPaid ? _self.isPaid : isPaid // ignore: cast_nullable_to_non_nullable
as bool,packingChecklist: null == packingChecklist ? _self._packingChecklist : packingChecklist // ignore: cast_nullable_to_non_nullable
as List<PackingItem>,workTicketPrintedAt: freezed == workTicketPrintedAt ? _self.workTicketPrintedAt : workTicketPrintedAt // ignore: cast_nullable_to_non_nullable
as String?,workTicketPrintedBy: freezed == workTicketPrintedBy ? _self.workTicketPrintedBy : workTicketPrintedBy // ignore: cast_nullable_to_non_nullable
as String?,urgency: null == urgency ? _self.urgency : urgency // ignore: cast_nullable_to_non_nullable
as String,acknowledgedAt: freezed == acknowledgedAt ? _self.acknowledgedAt : acknowledgedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on

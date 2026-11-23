// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'payment_transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PaymentTransaction {

 String get id; String get orderId; String get type; String get method; double get amount;@JsonKey(name: 'note') String get notes;@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get createdAt;@JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get invalidatedAt;@JsonKey(name: 'invalidatedBy') String get invalidatedBy;@JsonKey(name: 'paymentSource') String? get paymentSource; String get destinationStatus;@JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get destinationResolvedAt; String get destinationResolvedBy;
/// Create a copy of PaymentTransaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaymentTransactionCopyWith<PaymentTransaction> get copyWith => _$PaymentTransactionCopyWithImpl<PaymentTransaction>(this as PaymentTransaction, _$identity);

  /// Serializes this PaymentTransaction to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaymentTransaction&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.type, type) || other.type == type)&&(identical(other.method, method) || other.method == method)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.invalidatedAt, invalidatedAt) || other.invalidatedAt == invalidatedAt)&&(identical(other.invalidatedBy, invalidatedBy) || other.invalidatedBy == invalidatedBy)&&(identical(other.paymentSource, paymentSource) || other.paymentSource == paymentSource)&&(identical(other.destinationStatus, destinationStatus) || other.destinationStatus == destinationStatus)&&(identical(other.destinationResolvedAt, destinationResolvedAt) || other.destinationResolvedAt == destinationResolvedAt)&&(identical(other.destinationResolvedBy, destinationResolvedBy) || other.destinationResolvedBy == destinationResolvedBy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,orderId,type,method,amount,notes,createdAt,invalidatedAt,invalidatedBy,paymentSource,destinationStatus,destinationResolvedAt,destinationResolvedBy);

@override
String toString() {
  return 'PaymentTransaction(id: $id, orderId: $orderId, type: $type, method: $method, amount: $amount, notes: $notes, createdAt: $createdAt, invalidatedAt: $invalidatedAt, invalidatedBy: $invalidatedBy, paymentSource: $paymentSource, destinationStatus: $destinationStatus, destinationResolvedAt: $destinationResolvedAt, destinationResolvedBy: $destinationResolvedBy)';
}


}

/// @nodoc
abstract mixin class $PaymentTransactionCopyWith<$Res>  {
  factory $PaymentTransactionCopyWith(PaymentTransaction value, $Res Function(PaymentTransaction) _then) = _$PaymentTransactionCopyWithImpl;
@useResult
$Res call({
 String id, String orderId, String type, String method, double amount,@JsonKey(name: 'note') String notes,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? invalidatedAt,@JsonKey(name: 'invalidatedBy') String invalidatedBy,@JsonKey(name: 'paymentSource') String? paymentSource, String destinationStatus,@JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? destinationResolvedAt, String destinationResolvedBy
});




}
/// @nodoc
class _$PaymentTransactionCopyWithImpl<$Res>
    implements $PaymentTransactionCopyWith<$Res> {
  _$PaymentTransactionCopyWithImpl(this._self, this._then);

  final PaymentTransaction _self;
  final $Res Function(PaymentTransaction) _then;

/// Create a copy of PaymentTransaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? orderId = null,Object? type = null,Object? method = null,Object? amount = null,Object? notes = null,Object? createdAt = freezed,Object? invalidatedAt = freezed,Object? invalidatedBy = null,Object? paymentSource = freezed,Object? destinationStatus = null,Object? destinationResolvedAt = freezed,Object? destinationResolvedBy = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,invalidatedAt: freezed == invalidatedAt ? _self.invalidatedAt : invalidatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,invalidatedBy: null == invalidatedBy ? _self.invalidatedBy : invalidatedBy // ignore: cast_nullable_to_non_nullable
as String,paymentSource: freezed == paymentSource ? _self.paymentSource : paymentSource // ignore: cast_nullable_to_non_nullable
as String?,destinationStatus: null == destinationStatus ? _self.destinationStatus : destinationStatus // ignore: cast_nullable_to_non_nullable
as String,destinationResolvedAt: freezed == destinationResolvedAt ? _self.destinationResolvedAt : destinationResolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,destinationResolvedBy: null == destinationResolvedBy ? _self.destinationResolvedBy : destinationResolvedBy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PaymentTransaction].
extension PaymentTransactionPatterns on PaymentTransaction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PaymentTransaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PaymentTransaction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PaymentTransaction value)  $default,){
final _that = this;
switch (_that) {
case _PaymentTransaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PaymentTransaction value)?  $default,){
final _that = this;
switch (_that) {
case _PaymentTransaction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String orderId,  String type,  String method,  double amount, @JsonKey(name: 'note')  String notes, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? invalidatedAt, @JsonKey(name: 'invalidatedBy')  String invalidatedBy, @JsonKey(name: 'paymentSource')  String? paymentSource,  String destinationStatus, @JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? destinationResolvedAt,  String destinationResolvedBy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PaymentTransaction() when $default != null:
return $default(_that.id,_that.orderId,_that.type,_that.method,_that.amount,_that.notes,_that.createdAt,_that.invalidatedAt,_that.invalidatedBy,_that.paymentSource,_that.destinationStatus,_that.destinationResolvedAt,_that.destinationResolvedBy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String orderId,  String type,  String method,  double amount, @JsonKey(name: 'note')  String notes, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? invalidatedAt, @JsonKey(name: 'invalidatedBy')  String invalidatedBy, @JsonKey(name: 'paymentSource')  String? paymentSource,  String destinationStatus, @JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? destinationResolvedAt,  String destinationResolvedBy)  $default,) {final _that = this;
switch (_that) {
case _PaymentTransaction():
return $default(_that.id,_that.orderId,_that.type,_that.method,_that.amount,_that.notes,_that.createdAt,_that.invalidatedAt,_that.invalidatedBy,_that.paymentSource,_that.destinationStatus,_that.destinationResolvedAt,_that.destinationResolvedBy);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String orderId,  String type,  String method,  double amount, @JsonKey(name: 'note')  String notes, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? invalidatedAt, @JsonKey(name: 'invalidatedBy')  String invalidatedBy, @JsonKey(name: 'paymentSource')  String? paymentSource,  String destinationStatus, @JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? destinationResolvedAt,  String destinationResolvedBy)?  $default,) {final _that = this;
switch (_that) {
case _PaymentTransaction() when $default != null:
return $default(_that.id,_that.orderId,_that.type,_that.method,_that.amount,_that.notes,_that.createdAt,_that.invalidatedAt,_that.invalidatedBy,_that.paymentSource,_that.destinationStatus,_that.destinationResolvedAt,_that.destinationResolvedBy);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PaymentTransaction implements PaymentTransaction {
  const _PaymentTransaction({required this.id, required this.orderId, this.type = 'deposit', this.method = 'cash', required this.amount, @JsonKey(name: 'note') this.notes = '', @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.createdAt, @JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.invalidatedAt, @JsonKey(name: 'invalidatedBy') this.invalidatedBy = '', @JsonKey(name: 'paymentSource') this.paymentSource, this.destinationStatus = 'known', @JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson) this.destinationResolvedAt, this.destinationResolvedBy = ''});
  factory _PaymentTransaction.fromJson(Map<String, dynamic> json) => _$PaymentTransactionFromJson(json);

@override final  String id;
@override final  String orderId;
@override@JsonKey() final  String type;
@override@JsonKey() final  String method;
@override final  double amount;
@override@JsonKey(name: 'note') final  String notes;
@override@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? createdAt;
@override@JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? invalidatedAt;
@override@JsonKey(name: 'invalidatedBy') final  String invalidatedBy;
@override@JsonKey(name: 'paymentSource') final  String? paymentSource;
@override@JsonKey() final  String destinationStatus;
@override@JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? destinationResolvedAt;
@override@JsonKey() final  String destinationResolvedBy;

/// Create a copy of PaymentTransaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PaymentTransactionCopyWith<_PaymentTransaction> get copyWith => __$PaymentTransactionCopyWithImpl<_PaymentTransaction>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PaymentTransactionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PaymentTransaction&&(identical(other.id, id) || other.id == id)&&(identical(other.orderId, orderId) || other.orderId == orderId)&&(identical(other.type, type) || other.type == type)&&(identical(other.method, method) || other.method == method)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.invalidatedAt, invalidatedAt) || other.invalidatedAt == invalidatedAt)&&(identical(other.invalidatedBy, invalidatedBy) || other.invalidatedBy == invalidatedBy)&&(identical(other.paymentSource, paymentSource) || other.paymentSource == paymentSource)&&(identical(other.destinationStatus, destinationStatus) || other.destinationStatus == destinationStatus)&&(identical(other.destinationResolvedAt, destinationResolvedAt) || other.destinationResolvedAt == destinationResolvedAt)&&(identical(other.destinationResolvedBy, destinationResolvedBy) || other.destinationResolvedBy == destinationResolvedBy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,orderId,type,method,amount,notes,createdAt,invalidatedAt,invalidatedBy,paymentSource,destinationStatus,destinationResolvedAt,destinationResolvedBy);

@override
String toString() {
  return 'PaymentTransaction(id: $id, orderId: $orderId, type: $type, method: $method, amount: $amount, notes: $notes, createdAt: $createdAt, invalidatedAt: $invalidatedAt, invalidatedBy: $invalidatedBy, paymentSource: $paymentSource, destinationStatus: $destinationStatus, destinationResolvedAt: $destinationResolvedAt, destinationResolvedBy: $destinationResolvedBy)';
}


}

/// @nodoc
abstract mixin class _$PaymentTransactionCopyWith<$Res> implements $PaymentTransactionCopyWith<$Res> {
  factory _$PaymentTransactionCopyWith(_PaymentTransaction value, $Res Function(_PaymentTransaction) _then) = __$PaymentTransactionCopyWithImpl;
@override @useResult
$Res call({
 String id, String orderId, String type, String method, double amount,@JsonKey(name: 'note') String notes,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'invalidatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? invalidatedAt,@JsonKey(name: 'invalidatedBy') String invalidatedBy,@JsonKey(name: 'paymentSource') String? paymentSource, String destinationStatus,@JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? destinationResolvedAt, String destinationResolvedBy
});




}
/// @nodoc
class __$PaymentTransactionCopyWithImpl<$Res>
    implements _$PaymentTransactionCopyWith<$Res> {
  __$PaymentTransactionCopyWithImpl(this._self, this._then);

  final _PaymentTransaction _self;
  final $Res Function(_PaymentTransaction) _then;

/// Create a copy of PaymentTransaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? orderId = null,Object? type = null,Object? method = null,Object? amount = null,Object? notes = null,Object? createdAt = freezed,Object? invalidatedAt = freezed,Object? invalidatedBy = null,Object? paymentSource = freezed,Object? destinationStatus = null,Object? destinationResolvedAt = freezed,Object? destinationResolvedBy = null,}) {
  return _then(_PaymentTransaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,orderId: null == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,invalidatedAt: freezed == invalidatedAt ? _self.invalidatedAt : invalidatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,invalidatedBy: null == invalidatedBy ? _self.invalidatedBy : invalidatedBy // ignore: cast_nullable_to_non_nullable
as String,paymentSource: freezed == paymentSource ? _self.paymentSource : paymentSource // ignore: cast_nullable_to_non_nullable
as String?,destinationStatus: null == destinationStatus ? _self.destinationStatus : destinationStatus // ignore: cast_nullable_to_non_nullable
as String,destinationResolvedAt: freezed == destinationResolvedAt ? _self.destinationResolvedAt : destinationResolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,destinationResolvedBy: null == destinationResolvedBy ? _self.destinationResolvedBy : destinationResolvedBy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

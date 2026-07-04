// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'customer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CustomerPhone {

 String get phone;@JsonKey(name: 'isPrimary') bool get isPrimary;
/// Create a copy of CustomerPhone
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomerPhoneCopyWith<CustomerPhone> get copyWith => _$CustomerPhoneCopyWithImpl<CustomerPhone>(this as CustomerPhone, _$identity);

  /// Serializes this CustomerPhone to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomerPhone&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,phone,isPrimary);

@override
String toString() {
  return 'CustomerPhone(phone: $phone, isPrimary: $isPrimary)';
}


}

/// @nodoc
abstract mixin class $CustomerPhoneCopyWith<$Res>  {
  factory $CustomerPhoneCopyWith(CustomerPhone value, $Res Function(CustomerPhone) _then) = _$CustomerPhoneCopyWithImpl;
@useResult
$Res call({
 String phone,@JsonKey(name: 'isPrimary') bool isPrimary
});




}
/// @nodoc
class _$CustomerPhoneCopyWithImpl<$Res>
    implements $CustomerPhoneCopyWith<$Res> {
  _$CustomerPhoneCopyWithImpl(this._self, this._then);

  final CustomerPhone _self;
  final $Res Function(CustomerPhone) _then;

/// Create a copy of CustomerPhone
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phone = null,Object? isPrimary = null,}) {
  return _then(_self.copyWith(
phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomerPhone].
extension CustomerPhonePatterns on CustomerPhone {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomerPhone value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomerPhone() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomerPhone value)  $default,){
final _that = this;
switch (_that) {
case _CustomerPhone():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomerPhone value)?  $default,){
final _that = this;
switch (_that) {
case _CustomerPhone() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String phone, @JsonKey(name: 'isPrimary')  bool isPrimary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomerPhone() when $default != null:
return $default(_that.phone,_that.isPrimary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String phone, @JsonKey(name: 'isPrimary')  bool isPrimary)  $default,) {final _that = this;
switch (_that) {
case _CustomerPhone():
return $default(_that.phone,_that.isPrimary);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String phone, @JsonKey(name: 'isPrimary')  bool isPrimary)?  $default,) {final _that = this;
switch (_that) {
case _CustomerPhone() when $default != null:
return $default(_that.phone,_that.isPrimary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CustomerPhone implements CustomerPhone {
  const _CustomerPhone({required this.phone, @JsonKey(name: 'isPrimary') this.isPrimary = false});
  factory _CustomerPhone.fromJson(Map<String, dynamic> json) => _$CustomerPhoneFromJson(json);

@override final  String phone;
@override@JsonKey(name: 'isPrimary') final  bool isPrimary;

/// Create a copy of CustomerPhone
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomerPhoneCopyWith<_CustomerPhone> get copyWith => __$CustomerPhoneCopyWithImpl<_CustomerPhone>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomerPhoneToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomerPhone&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,phone,isPrimary);

@override
String toString() {
  return 'CustomerPhone(phone: $phone, isPrimary: $isPrimary)';
}


}

/// @nodoc
abstract mixin class _$CustomerPhoneCopyWith<$Res> implements $CustomerPhoneCopyWith<$Res> {
  factory _$CustomerPhoneCopyWith(_CustomerPhone value, $Res Function(_CustomerPhone) _then) = __$CustomerPhoneCopyWithImpl;
@override @useResult
$Res call({
 String phone,@JsonKey(name: 'isPrimary') bool isPrimary
});




}
/// @nodoc
class __$CustomerPhoneCopyWithImpl<$Res>
    implements _$CustomerPhoneCopyWith<$Res> {
  __$CustomerPhoneCopyWithImpl(this._self, this._then);

  final _CustomerPhone _self;
  final $Res Function(_CustomerPhone) _then;

/// Create a copy of CustomerPhone
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phone = null,Object? isPrimary = null,}) {
  return _then(_CustomerPhone(
phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$CustomerYearSummary {

 int get year;@JsonKey(name: 'orderCount') int get orderCount;@JsonKey(name: 'totalVolume') double get totalVolume;
/// Create a copy of CustomerYearSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomerYearSummaryCopyWith<CustomerYearSummary> get copyWith => _$CustomerYearSummaryCopyWithImpl<CustomerYearSummary>(this as CustomerYearSummary, _$identity);

  /// Serializes this CustomerYearSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomerYearSummary&&(identical(other.year, year) || other.year == year)&&(identical(other.orderCount, orderCount) || other.orderCount == orderCount)&&(identical(other.totalVolume, totalVolume) || other.totalVolume == totalVolume));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,year,orderCount,totalVolume);

@override
String toString() {
  return 'CustomerYearSummary(year: $year, orderCount: $orderCount, totalVolume: $totalVolume)';
}


}

/// @nodoc
abstract mixin class $CustomerYearSummaryCopyWith<$Res>  {
  factory $CustomerYearSummaryCopyWith(CustomerYearSummary value, $Res Function(CustomerYearSummary) _then) = _$CustomerYearSummaryCopyWithImpl;
@useResult
$Res call({
 int year,@JsonKey(name: 'orderCount') int orderCount,@JsonKey(name: 'totalVolume') double totalVolume
});




}
/// @nodoc
class _$CustomerYearSummaryCopyWithImpl<$Res>
    implements $CustomerYearSummaryCopyWith<$Res> {
  _$CustomerYearSummaryCopyWithImpl(this._self, this._then);

  final CustomerYearSummary _self;
  final $Res Function(CustomerYearSummary) _then;

/// Create a copy of CustomerYearSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? year = null,Object? orderCount = null,Object? totalVolume = null,}) {
  return _then(_self.copyWith(
year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,orderCount: null == orderCount ? _self.orderCount : orderCount // ignore: cast_nullable_to_non_nullable
as int,totalVolume: null == totalVolume ? _self.totalVolume : totalVolume // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomerYearSummary].
extension CustomerYearSummaryPatterns on CustomerYearSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomerYearSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomerYearSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomerYearSummary value)  $default,){
final _that = this;
switch (_that) {
case _CustomerYearSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomerYearSummary value)?  $default,){
final _that = this;
switch (_that) {
case _CustomerYearSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int year, @JsonKey(name: 'orderCount')  int orderCount, @JsonKey(name: 'totalVolume')  double totalVolume)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomerYearSummary() when $default != null:
return $default(_that.year,_that.orderCount,_that.totalVolume);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int year, @JsonKey(name: 'orderCount')  int orderCount, @JsonKey(name: 'totalVolume')  double totalVolume)  $default,) {final _that = this;
switch (_that) {
case _CustomerYearSummary():
return $default(_that.year,_that.orderCount,_that.totalVolume);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int year, @JsonKey(name: 'orderCount')  int orderCount, @JsonKey(name: 'totalVolume')  double totalVolume)?  $default,) {final _that = this;
switch (_that) {
case _CustomerYearSummary() when $default != null:
return $default(_that.year,_that.orderCount,_that.totalVolume);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CustomerYearSummary implements CustomerYearSummary {
  const _CustomerYearSummary({required this.year, @JsonKey(name: 'orderCount') this.orderCount = 0, @JsonKey(name: 'totalVolume') this.totalVolume = 0.0});
  factory _CustomerYearSummary.fromJson(Map<String, dynamic> json) => _$CustomerYearSummaryFromJson(json);

@override final  int year;
@override@JsonKey(name: 'orderCount') final  int orderCount;
@override@JsonKey(name: 'totalVolume') final  double totalVolume;

/// Create a copy of CustomerYearSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomerYearSummaryCopyWith<_CustomerYearSummary> get copyWith => __$CustomerYearSummaryCopyWithImpl<_CustomerYearSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomerYearSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomerYearSummary&&(identical(other.year, year) || other.year == year)&&(identical(other.orderCount, orderCount) || other.orderCount == orderCount)&&(identical(other.totalVolume, totalVolume) || other.totalVolume == totalVolume));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,year,orderCount,totalVolume);

@override
String toString() {
  return 'CustomerYearSummary(year: $year, orderCount: $orderCount, totalVolume: $totalVolume)';
}


}

/// @nodoc
abstract mixin class _$CustomerYearSummaryCopyWith<$Res> implements $CustomerYearSummaryCopyWith<$Res> {
  factory _$CustomerYearSummaryCopyWith(_CustomerYearSummary value, $Res Function(_CustomerYearSummary) _then) = __$CustomerYearSummaryCopyWithImpl;
@override @useResult
$Res call({
 int year,@JsonKey(name: 'orderCount') int orderCount,@JsonKey(name: 'totalVolume') double totalVolume
});




}
/// @nodoc
class __$CustomerYearSummaryCopyWithImpl<$Res>
    implements _$CustomerYearSummaryCopyWith<$Res> {
  __$CustomerYearSummaryCopyWithImpl(this._self, this._then);

  final _CustomerYearSummary _self;
  final $Res Function(_CustomerYearSummary) _then;

/// Create a copy of CustomerYearSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? year = null,Object? orderCount = null,Object? totalVolume = null,}) {
  return _then(_CustomerYearSummary(
year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,orderCount: null == orderCount ? _self.orderCount : orderCount // ignore: cast_nullable_to_non_nullable
as int,totalVolume: null == totalVolume ? _self.totalVolume : totalVolume // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$Customer {

 int get id; String get name; String get phone; List<CustomerPhone> get phones;@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get createdAt;@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get updatedAt;/// Per-year order summary from backend `customer_year_summary` table
/// (DG-206 Phase 1). Only populated by `GET /api/customers/:id`; list
/// responses do not include it.
@JsonKey(name: 'yearSummary') CustomerYearSummary? get yearSummary;
/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomerCopyWith<Customer> get copyWith => _$CustomerCopyWithImpl<Customer>(this as Customer, _$identity);

  /// Serializes this Customer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Customer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&const DeepCollectionEquality().equals(other.phones, phones)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.yearSummary, yearSummary) || other.yearSummary == yearSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,const DeepCollectionEquality().hash(phones),createdAt,updatedAt,yearSummary);

@override
String toString() {
  return 'Customer(id: $id, name: $name, phone: $phone, phones: $phones, createdAt: $createdAt, updatedAt: $updatedAt, yearSummary: $yearSummary)';
}


}

/// @nodoc
abstract mixin class $CustomerCopyWith<$Res>  {
  factory $CustomerCopyWith(Customer value, $Res Function(Customer) _then) = _$CustomerCopyWithImpl;
@useResult
$Res call({
 int id, String name, String phone, List<CustomerPhone> phones,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt,@JsonKey(name: 'yearSummary') CustomerYearSummary? yearSummary
});


$CustomerYearSummaryCopyWith<$Res>? get yearSummary;

}
/// @nodoc
class _$CustomerCopyWithImpl<$Res>
    implements $CustomerCopyWith<$Res> {
  _$CustomerCopyWithImpl(this._self, this._then);

  final Customer _self;
  final $Res Function(Customer) _then;

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? phones = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? yearSummary = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,phones: null == phones ? _self.phones : phones // ignore: cast_nullable_to_non_nullable
as List<CustomerPhone>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,yearSummary: freezed == yearSummary ? _self.yearSummary : yearSummary // ignore: cast_nullable_to_non_nullable
as CustomerYearSummary?,
  ));
}
/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CustomerYearSummaryCopyWith<$Res>? get yearSummary {
    if (_self.yearSummary == null) {
    return null;
  }

  return $CustomerYearSummaryCopyWith<$Res>(_self.yearSummary!, (value) {
    return _then(_self.copyWith(yearSummary: value));
  });
}
}


/// Adds pattern-matching-related methods to [Customer].
extension CustomerPatterns on Customer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Customer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Customer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Customer value)  $default,){
final _that = this;
switch (_that) {
case _Customer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Customer value)?  $default,){
final _that = this;
switch (_that) {
case _Customer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt, @JsonKey(name: 'yearSummary')  CustomerYearSummary? yearSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Customer() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt,_that.yearSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt, @JsonKey(name: 'yearSummary')  CustomerYearSummary? yearSummary)  $default,) {final _that = this;
switch (_that) {
case _Customer():
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt,_that.yearSummary);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt, @JsonKey(name: 'yearSummary')  CustomerYearSummary? yearSummary)?  $default,) {final _that = this;
switch (_that) {
case _Customer() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt,_that.yearSummary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Customer implements Customer {
  const _Customer({required this.id, required this.name, this.phone = '', final  List<CustomerPhone> phones = const <CustomerPhone>[], @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.updatedAt, @JsonKey(name: 'yearSummary') this.yearSummary}): _phones = phones;
  factory _Customer.fromJson(Map<String, dynamic> json) => _$CustomerFromJson(json);

@override final  int id;
@override final  String name;
@override@JsonKey() final  String phone;
 final  List<CustomerPhone> _phones;
@override@JsonKey() List<CustomerPhone> get phones {
  if (_phones is EqualUnmodifiableListView) return _phones;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_phones);
}

@override@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? createdAt;
@override@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? updatedAt;
/// Per-year order summary from backend `customer_year_summary` table
/// (DG-206 Phase 1). Only populated by `GET /api/customers/:id`; list
/// responses do not include it.
@override@JsonKey(name: 'yearSummary') final  CustomerYearSummary? yearSummary;

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomerCopyWith<_Customer> get copyWith => __$CustomerCopyWithImpl<_Customer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Customer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&const DeepCollectionEquality().equals(other._phones, _phones)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.yearSummary, yearSummary) || other.yearSummary == yearSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,const DeepCollectionEquality().hash(_phones),createdAt,updatedAt,yearSummary);

@override
String toString() {
  return 'Customer(id: $id, name: $name, phone: $phone, phones: $phones, createdAt: $createdAt, updatedAt: $updatedAt, yearSummary: $yearSummary)';
}


}

/// @nodoc
abstract mixin class _$CustomerCopyWith<$Res> implements $CustomerCopyWith<$Res> {
  factory _$CustomerCopyWith(_Customer value, $Res Function(_Customer) _then) = __$CustomerCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, String phone, List<CustomerPhone> phones,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt,@JsonKey(name: 'yearSummary') CustomerYearSummary? yearSummary
});


@override $CustomerYearSummaryCopyWith<$Res>? get yearSummary;

}
/// @nodoc
class __$CustomerCopyWithImpl<$Res>
    implements _$CustomerCopyWith<$Res> {
  __$CustomerCopyWithImpl(this._self, this._then);

  final _Customer _self;
  final $Res Function(_Customer) _then;

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? phones = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? yearSummary = freezed,}) {
  return _then(_Customer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,phones: null == phones ? _self._phones : phones // ignore: cast_nullable_to_non_nullable
as List<CustomerPhone>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,yearSummary: freezed == yearSummary ? _self.yearSummary : yearSummary // ignore: cast_nullable_to_non_nullable
as CustomerYearSummary?,
  ));
}

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CustomerYearSummaryCopyWith<$Res>? get yearSummary {
    if (_self.yearSummary == null) {
    return null;
  }

  return $CustomerYearSummaryCopyWith<$Res>(_self.yearSummary!, (value) {
    return _then(_self.copyWith(yearSummary: value));
  });
}
}

// dart format on

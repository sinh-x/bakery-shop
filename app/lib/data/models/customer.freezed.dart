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
mixin _$Customer {

 int get id; String get name; String get phone; List<CustomerPhone> get phones;@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get createdAt;@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get updatedAt;
/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomerCopyWith<Customer> get copyWith => _$CustomerCopyWithImpl<Customer>(this as Customer, _$identity);

  /// Serializes this Customer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Customer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&const DeepCollectionEquality().equals(other.phones, phones)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,const DeepCollectionEquality().hash(phones),createdAt,updatedAt);

@override
String toString() {
  return 'Customer(id: $id, name: $name, phone: $phone, phones: $phones, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $CustomerCopyWith<$Res>  {
  factory $CustomerCopyWith(Customer value, $Res Function(Customer) _then) = _$CustomerCopyWithImpl;
@useResult
$Res call({
 int id, String name, String phone, List<CustomerPhone> phones,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$CustomerCopyWithImpl<$Res>
    implements $CustomerCopyWith<$Res> {
  _$CustomerCopyWithImpl(this._self, this._then);

  final Customer _self;
  final $Res Function(Customer) _then;

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? phones = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,phones: null == phones ? _self.phones : phones // ignore: cast_nullable_to_non_nullable
as List<CustomerPhone>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Customer() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Customer():
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  String phone,  List<CustomerPhone> phones, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Customer() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.phones,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Customer implements Customer {
  const _Customer({required this.id, required this.name, this.phone = '', final  List<CustomerPhone> phones = const <CustomerPhone>[], @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.updatedAt}): _phones = phones;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Customer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&const DeepCollectionEquality().equals(other._phones, _phones)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,const DeepCollectionEquality().hash(_phones),createdAt,updatedAt);

@override
String toString() {
  return 'Customer(id: $id, name: $name, phone: $phone, phones: $phones, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$CustomerCopyWith<$Res> implements $CustomerCopyWith<$Res> {
  factory _$CustomerCopyWith(_Customer value, $Res Function(_Customer) _then) = __$CustomerCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, String phone, List<CustomerPhone> phones,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$CustomerCopyWithImpl<$Res>
    implements _$CustomerCopyWith<$Res> {
  __$CustomerCopyWithImpl(this._self, this._then);

  final _Customer _self;
  final $Res Function(_Customer) _then;

/// Create a copy of Customer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? phones = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_Customer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,phones: null == phones ? _self._phones : phones // ignore: cast_nullable_to_non_nullable
as List<CustomerPhone>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on

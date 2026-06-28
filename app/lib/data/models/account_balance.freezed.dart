// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_balance.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AccountBalance {

@JsonKey(name: 'accountId') String get accountId; String get code; String get name; String get type;@JsonKey(name: 'parentId') String? get parentId; double get debit; double get credit; double get balance;
/// Create a copy of AccountBalance
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountBalanceCopyWith<AccountBalance> get copyWith => _$AccountBalanceCopyWithImpl<AccountBalance>(this as AccountBalance, _$identity);

  /// Serializes this AccountBalance to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountBalance&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.debit, debit) || other.debit == debit)&&(identical(other.credit, credit) || other.credit == credit)&&(identical(other.balance, balance) || other.balance == balance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,accountId,code,name,type,parentId,debit,credit,balance);

@override
String toString() {
  return 'AccountBalance(accountId: $accountId, code: $code, name: $name, type: $type, parentId: $parentId, debit: $debit, credit: $credit, balance: $balance)';
}


}

/// @nodoc
abstract mixin class $AccountBalanceCopyWith<$Res>  {
  factory $AccountBalanceCopyWith(AccountBalance value, $Res Function(AccountBalance) _then) = _$AccountBalanceCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'accountId') String accountId, String code, String name, String type,@JsonKey(name: 'parentId') String? parentId, double debit, double credit, double balance
});




}
/// @nodoc
class _$AccountBalanceCopyWithImpl<$Res>
    implements $AccountBalanceCopyWith<$Res> {
  _$AccountBalanceCopyWithImpl(this._self, this._then);

  final AccountBalance _self;
  final $Res Function(AccountBalance) _then;

/// Create a copy of AccountBalance
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? code = null,Object? name = null,Object? type = null,Object? parentId = freezed,Object? debit = null,Object? credit = null,Object? balance = null,}) {
  return _then(_self.copyWith(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as double,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as double,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountBalance].
extension AccountBalancePatterns on AccountBalance {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountBalance value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountBalance() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountBalance value)  $default,){
final _that = this;
switch (_that) {
case _AccountBalance():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountBalance value)?  $default,){
final _that = this;
switch (_that) {
case _AccountBalance() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'accountId')  String accountId,  String code,  String name,  String type, @JsonKey(name: 'parentId')  String? parentId,  double debit,  double credit,  double balance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountBalance() when $default != null:
return $default(_that.accountId,_that.code,_that.name,_that.type,_that.parentId,_that.debit,_that.credit,_that.balance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'accountId')  String accountId,  String code,  String name,  String type, @JsonKey(name: 'parentId')  String? parentId,  double debit,  double credit,  double balance)  $default,) {final _that = this;
switch (_that) {
case _AccountBalance():
return $default(_that.accountId,_that.code,_that.name,_that.type,_that.parentId,_that.debit,_that.credit,_that.balance);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'accountId')  String accountId,  String code,  String name,  String type, @JsonKey(name: 'parentId')  String? parentId,  double debit,  double credit,  double balance)?  $default,) {final _that = this;
switch (_that) {
case _AccountBalance() when $default != null:
return $default(_that.accountId,_that.code,_that.name,_that.type,_that.parentId,_that.debit,_that.credit,_that.balance);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AccountBalance implements AccountBalance {
  const _AccountBalance({@JsonKey(name: 'accountId') required this.accountId, required this.code, required this.name, required this.type, @JsonKey(name: 'parentId') this.parentId, this.debit = 0.0, this.credit = 0.0, this.balance = 0.0});
  factory _AccountBalance.fromJson(Map<String, dynamic> json) => _$AccountBalanceFromJson(json);

@override@JsonKey(name: 'accountId') final  String accountId;
@override final  String code;
@override final  String name;
@override final  String type;
@override@JsonKey(name: 'parentId') final  String? parentId;
@override@JsonKey() final  double debit;
@override@JsonKey() final  double credit;
@override@JsonKey() final  double balance;

/// Create a copy of AccountBalance
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountBalanceCopyWith<_AccountBalance> get copyWith => __$AccountBalanceCopyWithImpl<_AccountBalance>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AccountBalanceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountBalance&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.debit, debit) || other.debit == debit)&&(identical(other.credit, credit) || other.credit == credit)&&(identical(other.balance, balance) || other.balance == balance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,accountId,code,name,type,parentId,debit,credit,balance);

@override
String toString() {
  return 'AccountBalance(accountId: $accountId, code: $code, name: $name, type: $type, parentId: $parentId, debit: $debit, credit: $credit, balance: $balance)';
}


}

/// @nodoc
abstract mixin class _$AccountBalanceCopyWith<$Res> implements $AccountBalanceCopyWith<$Res> {
  factory _$AccountBalanceCopyWith(_AccountBalance value, $Res Function(_AccountBalance) _then) = __$AccountBalanceCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'accountId') String accountId, String code, String name, String type,@JsonKey(name: 'parentId') String? parentId, double debit, double credit, double balance
});




}
/// @nodoc
class __$AccountBalanceCopyWithImpl<$Res>
    implements _$AccountBalanceCopyWith<$Res> {
  __$AccountBalanceCopyWithImpl(this._self, this._then);

  final _AccountBalance _self;
  final $Res Function(_AccountBalance) _then;

/// Create a copy of AccountBalance
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? code = null,Object? name = null,Object? type = null,Object? parentId = freezed,Object? debit = null,Object? credit = null,Object? balance = null,}) {
  return _then(_AccountBalance(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as double,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as double,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on

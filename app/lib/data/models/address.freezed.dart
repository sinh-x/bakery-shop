// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'address.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AddressSuggestion {

 int get id;@JsonKey(name: 'displayAddress') String get displayAddress;@JsonKey(name: 'googleMapsUrl') String? get googleMapsUrl;@JsonKey(name: 'isCustomerAddress') bool get isCustomerAddress;
/// Create a copy of AddressSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressSuggestionCopyWith<AddressSuggestion> get copyWith => _$AddressSuggestionCopyWithImpl<AddressSuggestion>(this as AddressSuggestion, _$identity);

  /// Serializes this AddressSuggestion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressSuggestion&&(identical(other.id, id) || other.id == id)&&(identical(other.displayAddress, displayAddress) || other.displayAddress == displayAddress)&&(identical(other.googleMapsUrl, googleMapsUrl) || other.googleMapsUrl == googleMapsUrl)&&(identical(other.isCustomerAddress, isCustomerAddress) || other.isCustomerAddress == isCustomerAddress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayAddress,googleMapsUrl,isCustomerAddress);

@override
String toString() {
  return 'AddressSuggestion(id: $id, displayAddress: $displayAddress, googleMapsUrl: $googleMapsUrl, isCustomerAddress: $isCustomerAddress)';
}


}

/// @nodoc
abstract mixin class $AddressSuggestionCopyWith<$Res>  {
  factory $AddressSuggestionCopyWith(AddressSuggestion value, $Res Function(AddressSuggestion) _then) = _$AddressSuggestionCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'displayAddress') String displayAddress,@JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,@JsonKey(name: 'isCustomerAddress') bool isCustomerAddress
});




}
/// @nodoc
class _$AddressSuggestionCopyWithImpl<$Res>
    implements $AddressSuggestionCopyWith<$Res> {
  _$AddressSuggestionCopyWithImpl(this._self, this._then);

  final AddressSuggestion _self;
  final $Res Function(AddressSuggestion) _then;

/// Create a copy of AddressSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayAddress = null,Object? googleMapsUrl = freezed,Object? isCustomerAddress = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,displayAddress: null == displayAddress ? _self.displayAddress : displayAddress // ignore: cast_nullable_to_non_nullable
as String,googleMapsUrl: freezed == googleMapsUrl ? _self.googleMapsUrl : googleMapsUrl // ignore: cast_nullable_to_non_nullable
as String?,isCustomerAddress: null == isCustomerAddress ? _self.isCustomerAddress : isCustomerAddress // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AddressSuggestion].
extension AddressSuggestionPatterns on AddressSuggestion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddressSuggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddressSuggestion value)  $default,){
final _that = this;
switch (_that) {
case _AddressSuggestion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddressSuggestion value)?  $default,){
final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'isCustomerAddress')  bool isCustomerAddress)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.isCustomerAddress);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'isCustomerAddress')  bool isCustomerAddress)  $default,) {final _that = this;
switch (_that) {
case _AddressSuggestion():
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.isCustomerAddress);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'isCustomerAddress')  bool isCustomerAddress)?  $default,) {final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.isCustomerAddress);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AddressSuggestion implements AddressSuggestion {
  const _AddressSuggestion({required this.id, @JsonKey(name: 'displayAddress') required this.displayAddress, @JsonKey(name: 'googleMapsUrl') this.googleMapsUrl, @JsonKey(name: 'isCustomerAddress') this.isCustomerAddress = false});
  factory _AddressSuggestion.fromJson(Map<String, dynamic> json) => _$AddressSuggestionFromJson(json);

@override final  int id;
@override@JsonKey(name: 'displayAddress') final  String displayAddress;
@override@JsonKey(name: 'googleMapsUrl') final  String? googleMapsUrl;
@override@JsonKey(name: 'isCustomerAddress') final  bool isCustomerAddress;

/// Create a copy of AddressSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddressSuggestionCopyWith<_AddressSuggestion> get copyWith => __$AddressSuggestionCopyWithImpl<_AddressSuggestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AddressSuggestionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddressSuggestion&&(identical(other.id, id) || other.id == id)&&(identical(other.displayAddress, displayAddress) || other.displayAddress == displayAddress)&&(identical(other.googleMapsUrl, googleMapsUrl) || other.googleMapsUrl == googleMapsUrl)&&(identical(other.isCustomerAddress, isCustomerAddress) || other.isCustomerAddress == isCustomerAddress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayAddress,googleMapsUrl,isCustomerAddress);

@override
String toString() {
  return 'AddressSuggestion(id: $id, displayAddress: $displayAddress, googleMapsUrl: $googleMapsUrl, isCustomerAddress: $isCustomerAddress)';
}


}

/// @nodoc
abstract mixin class _$AddressSuggestionCopyWith<$Res> implements $AddressSuggestionCopyWith<$Res> {
  factory _$AddressSuggestionCopyWith(_AddressSuggestion value, $Res Function(_AddressSuggestion) _then) = __$AddressSuggestionCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'displayAddress') String displayAddress,@JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,@JsonKey(name: 'isCustomerAddress') bool isCustomerAddress
});




}
/// @nodoc
class __$AddressSuggestionCopyWithImpl<$Res>
    implements _$AddressSuggestionCopyWith<$Res> {
  __$AddressSuggestionCopyWithImpl(this._self, this._then);

  final _AddressSuggestion _self;
  final $Res Function(_AddressSuggestion) _then;

/// Create a copy of AddressSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayAddress = null,Object? googleMapsUrl = freezed,Object? isCustomerAddress = null,}) {
  return _then(_AddressSuggestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,displayAddress: null == displayAddress ? _self.displayAddress : displayAddress // ignore: cast_nullable_to_non_nullable
as String,googleMapsUrl: freezed == googleMapsUrl ? _self.googleMapsUrl : googleMapsUrl // ignore: cast_nullable_to_non_nullable
as String?,isCustomerAddress: null == isCustomerAddress ? _self.isCustomerAddress : isCustomerAddress // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$AddressLibraryEntry {

 int get id;@JsonKey(name: 'displayAddress') String get displayAddress;@JsonKey(name: 'googleMapsUrl') String? get googleMapsUrl;@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get createdAt;@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get updatedAt;
/// Create a copy of AddressLibraryEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressLibraryEntryCopyWith<AddressLibraryEntry> get copyWith => _$AddressLibraryEntryCopyWithImpl<AddressLibraryEntry>(this as AddressLibraryEntry, _$identity);

  /// Serializes this AddressLibraryEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressLibraryEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.displayAddress, displayAddress) || other.displayAddress == displayAddress)&&(identical(other.googleMapsUrl, googleMapsUrl) || other.googleMapsUrl == googleMapsUrl)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayAddress,googleMapsUrl,createdAt,updatedAt);

@override
String toString() {
  return 'AddressLibraryEntry(id: $id, displayAddress: $displayAddress, googleMapsUrl: $googleMapsUrl, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $AddressLibraryEntryCopyWith<$Res>  {
  factory $AddressLibraryEntryCopyWith(AddressLibraryEntry value, $Res Function(AddressLibraryEntry) _then) = _$AddressLibraryEntryCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'displayAddress') String displayAddress,@JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$AddressLibraryEntryCopyWithImpl<$Res>
    implements $AddressLibraryEntryCopyWith<$Res> {
  _$AddressLibraryEntryCopyWithImpl(this._self, this._then);

  final AddressLibraryEntry _self;
  final $Res Function(AddressLibraryEntry) _then;

/// Create a copy of AddressLibraryEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayAddress = null,Object? googleMapsUrl = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,displayAddress: null == displayAddress ? _self.displayAddress : displayAddress // ignore: cast_nullable_to_non_nullable
as String,googleMapsUrl: freezed == googleMapsUrl ? _self.googleMapsUrl : googleMapsUrl // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [AddressLibraryEntry].
extension AddressLibraryEntryPatterns on AddressLibraryEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddressLibraryEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddressLibraryEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddressLibraryEntry value)  $default,){
final _that = this;
switch (_that) {
case _AddressLibraryEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddressLibraryEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AddressLibraryEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddressLibraryEntry() when $default != null:
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AddressLibraryEntry():
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'displayAddress')  String displayAddress, @JsonKey(name: 'googleMapsUrl')  String? googleMapsUrl, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AddressLibraryEntry() when $default != null:
return $default(_that.id,_that.displayAddress,_that.googleMapsUrl,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AddressLibraryEntry implements AddressLibraryEntry {
  const _AddressLibraryEntry({required this.id, @JsonKey(name: 'displayAddress') required this.displayAddress, @JsonKey(name: 'googleMapsUrl') this.googleMapsUrl, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.createdAt, @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) this.updatedAt});
  factory _AddressLibraryEntry.fromJson(Map<String, dynamic> json) => _$AddressLibraryEntryFromJson(json);

@override final  int id;
@override@JsonKey(name: 'displayAddress') final  String displayAddress;
@override@JsonKey(name: 'googleMapsUrl') final  String? googleMapsUrl;
@override@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? createdAt;
@override@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? updatedAt;

/// Create a copy of AddressLibraryEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddressLibraryEntryCopyWith<_AddressLibraryEntry> get copyWith => __$AddressLibraryEntryCopyWithImpl<_AddressLibraryEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AddressLibraryEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddressLibraryEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.displayAddress, displayAddress) || other.displayAddress == displayAddress)&&(identical(other.googleMapsUrl, googleMapsUrl) || other.googleMapsUrl == googleMapsUrl)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayAddress,googleMapsUrl,createdAt,updatedAt);

@override
String toString() {
  return 'AddressLibraryEntry(id: $id, displayAddress: $displayAddress, googleMapsUrl: $googleMapsUrl, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$AddressLibraryEntryCopyWith<$Res> implements $AddressLibraryEntryCopyWith<$Res> {
  factory _$AddressLibraryEntryCopyWith(_AddressLibraryEntry value, $Res Function(_AddressLibraryEntry) _then) = __$AddressLibraryEntryCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'displayAddress') String displayAddress,@JsonKey(name: 'googleMapsUrl') String? googleMapsUrl,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$AddressLibraryEntryCopyWithImpl<$Res>
    implements _$AddressLibraryEntryCopyWith<$Res> {
  __$AddressLibraryEntryCopyWithImpl(this._self, this._then);

  final _AddressLibraryEntry _self;
  final $Res Function(_AddressLibraryEntry) _then;

/// Create a copy of AddressLibraryEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayAddress = null,Object? googleMapsUrl = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_AddressLibraryEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,displayAddress: null == displayAddress ? _self.displayAddress : displayAddress // ignore: cast_nullable_to_non_nullable
as String,googleMapsUrl: freezed == googleMapsUrl ? _self.googleMapsUrl : googleMapsUrl // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on

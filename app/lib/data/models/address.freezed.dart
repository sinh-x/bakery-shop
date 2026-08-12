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
mixin _$AddressAutocompleteResponse {

@JsonKey(name: 'pastOrders') List<AddressSuggestion> get pastOrders;@JsonKey(name: 'library') List<AddressSuggestion> get library;
/// Create a copy of AddressAutocompleteResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressAutocompleteResponseCopyWith<AddressAutocompleteResponse> get copyWith => _$AddressAutocompleteResponseCopyWithImpl<AddressAutocompleteResponse>(this as AddressAutocompleteResponse, _$identity);

  /// Serializes this AddressAutocompleteResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressAutocompleteResponse&&const DeepCollectionEquality().equals(other.pastOrders, pastOrders)&&const DeepCollectionEquality().equals(other.library, library));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(pastOrders),const DeepCollectionEquality().hash(library));

@override
String toString() {
  return 'AddressAutocompleteResponse(pastOrders: $pastOrders, library: $library)';
}


}

/// @nodoc
abstract mixin class $AddressAutocompleteResponseCopyWith<$Res>  {
  factory $AddressAutocompleteResponseCopyWith(AddressAutocompleteResponse value, $Res Function(AddressAutocompleteResponse) _then) = _$AddressAutocompleteResponseCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'pastOrders') List<AddressSuggestion> pastOrders,@JsonKey(name: 'library') List<AddressSuggestion> library
});




}
/// @nodoc
class _$AddressAutocompleteResponseCopyWithImpl<$Res>
    implements $AddressAutocompleteResponseCopyWith<$Res> {
  _$AddressAutocompleteResponseCopyWithImpl(this._self, this._then);

  final AddressAutocompleteResponse _self;
  final $Res Function(AddressAutocompleteResponse) _then;

/// Create a copy of AddressAutocompleteResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pastOrders = null,Object? library = null,}) {
  return _then(_self.copyWith(
pastOrders: null == pastOrders ? _self.pastOrders : pastOrders // ignore: cast_nullable_to_non_nullable
as List<AddressSuggestion>,library: null == library ? _self.library : library // ignore: cast_nullable_to_non_nullable
as List<AddressSuggestion>,
  ));
}

}


/// Adds pattern-matching-related methods to [AddressAutocompleteResponse].
extension AddressAutocompleteResponsePatterns on AddressAutocompleteResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddressAutocompleteResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddressAutocompleteResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddressAutocompleteResponse value)  $default,){
final _that = this;
switch (_that) {
case _AddressAutocompleteResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddressAutocompleteResponse value)?  $default,){
final _that = this;
switch (_that) {
case _AddressAutocompleteResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'pastOrders')  List<AddressSuggestion> pastOrders, @JsonKey(name: 'library')  List<AddressSuggestion> library)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddressAutocompleteResponse() when $default != null:
return $default(_that.pastOrders,_that.library);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'pastOrders')  List<AddressSuggestion> pastOrders, @JsonKey(name: 'library')  List<AddressSuggestion> library)  $default,) {final _that = this;
switch (_that) {
case _AddressAutocompleteResponse():
return $default(_that.pastOrders,_that.library);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'pastOrders')  List<AddressSuggestion> pastOrders, @JsonKey(name: 'library')  List<AddressSuggestion> library)?  $default,) {final _that = this;
switch (_that) {
case _AddressAutocompleteResponse() when $default != null:
return $default(_that.pastOrders,_that.library);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AddressAutocompleteResponse implements AddressAutocompleteResponse {
  const _AddressAutocompleteResponse({@JsonKey(name: 'pastOrders') final  List<AddressSuggestion> pastOrders = const <AddressSuggestion>[], @JsonKey(name: 'library') final  List<AddressSuggestion> library = const <AddressSuggestion>[]}): _pastOrders = pastOrders,_library = library;
  factory _AddressAutocompleteResponse.fromJson(Map<String, dynamic> json) => _$AddressAutocompleteResponseFromJson(json);

 final  List<AddressSuggestion> _pastOrders;
@override@JsonKey(name: 'pastOrders') List<AddressSuggestion> get pastOrders {
  if (_pastOrders is EqualUnmodifiableListView) return _pastOrders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pastOrders);
}

 final  List<AddressSuggestion> _library;
@override@JsonKey(name: 'library') List<AddressSuggestion> get library {
  if (_library is EqualUnmodifiableListView) return _library;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_library);
}


/// Create a copy of AddressAutocompleteResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddressAutocompleteResponseCopyWith<_AddressAutocompleteResponse> get copyWith => __$AddressAutocompleteResponseCopyWithImpl<_AddressAutocompleteResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AddressAutocompleteResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddressAutocompleteResponse&&const DeepCollectionEquality().equals(other._pastOrders, _pastOrders)&&const DeepCollectionEquality().equals(other._library, _library));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_pastOrders),const DeepCollectionEquality().hash(_library));

@override
String toString() {
  return 'AddressAutocompleteResponse(pastOrders: $pastOrders, library: $library)';
}


}

/// @nodoc
abstract mixin class _$AddressAutocompleteResponseCopyWith<$Res> implements $AddressAutocompleteResponseCopyWith<$Res> {
  factory _$AddressAutocompleteResponseCopyWith(_AddressAutocompleteResponse value, $Res Function(_AddressAutocompleteResponse) _then) = __$AddressAutocompleteResponseCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'pastOrders') List<AddressSuggestion> pastOrders,@JsonKey(name: 'library') List<AddressSuggestion> library
});




}
/// @nodoc
class __$AddressAutocompleteResponseCopyWithImpl<$Res>
    implements _$AddressAutocompleteResponseCopyWith<$Res> {
  __$AddressAutocompleteResponseCopyWithImpl(this._self, this._then);

  final _AddressAutocompleteResponse _self;
  final $Res Function(_AddressAutocompleteResponse) _then;

/// Create a copy of AddressAutocompleteResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pastOrders = null,Object? library = null,}) {
  return _then(_AddressAutocompleteResponse(
pastOrders: null == pastOrders ? _self._pastOrders : pastOrders // ignore: cast_nullable_to_non_nullable
as List<AddressSuggestion>,library: null == library ? _self._library : library // ignore: cast_nullable_to_non_nullable
as List<AddressSuggestion>,
  ));
}


}


/// @nodoc
mixin _$MissingLinkItem {

@JsonKey(name: 'deliveryAddress') String get deliveryAddress;@JsonKey(name: 'orderCount') int get orderCount;
/// Create a copy of MissingLinkItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MissingLinkItemCopyWith<MissingLinkItem> get copyWith => _$MissingLinkItemCopyWithImpl<MissingLinkItem>(this as MissingLinkItem, _$identity);

  /// Serializes this MissingLinkItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MissingLinkItem&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.orderCount, orderCount) || other.orderCount == orderCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,deliveryAddress,orderCount);

@override
String toString() {
  return 'MissingLinkItem(deliveryAddress: $deliveryAddress, orderCount: $orderCount)';
}


}

/// @nodoc
abstract mixin class $MissingLinkItemCopyWith<$Res>  {
  factory $MissingLinkItemCopyWith(MissingLinkItem value, $Res Function(MissingLinkItem) _then) = _$MissingLinkItemCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'deliveryAddress') String deliveryAddress,@JsonKey(name: 'orderCount') int orderCount
});




}
/// @nodoc
class _$MissingLinkItemCopyWithImpl<$Res>
    implements $MissingLinkItemCopyWith<$Res> {
  _$MissingLinkItemCopyWithImpl(this._self, this._then);

  final MissingLinkItem _self;
  final $Res Function(MissingLinkItem) _then;

/// Create a copy of MissingLinkItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deliveryAddress = null,Object? orderCount = null,}) {
  return _then(_self.copyWith(
deliveryAddress: null == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String,orderCount: null == orderCount ? _self.orderCount : orderCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [MissingLinkItem].
extension MissingLinkItemPatterns on MissingLinkItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MissingLinkItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MissingLinkItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MissingLinkItem value)  $default,){
final _that = this;
switch (_that) {
case _MissingLinkItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MissingLinkItem value)?  $default,){
final _that = this;
switch (_that) {
case _MissingLinkItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'deliveryAddress')  String deliveryAddress, @JsonKey(name: 'orderCount')  int orderCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MissingLinkItem() when $default != null:
return $default(_that.deliveryAddress,_that.orderCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'deliveryAddress')  String deliveryAddress, @JsonKey(name: 'orderCount')  int orderCount)  $default,) {final _that = this;
switch (_that) {
case _MissingLinkItem():
return $default(_that.deliveryAddress,_that.orderCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'deliveryAddress')  String deliveryAddress, @JsonKey(name: 'orderCount')  int orderCount)?  $default,) {final _that = this;
switch (_that) {
case _MissingLinkItem() when $default != null:
return $default(_that.deliveryAddress,_that.orderCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MissingLinkItem implements MissingLinkItem {
  const _MissingLinkItem({@JsonKey(name: 'deliveryAddress') required this.deliveryAddress, @JsonKey(name: 'orderCount') required this.orderCount});
  factory _MissingLinkItem.fromJson(Map<String, dynamic> json) => _$MissingLinkItemFromJson(json);

@override@JsonKey(name: 'deliveryAddress') final  String deliveryAddress;
@override@JsonKey(name: 'orderCount') final  int orderCount;

/// Create a copy of MissingLinkItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MissingLinkItemCopyWith<_MissingLinkItem> get copyWith => __$MissingLinkItemCopyWithImpl<_MissingLinkItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MissingLinkItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MissingLinkItem&&(identical(other.deliveryAddress, deliveryAddress) || other.deliveryAddress == deliveryAddress)&&(identical(other.orderCount, orderCount) || other.orderCount == orderCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,deliveryAddress,orderCount);

@override
String toString() {
  return 'MissingLinkItem(deliveryAddress: $deliveryAddress, orderCount: $orderCount)';
}


}

/// @nodoc
abstract mixin class _$MissingLinkItemCopyWith<$Res> implements $MissingLinkItemCopyWith<$Res> {
  factory _$MissingLinkItemCopyWith(_MissingLinkItem value, $Res Function(_MissingLinkItem) _then) = __$MissingLinkItemCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'deliveryAddress') String deliveryAddress,@JsonKey(name: 'orderCount') int orderCount
});




}
/// @nodoc
class __$MissingLinkItemCopyWithImpl<$Res>
    implements _$MissingLinkItemCopyWith<$Res> {
  __$MissingLinkItemCopyWithImpl(this._self, this._then);

  final _MissingLinkItem _self;
  final $Res Function(_MissingLinkItem) _then;

/// Create a copy of MissingLinkItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deliveryAddress = null,Object? orderCount = null,}) {
  return _then(_MissingLinkItem(
deliveryAddress: null == deliveryAddress ? _self.deliveryAddress : deliveryAddress // ignore: cast_nullable_to_non_nullable
as String,orderCount: null == orderCount ? _self.orderCount : orderCount // ignore: cast_nullable_to_non_nullable
as int,
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

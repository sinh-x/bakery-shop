// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'enum_attribute.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EnumOption {

 int get id;@JsonKey(name: 'value_vi') String get valueVi;@JsonKey(name: 'sort_order') int get sortOrder; int get active;@JsonKey(name: 'is_default') bool get isDefault;
/// Create a copy of EnumOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnumOptionCopyWith<EnumOption> get copyWith => _$EnumOptionCopyWithImpl<EnumOption>(this as EnumOption, _$identity);

  /// Serializes this EnumOption to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnumOption&&(identical(other.id, id) || other.id == id)&&(identical(other.valueVi, valueVi) || other.valueVi == valueVi)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,valueVi,sortOrder,active,isDefault);

@override
String toString() {
  return 'EnumOption(id: $id, valueVi: $valueVi, sortOrder: $sortOrder, active: $active, isDefault: $isDefault)';
}


}

/// @nodoc
abstract mixin class $EnumOptionCopyWith<$Res>  {
  factory $EnumOptionCopyWith(EnumOption value, $Res Function(EnumOption) _then) = _$EnumOptionCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'value_vi') String valueVi,@JsonKey(name: 'sort_order') int sortOrder, int active,@JsonKey(name: 'is_default') bool isDefault
});




}
/// @nodoc
class _$EnumOptionCopyWithImpl<$Res>
    implements $EnumOptionCopyWith<$Res> {
  _$EnumOptionCopyWithImpl(this._self, this._then);

  final EnumOption _self;
  final $Res Function(EnumOption) _then;

/// Create a copy of EnumOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? valueVi = null,Object? sortOrder = null,Object? active = null,Object? isDefault = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,valueVi: null == valueVi ? _self.valueVi : valueVi // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as int,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [EnumOption].
extension EnumOptionPatterns on EnumOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EnumOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EnumOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EnumOption value)  $default,){
final _that = this;
switch (_that) {
case _EnumOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EnumOption value)?  $default,){
final _that = this;
switch (_that) {
case _EnumOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'value_vi')  String valueVi, @JsonKey(name: 'sort_order')  int sortOrder,  int active, @JsonKey(name: 'is_default')  bool isDefault)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnumOption() when $default != null:
return $default(_that.id,_that.valueVi,_that.sortOrder,_that.active,_that.isDefault);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'value_vi')  String valueVi, @JsonKey(name: 'sort_order')  int sortOrder,  int active, @JsonKey(name: 'is_default')  bool isDefault)  $default,) {final _that = this;
switch (_that) {
case _EnumOption():
return $default(_that.id,_that.valueVi,_that.sortOrder,_that.active,_that.isDefault);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'value_vi')  String valueVi, @JsonKey(name: 'sort_order')  int sortOrder,  int active, @JsonKey(name: 'is_default')  bool isDefault)?  $default,) {final _that = this;
switch (_that) {
case _EnumOption() when $default != null:
return $default(_that.id,_that.valueVi,_that.sortOrder,_that.active,_that.isDefault);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnumOption implements EnumOption {
  const _EnumOption({required this.id, @JsonKey(name: 'value_vi') required this.valueVi, @JsonKey(name: 'sort_order') this.sortOrder = 0, this.active = 1, @JsonKey(name: 'is_default') this.isDefault = false});
  factory _EnumOption.fromJson(Map<String, dynamic> json) => _$EnumOptionFromJson(json);

@override final  int id;
@override@JsonKey(name: 'value_vi') final  String valueVi;
@override@JsonKey(name: 'sort_order') final  int sortOrder;
@override@JsonKey() final  int active;
@override@JsonKey(name: 'is_default') final  bool isDefault;

/// Create a copy of EnumOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EnumOptionCopyWith<_EnumOption> get copyWith => __$EnumOptionCopyWithImpl<_EnumOption>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EnumOptionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnumOption&&(identical(other.id, id) || other.id == id)&&(identical(other.valueVi, valueVi) || other.valueVi == valueVi)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,valueVi,sortOrder,active,isDefault);

@override
String toString() {
  return 'EnumOption(id: $id, valueVi: $valueVi, sortOrder: $sortOrder, active: $active, isDefault: $isDefault)';
}


}

/// @nodoc
abstract mixin class _$EnumOptionCopyWith<$Res> implements $EnumOptionCopyWith<$Res> {
  factory _$EnumOptionCopyWith(_EnumOption value, $Res Function(_EnumOption) _then) = __$EnumOptionCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'value_vi') String valueVi,@JsonKey(name: 'sort_order') int sortOrder, int active,@JsonKey(name: 'is_default') bool isDefault
});




}
/// @nodoc
class __$EnumOptionCopyWithImpl<$Res>
    implements _$EnumOptionCopyWith<$Res> {
  __$EnumOptionCopyWithImpl(this._self, this._then);

  final _EnumOption _self;
  final $Res Function(_EnumOption) _then;

/// Create a copy of EnumOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? valueVi = null,Object? sortOrder = null,Object? active = null,Object? isDefault = null,}) {
  return _then(_EnumOption(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,valueVi: null == valueVi ? _self.valueVi : valueVi // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as int,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$EnumAttribute {

@JsonKey(name: 'attribute_type') String get attributeType;@JsonKey(name: 'label_vi') String get labelVi;@JsonKey(name: 'default_option_id') int? get defaultOptionId; List<EnumOption> get options;
/// Create a copy of EnumAttribute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnumAttributeCopyWith<EnumAttribute> get copyWith => _$EnumAttributeCopyWithImpl<EnumAttribute>(this as EnumAttribute, _$identity);

  /// Serializes this EnumAttribute to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnumAttribute&&(identical(other.attributeType, attributeType) || other.attributeType == attributeType)&&(identical(other.labelVi, labelVi) || other.labelVi == labelVi)&&(identical(other.defaultOptionId, defaultOptionId) || other.defaultOptionId == defaultOptionId)&&const DeepCollectionEquality().equals(other.options, options));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,attributeType,labelVi,defaultOptionId,const DeepCollectionEquality().hash(options));

@override
String toString() {
  return 'EnumAttribute(attributeType: $attributeType, labelVi: $labelVi, defaultOptionId: $defaultOptionId, options: $options)';
}


}

/// @nodoc
abstract mixin class $EnumAttributeCopyWith<$Res>  {
  factory $EnumAttributeCopyWith(EnumAttribute value, $Res Function(EnumAttribute) _then) = _$EnumAttributeCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'attribute_type') String attributeType,@JsonKey(name: 'label_vi') String labelVi,@JsonKey(name: 'default_option_id') int? defaultOptionId, List<EnumOption> options
});




}
/// @nodoc
class _$EnumAttributeCopyWithImpl<$Res>
    implements $EnumAttributeCopyWith<$Res> {
  _$EnumAttributeCopyWithImpl(this._self, this._then);

  final EnumAttribute _self;
  final $Res Function(EnumAttribute) _then;

/// Create a copy of EnumAttribute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? attributeType = null,Object? labelVi = null,Object? defaultOptionId = freezed,Object? options = null,}) {
  return _then(_self.copyWith(
attributeType: null == attributeType ? _self.attributeType : attributeType // ignore: cast_nullable_to_non_nullable
as String,labelVi: null == labelVi ? _self.labelVi : labelVi // ignore: cast_nullable_to_non_nullable
as String,defaultOptionId: freezed == defaultOptionId ? _self.defaultOptionId : defaultOptionId // ignore: cast_nullable_to_non_nullable
as int?,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<EnumOption>,
  ));
}

}


/// Adds pattern-matching-related methods to [EnumAttribute].
extension EnumAttributePatterns on EnumAttribute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EnumAttribute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EnumAttribute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EnumAttribute value)  $default,){
final _that = this;
switch (_that) {
case _EnumAttribute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EnumAttribute value)?  $default,){
final _that = this;
switch (_that) {
case _EnumAttribute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'attribute_type')  String attributeType, @JsonKey(name: 'label_vi')  String labelVi, @JsonKey(name: 'default_option_id')  int? defaultOptionId,  List<EnumOption> options)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnumAttribute() when $default != null:
return $default(_that.attributeType,_that.labelVi,_that.defaultOptionId,_that.options);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'attribute_type')  String attributeType, @JsonKey(name: 'label_vi')  String labelVi, @JsonKey(name: 'default_option_id')  int? defaultOptionId,  List<EnumOption> options)  $default,) {final _that = this;
switch (_that) {
case _EnumAttribute():
return $default(_that.attributeType,_that.labelVi,_that.defaultOptionId,_that.options);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'attribute_type')  String attributeType, @JsonKey(name: 'label_vi')  String labelVi, @JsonKey(name: 'default_option_id')  int? defaultOptionId,  List<EnumOption> options)?  $default,) {final _that = this;
switch (_that) {
case _EnumAttribute() when $default != null:
return $default(_that.attributeType,_that.labelVi,_that.defaultOptionId,_that.options);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnumAttribute implements EnumAttribute {
  const _EnumAttribute({@JsonKey(name: 'attribute_type') required this.attributeType, @JsonKey(name: 'label_vi') required this.labelVi, @JsonKey(name: 'default_option_id') this.defaultOptionId, final  List<EnumOption> options = const []}): _options = options;
  factory _EnumAttribute.fromJson(Map<String, dynamic> json) => _$EnumAttributeFromJson(json);

@override@JsonKey(name: 'attribute_type') final  String attributeType;
@override@JsonKey(name: 'label_vi') final  String labelVi;
@override@JsonKey(name: 'default_option_id') final  int? defaultOptionId;
 final  List<EnumOption> _options;
@override@JsonKey() List<EnumOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}


/// Create a copy of EnumAttribute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EnumAttributeCopyWith<_EnumAttribute> get copyWith => __$EnumAttributeCopyWithImpl<_EnumAttribute>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EnumAttributeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnumAttribute&&(identical(other.attributeType, attributeType) || other.attributeType == attributeType)&&(identical(other.labelVi, labelVi) || other.labelVi == labelVi)&&(identical(other.defaultOptionId, defaultOptionId) || other.defaultOptionId == defaultOptionId)&&const DeepCollectionEquality().equals(other._options, _options));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,attributeType,labelVi,defaultOptionId,const DeepCollectionEquality().hash(_options));

@override
String toString() {
  return 'EnumAttribute(attributeType: $attributeType, labelVi: $labelVi, defaultOptionId: $defaultOptionId, options: $options)';
}


}

/// @nodoc
abstract mixin class _$EnumAttributeCopyWith<$Res> implements $EnumAttributeCopyWith<$Res> {
  factory _$EnumAttributeCopyWith(_EnumAttribute value, $Res Function(_EnumAttribute) _then) = __$EnumAttributeCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'attribute_type') String attributeType,@JsonKey(name: 'label_vi') String labelVi,@JsonKey(name: 'default_option_id') int? defaultOptionId, List<EnumOption> options
});




}
/// @nodoc
class __$EnumAttributeCopyWithImpl<$Res>
    implements _$EnumAttributeCopyWith<$Res> {
  __$EnumAttributeCopyWithImpl(this._self, this._then);

  final _EnumAttribute _self;
  final $Res Function(_EnumAttribute) _then;

/// Create a copy of EnumAttribute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? attributeType = null,Object? labelVi = null,Object? defaultOptionId = freezed,Object? options = null,}) {
  return _then(_EnumAttribute(
attributeType: null == attributeType ? _self.attributeType : attributeType // ignore: cast_nullable_to_non_nullable
as String,labelVi: null == labelVi ? _self.labelVi : labelVi // ignore: cast_nullable_to_non_nullable
as String,defaultOptionId: freezed == defaultOptionId ? _self.defaultOptionId : defaultOptionId // ignore: cast_nullable_to_non_nullable
as int?,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<EnumOption>,
  ));
}


}

// dart format on

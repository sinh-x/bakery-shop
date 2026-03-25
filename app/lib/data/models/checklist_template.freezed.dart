// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'checklist_template.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChecklistTemplate {

 int get id; String get name; String get period;@JsonKey(name: 'sort_order') int get sortOrder; bool get active;@JsonKey(name: 'created_at') String? get createdAt;
/// Create a copy of ChecklistTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistTemplateCopyWith<ChecklistTemplate> get copyWith => _$ChecklistTemplateCopyWithImpl<ChecklistTemplate>(this as ChecklistTemplate, _$identity);

  /// Serializes this ChecklistTemplate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.period, period) || other.period == period)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,period,sortOrder,active,createdAt);

@override
String toString() {
  return 'ChecklistTemplate(id: $id, name: $name, period: $period, sortOrder: $sortOrder, active: $active, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $ChecklistTemplateCopyWith<$Res>  {
  factory $ChecklistTemplateCopyWith(ChecklistTemplate value, $Res Function(ChecklistTemplate) _then) = _$ChecklistTemplateCopyWithImpl;
@useResult
$Res call({
 int id, String name, String period,@JsonKey(name: 'sort_order') int sortOrder, bool active,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class _$ChecklistTemplateCopyWithImpl<$Res>
    implements $ChecklistTemplateCopyWith<$Res> {
  _$ChecklistTemplateCopyWithImpl(this._self, this._then);

  final ChecklistTemplate _self;
  final $Res Function(ChecklistTemplate) _then;

/// Create a copy of ChecklistTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? period = null,Object? sortOrder = null,Object? active = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,period: null == period ? _self.period : period // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistTemplate].
extension ChecklistTemplatePatterns on ChecklistTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistTemplate value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  String period, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistTemplate() when $default != null:
return $default(_that.id,_that.name,_that.period,_that.sortOrder,_that.active,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  String period, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ChecklistTemplate():
return $default(_that.id,_that.name,_that.period,_that.sortOrder,_that.active,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  String period, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistTemplate() when $default != null:
return $default(_that.id,_that.name,_that.period,_that.sortOrder,_that.active,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistTemplate implements ChecklistTemplate {
  const _ChecklistTemplate({required this.id, required this.name, this.period = 'opening', @JsonKey(name: 'sort_order') this.sortOrder = 0, this.active = true, @JsonKey(name: 'created_at') this.createdAt});
  factory _ChecklistTemplate.fromJson(Map<String, dynamic> json) => _$ChecklistTemplateFromJson(json);

@override final  int id;
@override final  String name;
@override@JsonKey() final  String period;
@override@JsonKey(name: 'sort_order') final  int sortOrder;
@override@JsonKey() final  bool active;
@override@JsonKey(name: 'created_at') final  String? createdAt;

/// Create a copy of ChecklistTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistTemplateCopyWith<_ChecklistTemplate> get copyWith => __$ChecklistTemplateCopyWithImpl<_ChecklistTemplate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistTemplateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.period, period) || other.period == period)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,period,sortOrder,active,createdAt);

@override
String toString() {
  return 'ChecklistTemplate(id: $id, name: $name, period: $period, sortOrder: $sortOrder, active: $active, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ChecklistTemplateCopyWith<$Res> implements $ChecklistTemplateCopyWith<$Res> {
  factory _$ChecklistTemplateCopyWith(_ChecklistTemplate value, $Res Function(_ChecklistTemplate) _then) = __$ChecklistTemplateCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, String period,@JsonKey(name: 'sort_order') int sortOrder, bool active,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class __$ChecklistTemplateCopyWithImpl<$Res>
    implements _$ChecklistTemplateCopyWith<$Res> {
  __$ChecklistTemplateCopyWithImpl(this._self, this._then);

  final _ChecklistTemplate _self;
  final $Res Function(_ChecklistTemplate) _then;

/// Create a copy of ChecklistTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? period = null,Object? sortOrder = null,Object? active = null,Object? createdAt = freezed,}) {
  return _then(_ChecklistTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,period: null == period ? _self.period : period // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

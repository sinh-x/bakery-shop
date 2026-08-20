// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message_template.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MessageTemplate {

 int get id; String get scenario; String get name; String get body;@JsonKey(name: 'is_system') bool get isSystem;@JsonKey(name: 'created_by_staff_id') int? get createdByStaffId;@JsonKey(name: 'sort_order') int get sortOrder; bool get active;@JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get createdAt;@JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? get updatedAt;
/// Create a copy of MessageTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageTemplateCopyWith<MessageTemplate> get copyWith => _$MessageTemplateCopyWithImpl<MessageTemplate>(this as MessageTemplate, _$identity);

  /// Serializes this MessageTemplate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.scenario, scenario) || other.scenario == scenario)&&(identical(other.name, name) || other.name == name)&&(identical(other.body, body) || other.body == body)&&(identical(other.isSystem, isSystem) || other.isSystem == isSystem)&&(identical(other.createdByStaffId, createdByStaffId) || other.createdByStaffId == createdByStaffId)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,scenario,name,body,isSystem,createdByStaffId,sortOrder,active,createdAt,updatedAt);

@override
String toString() {
  return 'MessageTemplate(id: $id, scenario: $scenario, name: $name, body: $body, isSystem: $isSystem, createdByStaffId: $createdByStaffId, sortOrder: $sortOrder, active: $active, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $MessageTemplateCopyWith<$Res>  {
  factory $MessageTemplateCopyWith(MessageTemplate value, $Res Function(MessageTemplate) _then) = _$MessageTemplateCopyWithImpl;
@useResult
$Res call({
 int id, String scenario, String name, String body,@JsonKey(name: 'is_system') bool isSystem,@JsonKey(name: 'created_by_staff_id') int? createdByStaffId,@JsonKey(name: 'sort_order') int sortOrder, bool active,@JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$MessageTemplateCopyWithImpl<$Res>
    implements $MessageTemplateCopyWith<$Res> {
  _$MessageTemplateCopyWithImpl(this._self, this._then);

  final MessageTemplate _self;
  final $Res Function(MessageTemplate) _then;

/// Create a copy of MessageTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? scenario = null,Object? name = null,Object? body = null,Object? isSystem = null,Object? createdByStaffId = freezed,Object? sortOrder = null,Object? active = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,scenario: null == scenario ? _self.scenario : scenario // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,isSystem: null == isSystem ? _self.isSystem : isSystem // ignore: cast_nullable_to_non_nullable
as bool,createdByStaffId: freezed == createdByStaffId ? _self.createdByStaffId : createdByStaffId // ignore: cast_nullable_to_non_nullable
as int?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [MessageTemplate].
extension MessageTemplatePatterns on MessageTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MessageTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MessageTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MessageTemplate value)  $default,){
final _that = this;
switch (_that) {
case _MessageTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MessageTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _MessageTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String scenario,  String name,  String body, @JsonKey(name: 'is_system')  bool isSystem, @JsonKey(name: 'created_by_staff_id')  int? createdByStaffId, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MessageTemplate() when $default != null:
return $default(_that.id,_that.scenario,_that.name,_that.body,_that.isSystem,_that.createdByStaffId,_that.sortOrder,_that.active,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String scenario,  String name,  String body, @JsonKey(name: 'is_system')  bool isSystem, @JsonKey(name: 'created_by_staff_id')  int? createdByStaffId, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _MessageTemplate():
return $default(_that.id,_that.scenario,_that.name,_that.body,_that.isSystem,_that.createdByStaffId,_that.sortOrder,_that.active,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String scenario,  String name,  String body, @JsonKey(name: 'is_system')  bool isSystem, @JsonKey(name: 'created_by_staff_id')  int? createdByStaffId, @JsonKey(name: 'sort_order')  int sortOrder,  bool active, @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? createdAt, @JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _MessageTemplate() when $default != null:
return $default(_that.id,_that.scenario,_that.name,_that.body,_that.isSystem,_that.createdByStaffId,_that.sortOrder,_that.active,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MessageTemplate implements MessageTemplate {
  const _MessageTemplate({required this.id, required this.scenario, required this.name, this.body = '', @JsonKey(name: 'is_system') this.isSystem = false, @JsonKey(name: 'created_by_staff_id') this.createdByStaffId, @JsonKey(name: 'sort_order') this.sortOrder = 0, this.active = true, @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson) this.createdAt, @JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson) this.updatedAt});
  factory _MessageTemplate.fromJson(Map<String, dynamic> json) => _$MessageTemplateFromJson(json);

@override final  int id;
@override final  String scenario;
@override final  String name;
@override@JsonKey() final  String body;
@override@JsonKey(name: 'is_system') final  bool isSystem;
@override@JsonKey(name: 'created_by_staff_id') final  int? createdByStaffId;
@override@JsonKey(name: 'sort_order') final  int sortOrder;
@override@JsonKey() final  bool active;
@override@JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? createdAt;
@override@JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson) final  DateTime? updatedAt;

/// Create a copy of MessageTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageTemplateCopyWith<_MessageTemplate> get copyWith => __$MessageTemplateCopyWithImpl<_MessageTemplate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MessageTemplateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MessageTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.scenario, scenario) || other.scenario == scenario)&&(identical(other.name, name) || other.name == name)&&(identical(other.body, body) || other.body == body)&&(identical(other.isSystem, isSystem) || other.isSystem == isSystem)&&(identical(other.createdByStaffId, createdByStaffId) || other.createdByStaffId == createdByStaffId)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,scenario,name,body,isSystem,createdByStaffId,sortOrder,active,createdAt,updatedAt);

@override
String toString() {
  return 'MessageTemplate(id: $id, scenario: $scenario, name: $name, body: $body, isSystem: $isSystem, createdByStaffId: $createdByStaffId, sortOrder: $sortOrder, active: $active, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$MessageTemplateCopyWith<$Res> implements $MessageTemplateCopyWith<$Res> {
  factory _$MessageTemplateCopyWith(_MessageTemplate value, $Res Function(_MessageTemplate) _then) = __$MessageTemplateCopyWithImpl;
@override @useResult
$Res call({
 int id, String scenario, String name, String body,@JsonKey(name: 'is_system') bool isSystem,@JsonKey(name: 'created_by_staff_id') int? createdByStaffId,@JsonKey(name: 'sort_order') int sortOrder, bool active,@JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? createdAt,@JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$MessageTemplateCopyWithImpl<$Res>
    implements _$MessageTemplateCopyWith<$Res> {
  __$MessageTemplateCopyWithImpl(this._self, this._then);

  final _MessageTemplate _self;
  final $Res Function(_MessageTemplate) _then;

/// Create a copy of MessageTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? scenario = null,Object? name = null,Object? body = null,Object? isSystem = null,Object? createdByStaffId = freezed,Object? sortOrder = null,Object? active = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_MessageTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,scenario: null == scenario ? _self.scenario : scenario // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,isSystem: null == isSystem ? _self.isSystem : isSystem // ignore: cast_nullable_to_non_nullable
as bool,createdByStaffId: freezed == createdByStaffId ? _self.createdByStaffId : createdByStaffId // ignore: cast_nullable_to_non_nullable
as int?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on

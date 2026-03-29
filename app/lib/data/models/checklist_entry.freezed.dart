// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'checklist_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChecklistEntry {

 int get id;@JsonKey(name: 'template_id') int get templateId;@JsonKey(name: 'checklist_date') String get checklistDate; bool get completed;@JsonKey(name: 'completed_by') String get completedBy;@JsonKey(name: 'completed_at') String? get completedAt;@JsonKey(name: 'created_at') String? get createdAt;@JsonKey(name: 'template_name') String? get templateName;@JsonKey(name: 'template_period') String? get templatePeriod;@JsonKey(name: 'template_sort_order') int? get templateSortOrder;
/// Create a copy of ChecklistEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistEntryCopyWith<ChecklistEntry> get copyWith => _$ChecklistEntryCopyWithImpl<ChecklistEntry>(this as ChecklistEntry, _$identity);

  /// Serializes this ChecklistEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.templateId, templateId) || other.templateId == templateId)&&(identical(other.checklistDate, checklistDate) || other.checklistDate == checklistDate)&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.completedBy, completedBy) || other.completedBy == completedBy)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.templateName, templateName) || other.templateName == templateName)&&(identical(other.templatePeriod, templatePeriod) || other.templatePeriod == templatePeriod)&&(identical(other.templateSortOrder, templateSortOrder) || other.templateSortOrder == templateSortOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,templateId,checklistDate,completed,completedBy,completedAt,createdAt,templateName,templatePeriod,templateSortOrder);

@override
String toString() {
  return 'ChecklistEntry(id: $id, templateId: $templateId, checklistDate: $checklistDate, completed: $completed, completedBy: $completedBy, completedAt: $completedAt, createdAt: $createdAt, templateName: $templateName, templatePeriod: $templatePeriod, templateSortOrder: $templateSortOrder)';
}


}

/// @nodoc
abstract mixin class $ChecklistEntryCopyWith<$Res>  {
  factory $ChecklistEntryCopyWith(ChecklistEntry value, $Res Function(ChecklistEntry) _then) = _$ChecklistEntryCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'template_id') int templateId,@JsonKey(name: 'checklist_date') String checklistDate, bool completed,@JsonKey(name: 'completed_by') String completedBy,@JsonKey(name: 'completed_at') String? completedAt,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'template_name') String? templateName,@JsonKey(name: 'template_period') String? templatePeriod,@JsonKey(name: 'template_sort_order') int? templateSortOrder
});




}
/// @nodoc
class _$ChecklistEntryCopyWithImpl<$Res>
    implements $ChecklistEntryCopyWith<$Res> {
  _$ChecklistEntryCopyWithImpl(this._self, this._then);

  final ChecklistEntry _self;
  final $Res Function(ChecklistEntry) _then;

/// Create a copy of ChecklistEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? templateId = null,Object? checklistDate = null,Object? completed = null,Object? completedBy = null,Object? completedAt = freezed,Object? createdAt = freezed,Object? templateName = freezed,Object? templatePeriod = freezed,Object? templateSortOrder = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,templateId: null == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as int,checklistDate: null == checklistDate ? _self.checklistDate : checklistDate // ignore: cast_nullable_to_non_nullable
as String,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,completedBy: null == completedBy ? _self.completedBy : completedBy // ignore: cast_nullable_to_non_nullable
as String,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,templateName: freezed == templateName ? _self.templateName : templateName // ignore: cast_nullable_to_non_nullable
as String?,templatePeriod: freezed == templatePeriod ? _self.templatePeriod : templatePeriod // ignore: cast_nullable_to_non_nullable
as String?,templateSortOrder: freezed == templateSortOrder ? _self.templateSortOrder : templateSortOrder // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistEntry].
extension ChecklistEntryPatterns on ChecklistEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistEntry value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistEntry value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'template_id')  int templateId, @JsonKey(name: 'checklist_date')  String checklistDate,  bool completed, @JsonKey(name: 'completed_by')  String completedBy, @JsonKey(name: 'completed_at')  String? completedAt, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'template_name')  String? templateName, @JsonKey(name: 'template_period')  String? templatePeriod, @JsonKey(name: 'template_sort_order')  int? templateSortOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistEntry() when $default != null:
return $default(_that.id,_that.templateId,_that.checklistDate,_that.completed,_that.completedBy,_that.completedAt,_that.createdAt,_that.templateName,_that.templatePeriod,_that.templateSortOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'template_id')  int templateId, @JsonKey(name: 'checklist_date')  String checklistDate,  bool completed, @JsonKey(name: 'completed_by')  String completedBy, @JsonKey(name: 'completed_at')  String? completedAt, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'template_name')  String? templateName, @JsonKey(name: 'template_period')  String? templatePeriod, @JsonKey(name: 'template_sort_order')  int? templateSortOrder)  $default,) {final _that = this;
switch (_that) {
case _ChecklistEntry():
return $default(_that.id,_that.templateId,_that.checklistDate,_that.completed,_that.completedBy,_that.completedAt,_that.createdAt,_that.templateName,_that.templatePeriod,_that.templateSortOrder);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'template_id')  int templateId, @JsonKey(name: 'checklist_date')  String checklistDate,  bool completed, @JsonKey(name: 'completed_by')  String completedBy, @JsonKey(name: 'completed_at')  String? completedAt, @JsonKey(name: 'created_at')  String? createdAt, @JsonKey(name: 'template_name')  String? templateName, @JsonKey(name: 'template_period')  String? templatePeriod, @JsonKey(name: 'template_sort_order')  int? templateSortOrder)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistEntry() when $default != null:
return $default(_that.id,_that.templateId,_that.checklistDate,_that.completed,_that.completedBy,_that.completedAt,_that.createdAt,_that.templateName,_that.templatePeriod,_that.templateSortOrder);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistEntry implements ChecklistEntry {
  const _ChecklistEntry({required this.id, @JsonKey(name: 'template_id') required this.templateId, @JsonKey(name: 'checklist_date') required this.checklistDate, this.completed = false, @JsonKey(name: 'completed_by') this.completedBy = '', @JsonKey(name: 'completed_at') this.completedAt, @JsonKey(name: 'created_at') this.createdAt, @JsonKey(name: 'template_name') this.templateName, @JsonKey(name: 'template_period') this.templatePeriod, @JsonKey(name: 'template_sort_order') this.templateSortOrder});
  factory _ChecklistEntry.fromJson(Map<String, dynamic> json) => _$ChecklistEntryFromJson(json);

@override final  int id;
@override@JsonKey(name: 'template_id') final  int templateId;
@override@JsonKey(name: 'checklist_date') final  String checklistDate;
@override@JsonKey() final  bool completed;
@override@JsonKey(name: 'completed_by') final  String completedBy;
@override@JsonKey(name: 'completed_at') final  String? completedAt;
@override@JsonKey(name: 'created_at') final  String? createdAt;
@override@JsonKey(name: 'template_name') final  String? templateName;
@override@JsonKey(name: 'template_period') final  String? templatePeriod;
@override@JsonKey(name: 'template_sort_order') final  int? templateSortOrder;

/// Create a copy of ChecklistEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistEntryCopyWith<_ChecklistEntry> get copyWith => __$ChecklistEntryCopyWithImpl<_ChecklistEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.templateId, templateId) || other.templateId == templateId)&&(identical(other.checklistDate, checklistDate) || other.checklistDate == checklistDate)&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.completedBy, completedBy) || other.completedBy == completedBy)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.templateName, templateName) || other.templateName == templateName)&&(identical(other.templatePeriod, templatePeriod) || other.templatePeriod == templatePeriod)&&(identical(other.templateSortOrder, templateSortOrder) || other.templateSortOrder == templateSortOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,templateId,checklistDate,completed,completedBy,completedAt,createdAt,templateName,templatePeriod,templateSortOrder);

@override
String toString() {
  return 'ChecklistEntry(id: $id, templateId: $templateId, checklistDate: $checklistDate, completed: $completed, completedBy: $completedBy, completedAt: $completedAt, createdAt: $createdAt, templateName: $templateName, templatePeriod: $templatePeriod, templateSortOrder: $templateSortOrder)';
}


}

/// @nodoc
abstract mixin class _$ChecklistEntryCopyWith<$Res> implements $ChecklistEntryCopyWith<$Res> {
  factory _$ChecklistEntryCopyWith(_ChecklistEntry value, $Res Function(_ChecklistEntry) _then) = __$ChecklistEntryCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'template_id') int templateId,@JsonKey(name: 'checklist_date') String checklistDate, bool completed,@JsonKey(name: 'completed_by') String completedBy,@JsonKey(name: 'completed_at') String? completedAt,@JsonKey(name: 'created_at') String? createdAt,@JsonKey(name: 'template_name') String? templateName,@JsonKey(name: 'template_period') String? templatePeriod,@JsonKey(name: 'template_sort_order') int? templateSortOrder
});




}
/// @nodoc
class __$ChecklistEntryCopyWithImpl<$Res>
    implements _$ChecklistEntryCopyWith<$Res> {
  __$ChecklistEntryCopyWithImpl(this._self, this._then);

  final _ChecklistEntry _self;
  final $Res Function(_ChecklistEntry) _then;

/// Create a copy of ChecklistEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? templateId = null,Object? checklistDate = null,Object? completed = null,Object? completedBy = null,Object? completedAt = freezed,Object? createdAt = freezed,Object? templateName = freezed,Object? templatePeriod = freezed,Object? templateSortOrder = freezed,}) {
  return _then(_ChecklistEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,templateId: null == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as int,checklistDate: null == checklistDate ? _self.checklistDate : checklistDate // ignore: cast_nullable_to_non_nullable
as String,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,completedBy: null == completedBy ? _self.completedBy : completedBy // ignore: cast_nullable_to_non_nullable
as String,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,templateName: freezed == templateName ? _self.templateName : templateName // ignore: cast_nullable_to_non_nullable
as String?,templatePeriod: freezed == templatePeriod ? _self.templatePeriod : templatePeriod // ignore: cast_nullable_to_non_nullable
as String?,templateSortOrder: freezed == templateSortOrder ? _self.templateSortOrder : templateSortOrder // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on

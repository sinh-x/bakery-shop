// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'blank.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Blank {

 int get id; String get name; String get category; String get unit; String get notes;@JsonKey(name: 'createdAt') String? get createdAt;@JsonKey(name: 'updatedAt') String? get updatedAt;
/// Create a copy of Blank
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankCopyWith<Blank> get copyWith => _$BlankCopyWithImpl<Blank>(this as Blank, _$identity);

  /// Serializes this Blank to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Blank&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,category,unit,notes,createdAt,updatedAt);

@override
String toString() {
  return 'Blank(id: $id, name: $name, category: $category, unit: $unit, notes: $notes, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BlankCopyWith<$Res>  {
  factory $BlankCopyWith(Blank value, $Res Function(Blank) _then) = _$BlankCopyWithImpl;
@useResult
$Res call({
 int id, String name, String category, String unit, String notes,@JsonKey(name: 'createdAt') String? createdAt,@JsonKey(name: 'updatedAt') String? updatedAt
});




}
/// @nodoc
class _$BlankCopyWithImpl<$Res>
    implements $BlankCopyWith<$Res> {
  _$BlankCopyWithImpl(this._self, this._then);

  final Blank _self;
  final $Res Function(Blank) _then;

/// Create a copy of Blank
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? category = null,Object? unit = null,Object? notes = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Blank].
extension BlankPatterns on Blank {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Blank value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Blank() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Blank value)  $default,){
final _that = this;
switch (_that) {
case _Blank():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Blank value)?  $default,){
final _that = this;
switch (_that) {
case _Blank() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  String category,  String unit,  String notes, @JsonKey(name: 'createdAt')  String? createdAt, @JsonKey(name: 'updatedAt')  String? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Blank() when $default != null:
return $default(_that.id,_that.name,_that.category,_that.unit,_that.notes,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  String category,  String unit,  String notes, @JsonKey(name: 'createdAt')  String? createdAt, @JsonKey(name: 'updatedAt')  String? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Blank():
return $default(_that.id,_that.name,_that.category,_that.unit,_that.notes,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  String category,  String unit,  String notes, @JsonKey(name: 'createdAt')  String? createdAt, @JsonKey(name: 'updatedAt')  String? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Blank() when $default != null:
return $default(_that.id,_that.name,_that.category,_that.unit,_that.notes,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Blank implements Blank {
  const _Blank({required this.id, required this.name, this.category = '', this.unit = '', this.notes = '', @JsonKey(name: 'createdAt') this.createdAt, @JsonKey(name: 'updatedAt') this.updatedAt});
  factory _Blank.fromJson(Map<String, dynamic> json) => _$BlankFromJson(json);

@override final  int id;
@override final  String name;
@override@JsonKey() final  String category;
@override@JsonKey() final  String unit;
@override@JsonKey() final  String notes;
@override@JsonKey(name: 'createdAt') final  String? createdAt;
@override@JsonKey(name: 'updatedAt') final  String? updatedAt;

/// Create a copy of Blank
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankCopyWith<_Blank> get copyWith => __$BlankCopyWithImpl<_Blank>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Blank&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,category,unit,notes,createdAt,updatedAt);

@override
String toString() {
  return 'Blank(id: $id, name: $name, category: $category, unit: $unit, notes: $notes, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$BlankCopyWith<$Res> implements $BlankCopyWith<$Res> {
  factory _$BlankCopyWith(_Blank value, $Res Function(_Blank) _then) = __$BlankCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, String category, String unit, String notes,@JsonKey(name: 'createdAt') String? createdAt,@JsonKey(name: 'updatedAt') String? updatedAt
});




}
/// @nodoc
class __$BlankCopyWithImpl<$Res>
    implements _$BlankCopyWith<$Res> {
  __$BlankCopyWithImpl(this._self, this._then);

  final _Blank _self;
  final $Res Function(_Blank) _then;

/// Create a copy of Blank
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? category = null,Object? unit = null,Object? notes = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_Blank(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$BlankCreate {

 String get name; String get category; String get unit; String get notes;
/// Create a copy of BlankCreate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankCreateCopyWith<BlankCreate> get copyWith => _$BlankCreateCopyWithImpl<BlankCreate>(this as BlankCreate, _$identity);

  /// Serializes this BlankCreate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankCreate&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,category,unit,notes);

@override
String toString() {
  return 'BlankCreate(name: $name, category: $category, unit: $unit, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $BlankCreateCopyWith<$Res>  {
  factory $BlankCreateCopyWith(BlankCreate value, $Res Function(BlankCreate) _then) = _$BlankCreateCopyWithImpl;
@useResult
$Res call({
 String name, String category, String unit, String notes
});




}
/// @nodoc
class _$BlankCreateCopyWithImpl<$Res>
    implements $BlankCreateCopyWith<$Res> {
  _$BlankCreateCopyWithImpl(this._self, this._then);

  final BlankCreate _self;
  final $Res Function(BlankCreate) _then;

/// Create a copy of BlankCreate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? category = null,Object? unit = null,Object? notes = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankCreate].
extension BlankCreatePatterns on BlankCreate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankCreate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankCreate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankCreate value)  $default,){
final _that = this;
switch (_that) {
case _BlankCreate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankCreate value)?  $default,){
final _that = this;
switch (_that) {
case _BlankCreate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String category,  String unit,  String notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankCreate() when $default != null:
return $default(_that.name,_that.category,_that.unit,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String category,  String unit,  String notes)  $default,) {final _that = this;
switch (_that) {
case _BlankCreate():
return $default(_that.name,_that.category,_that.unit,_that.notes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String category,  String unit,  String notes)?  $default,) {final _that = this;
switch (_that) {
case _BlankCreate() when $default != null:
return $default(_that.name,_that.category,_that.unit,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankCreate implements BlankCreate {
  const _BlankCreate({required this.name, this.category = '', this.unit = '', this.notes = ''});
  factory _BlankCreate.fromJson(Map<String, dynamic> json) => _$BlankCreateFromJson(json);

@override final  String name;
@override@JsonKey() final  String category;
@override@JsonKey() final  String unit;
@override@JsonKey() final  String notes;

/// Create a copy of BlankCreate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankCreateCopyWith<_BlankCreate> get copyWith => __$BlankCreateCopyWithImpl<_BlankCreate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankCreateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankCreate&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,category,unit,notes);

@override
String toString() {
  return 'BlankCreate(name: $name, category: $category, unit: $unit, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$BlankCreateCopyWith<$Res> implements $BlankCreateCopyWith<$Res> {
  factory _$BlankCreateCopyWith(_BlankCreate value, $Res Function(_BlankCreate) _then) = __$BlankCreateCopyWithImpl;
@override @useResult
$Res call({
 String name, String category, String unit, String notes
});




}
/// @nodoc
class __$BlankCreateCopyWithImpl<$Res>
    implements _$BlankCreateCopyWith<$Res> {
  __$BlankCreateCopyWithImpl(this._self, this._then);

  final _BlankCreate _self;
  final $Res Function(_BlankCreate) _then;

/// Create a copy of BlankCreate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? category = null,Object? unit = null,Object? notes = null,}) {
  return _then(_BlankCreate(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$BlankUpdate {

 String? get name; String? get category; String? get unit; String? get notes;
/// Create a copy of BlankUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankUpdateCopyWith<BlankUpdate> get copyWith => _$BlankUpdateCopyWithImpl<BlankUpdate>(this as BlankUpdate, _$identity);

  /// Serializes this BlankUpdate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankUpdate&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,category,unit,notes);

@override
String toString() {
  return 'BlankUpdate(name: $name, category: $category, unit: $unit, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $BlankUpdateCopyWith<$Res>  {
  factory $BlankUpdateCopyWith(BlankUpdate value, $Res Function(BlankUpdate) _then) = _$BlankUpdateCopyWithImpl;
@useResult
$Res call({
 String? name, String? category, String? unit, String? notes
});




}
/// @nodoc
class _$BlankUpdateCopyWithImpl<$Res>
    implements $BlankUpdateCopyWith<$Res> {
  _$BlankUpdateCopyWithImpl(this._self, this._then);

  final BlankUpdate _self;
  final $Res Function(BlankUpdate) _then;

/// Create a copy of BlankUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = freezed,Object? category = freezed,Object? unit = freezed,Object? notes = freezed,}) {
  return _then(_self.copyWith(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankUpdate].
extension BlankUpdatePatterns on BlankUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankUpdate value)  $default,){
final _that = this;
switch (_that) {
case _BlankUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _BlankUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? name,  String? category,  String? unit,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankUpdate() when $default != null:
return $default(_that.name,_that.category,_that.unit,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? name,  String? category,  String? unit,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _BlankUpdate():
return $default(_that.name,_that.category,_that.unit,_that.notes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? name,  String? category,  String? unit,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _BlankUpdate() when $default != null:
return $default(_that.name,_that.category,_that.unit,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankUpdate implements BlankUpdate {
  const _BlankUpdate({this.name, this.category, this.unit, this.notes});
  factory _BlankUpdate.fromJson(Map<String, dynamic> json) => _$BlankUpdateFromJson(json);

@override final  String? name;
@override final  String? category;
@override final  String? unit;
@override final  String? notes;

/// Create a copy of BlankUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankUpdateCopyWith<_BlankUpdate> get copyWith => __$BlankUpdateCopyWithImpl<_BlankUpdate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankUpdateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankUpdate&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,category,unit,notes);

@override
String toString() {
  return 'BlankUpdate(name: $name, category: $category, unit: $unit, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$BlankUpdateCopyWith<$Res> implements $BlankUpdateCopyWith<$Res> {
  factory _$BlankUpdateCopyWith(_BlankUpdate value, $Res Function(_BlankUpdate) _then) = __$BlankUpdateCopyWithImpl;
@override @useResult
$Res call({
 String? name, String? category, String? unit, String? notes
});




}
/// @nodoc
class __$BlankUpdateCopyWithImpl<$Res>
    implements _$BlankUpdateCopyWith<$Res> {
  __$BlankUpdateCopyWithImpl(this._self, this._then);

  final _BlankUpdate _self;
  final $Res Function(_BlankUpdate) _then;

/// Create a copy of BlankUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = freezed,Object? category = freezed,Object? unit = freezed,Object? notes = freezed,}) {
  return _then(_BlankUpdate(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ProductBlankBom {

 int get id;@JsonKey(name: 'productId') int? get productId;@JsonKey(name: 'priceChipId') int? get priceChipId;@JsonKey(name: 'blankId') int get blankId; double get quantity;@JsonKey(name: 'createdAt') String? get createdAt;
/// Create a copy of ProductBlankBom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductBlankBomCopyWith<ProductBlankBom> get copyWith => _$ProductBlankBomCopyWithImpl<ProductBlankBom>(this as ProductBlankBom, _$identity);

  /// Serializes this ProductBlankBom to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductBlankBom&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.priceChipId, priceChipId) || other.priceChipId == priceChipId)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,priceChipId,blankId,quantity,createdAt);

@override
String toString() {
  return 'ProductBlankBom(id: $id, productId: $productId, priceChipId: $priceChipId, blankId: $blankId, quantity: $quantity, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $ProductBlankBomCopyWith<$Res>  {
  factory $ProductBlankBomCopyWith(ProductBlankBom value, $Res Function(ProductBlankBom) _then) = _$ProductBlankBomCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'productId') int? productId,@JsonKey(name: 'priceChipId') int? priceChipId,@JsonKey(name: 'blankId') int blankId, double quantity,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class _$ProductBlankBomCopyWithImpl<$Res>
    implements $ProductBlankBomCopyWith<$Res> {
  _$ProductBlankBomCopyWithImpl(this._self, this._then);

  final ProductBlankBom _self;
  final $Res Function(ProductBlankBom) _then;

/// Create a copy of ProductBlankBom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = freezed,Object? priceChipId = freezed,Object? blankId = null,Object? quantity = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: freezed == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int?,priceChipId: freezed == priceChipId ? _self.priceChipId : priceChipId // ignore: cast_nullable_to_non_nullable
as int?,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductBlankBom].
extension ProductBlankBomPatterns on ProductBlankBom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductBlankBom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductBlankBom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductBlankBom value)  $default,){
final _that = this;
switch (_that) {
case _ProductBlankBom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductBlankBom value)?  $default,){
final _that = this;
switch (_that) {
case _ProductBlankBom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'productId')  int? productId, @JsonKey(name: 'priceChipId')  int? priceChipId, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductBlankBom() when $default != null:
return $default(_that.id,_that.productId,_that.priceChipId,_that.blankId,_that.quantity,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'productId')  int? productId, @JsonKey(name: 'priceChipId')  int? priceChipId, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'createdAt')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ProductBlankBom():
return $default(_that.id,_that.productId,_that.priceChipId,_that.blankId,_that.quantity,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'productId')  int? productId, @JsonKey(name: 'priceChipId')  int? priceChipId, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ProductBlankBom() when $default != null:
return $default(_that.id,_that.productId,_that.priceChipId,_that.blankId,_that.quantity,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductBlankBom implements ProductBlankBom {
  const _ProductBlankBom({required this.id, @JsonKey(name: 'productId') this.productId, @JsonKey(name: 'priceChipId') this.priceChipId, @JsonKey(name: 'blankId') required this.blankId, this.quantity = 1.0, @JsonKey(name: 'createdAt') this.createdAt});
  factory _ProductBlankBom.fromJson(Map<String, dynamic> json) => _$ProductBlankBomFromJson(json);

@override final  int id;
@override@JsonKey(name: 'productId') final  int? productId;
@override@JsonKey(name: 'priceChipId') final  int? priceChipId;
@override@JsonKey(name: 'blankId') final  int blankId;
@override@JsonKey() final  double quantity;
@override@JsonKey(name: 'createdAt') final  String? createdAt;

/// Create a copy of ProductBlankBom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductBlankBomCopyWith<_ProductBlankBom> get copyWith => __$ProductBlankBomCopyWithImpl<_ProductBlankBom>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductBlankBomToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductBlankBom&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.priceChipId, priceChipId) || other.priceChipId == priceChipId)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,priceChipId,blankId,quantity,createdAt);

@override
String toString() {
  return 'ProductBlankBom(id: $id, productId: $productId, priceChipId: $priceChipId, blankId: $blankId, quantity: $quantity, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ProductBlankBomCopyWith<$Res> implements $ProductBlankBomCopyWith<$Res> {
  factory _$ProductBlankBomCopyWith(_ProductBlankBom value, $Res Function(_ProductBlankBom) _then) = __$ProductBlankBomCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'productId') int? productId,@JsonKey(name: 'priceChipId') int? priceChipId,@JsonKey(name: 'blankId') int blankId, double quantity,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class __$ProductBlankBomCopyWithImpl<$Res>
    implements _$ProductBlankBomCopyWith<$Res> {
  __$ProductBlankBomCopyWithImpl(this._self, this._then);

  final _ProductBlankBom _self;
  final $Res Function(_ProductBlankBom) _then;

/// Create a copy of ProductBlankBom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = freezed,Object? priceChipId = freezed,Object? blankId = null,Object? quantity = null,Object? createdAt = freezed,}) {
  return _then(_ProductBlankBom(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,productId: freezed == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int?,priceChipId: freezed == priceChipId ? _self.priceChipId : priceChipId // ignore: cast_nullable_to_non_nullable
as int?,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$BomCreate {

@JsonKey(name: 'blankId') int get blankId; double get quantity;
/// Create a copy of BomCreate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BomCreateCopyWith<BomCreate> get copyWith => _$BomCreateCopyWithImpl<BomCreate>(this as BomCreate, _$identity);

  /// Serializes this BomCreate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BomCreate&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,quantity);

@override
String toString() {
  return 'BomCreate(blankId: $blankId, quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class $BomCreateCopyWith<$Res>  {
  factory $BomCreateCopyWith(BomCreate value, $Res Function(BomCreate) _then) = _$BomCreateCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, double quantity
});




}
/// @nodoc
class _$BomCreateCopyWithImpl<$Res>
    implements $BomCreateCopyWith<$Res> {
  _$BomCreateCopyWithImpl(this._self, this._then);

  final BomCreate _self;
  final $Res Function(BomCreate) _then;

/// Create a copy of BomCreate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? blankId = null,Object? quantity = null,}) {
  return _then(_self.copyWith(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [BomCreate].
extension BomCreatePatterns on BomCreate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BomCreate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BomCreate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BomCreate value)  $default,){
final _that = this;
switch (_that) {
case _BomCreate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BomCreate value)?  $default,){
final _that = this;
switch (_that) {
case _BomCreate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  double quantity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BomCreate() when $default != null:
return $default(_that.blankId,_that.quantity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  double quantity)  $default,) {final _that = this;
switch (_that) {
case _BomCreate():
return $default(_that.blankId,_that.quantity);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'blankId')  int blankId,  double quantity)?  $default,) {final _that = this;
switch (_that) {
case _BomCreate() when $default != null:
return $default(_that.blankId,_that.quantity);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BomCreate implements BomCreate {
  const _BomCreate({@JsonKey(name: 'blankId') required this.blankId, this.quantity = 1.0});
  factory _BomCreate.fromJson(Map<String, dynamic> json) => _$BomCreateFromJson(json);

@override@JsonKey(name: 'blankId') final  int blankId;
@override@JsonKey() final  double quantity;

/// Create a copy of BomCreate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BomCreateCopyWith<_BomCreate> get copyWith => __$BomCreateCopyWithImpl<_BomCreate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BomCreateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BomCreate&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,quantity);

@override
String toString() {
  return 'BomCreate(blankId: $blankId, quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class _$BomCreateCopyWith<$Res> implements $BomCreateCopyWith<$Res> {
  factory _$BomCreateCopyWith(_BomCreate value, $Res Function(_BomCreate) _then) = __$BomCreateCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, double quantity
});




}
/// @nodoc
class __$BomCreateCopyWithImpl<$Res>
    implements _$BomCreateCopyWith<$Res> {
  __$BomCreateCopyWithImpl(this._self, this._then);

  final _BomCreate _self;
  final $Res Function(_BomCreate) _then;

/// Create a copy of BomCreate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? blankId = null,Object? quantity = null,}) {
  return _then(_BomCreate(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BomUpdate {

 double get quantity;
/// Create a copy of BomUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BomUpdateCopyWith<BomUpdate> get copyWith => _$BomUpdateCopyWithImpl<BomUpdate>(this as BomUpdate, _$identity);

  /// Serializes this BomUpdate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BomUpdate&&(identical(other.quantity, quantity) || other.quantity == quantity));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,quantity);

@override
String toString() {
  return 'BomUpdate(quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class $BomUpdateCopyWith<$Res>  {
  factory $BomUpdateCopyWith(BomUpdate value, $Res Function(BomUpdate) _then) = _$BomUpdateCopyWithImpl;
@useResult
$Res call({
 double quantity
});




}
/// @nodoc
class _$BomUpdateCopyWithImpl<$Res>
    implements $BomUpdateCopyWith<$Res> {
  _$BomUpdateCopyWithImpl(this._self, this._then);

  final BomUpdate _self;
  final $Res Function(BomUpdate) _then;

/// Create a copy of BomUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? quantity = null,}) {
  return _then(_self.copyWith(
quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [BomUpdate].
extension BomUpdatePatterns on BomUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BomUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BomUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BomUpdate value)  $default,){
final _that = this;
switch (_that) {
case _BomUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BomUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _BomUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double quantity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BomUpdate() when $default != null:
return $default(_that.quantity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double quantity)  $default,) {final _that = this;
switch (_that) {
case _BomUpdate():
return $default(_that.quantity);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double quantity)?  $default,) {final _that = this;
switch (_that) {
case _BomUpdate() when $default != null:
return $default(_that.quantity);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BomUpdate implements BomUpdate {
  const _BomUpdate({this.quantity = 1.0});
  factory _BomUpdate.fromJson(Map<String, dynamic> json) => _$BomUpdateFromJson(json);

@override@JsonKey() final  double quantity;

/// Create a copy of BomUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BomUpdateCopyWith<_BomUpdate> get copyWith => __$BomUpdateCopyWithImpl<_BomUpdate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BomUpdateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BomUpdate&&(identical(other.quantity, quantity) || other.quantity == quantity));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,quantity);

@override
String toString() {
  return 'BomUpdate(quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class _$BomUpdateCopyWith<$Res> implements $BomUpdateCopyWith<$Res> {
  factory _$BomUpdateCopyWith(_BomUpdate value, $Res Function(_BomUpdate) _then) = __$BomUpdateCopyWithImpl;
@override @useResult
$Res call({
 double quantity
});




}
/// @nodoc
class __$BomUpdateCopyWithImpl<$Res>
    implements _$BomUpdateCopyWith<$Res> {
  __$BomUpdateCopyWithImpl(this._self, this._then);

  final _BomUpdate _self;
  final $Res Function(_BomUpdate) _then;

/// Create a copy of BomUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? quantity = null,}) {
  return _then(_BomUpdate(
quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BlankStockEntry {

 int get id;@JsonKey(name: 'blankId') int get blankId; double get quantity;@JsonKey(name: 'producedDate') String get producedDate;@JsonKey(name: 'expiryDate') String? get expiryDate; String get type;@JsonKey(name: 'createdAt') String? get createdAt;
/// Create a copy of BlankStockEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankStockEntryCopyWith<BlankStockEntry> get copyWith => _$BlankStockEntryCopyWithImpl<BlankStockEntry>(this as BlankStockEntry, _$identity);

  /// Serializes this BlankStockEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankStockEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,blankId,quantity,producedDate,expiryDate,type,createdAt);

@override
String toString() {
  return 'BlankStockEntry(id: $id, blankId: $blankId, quantity: $quantity, producedDate: $producedDate, expiryDate: $expiryDate, type: $type, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $BlankStockEntryCopyWith<$Res>  {
  factory $BlankStockEntryCopyWith(BlankStockEntry value, $Res Function(BlankStockEntry) _then) = _$BlankStockEntryCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'blankId') int blankId, double quantity,@JsonKey(name: 'producedDate') String producedDate,@JsonKey(name: 'expiryDate') String? expiryDate, String type,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class _$BlankStockEntryCopyWithImpl<$Res>
    implements $BlankStockEntryCopyWith<$Res> {
  _$BlankStockEntryCopyWithImpl(this._self, this._then);

  final BlankStockEntry _self;
  final $Res Function(BlankStockEntry) _then;

/// Create a copy of BlankStockEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? blankId = null,Object? quantity = null,Object? producedDate = null,Object? expiryDate = freezed,Object? type = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,producedDate: null == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankStockEntry].
extension BlankStockEntryPatterns on BlankStockEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankStockEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankStockEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankStockEntry value)  $default,){
final _that = this;
switch (_that) {
case _BlankStockEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankStockEntry value)?  $default,){
final _that = this;
switch (_that) {
case _BlankStockEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate,  String type, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankStockEntry() when $default != null:
return $default(_that.id,_that.blankId,_that.quantity,_that.producedDate,_that.expiryDate,_that.type,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate,  String type, @JsonKey(name: 'createdAt')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _BlankStockEntry():
return $default(_that.id,_that.blankId,_that.quantity,_that.producedDate,_that.expiryDate,_that.type,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'blankId')  int blankId,  double quantity, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate,  String type, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _BlankStockEntry() when $default != null:
return $default(_that.id,_that.blankId,_that.quantity,_that.producedDate,_that.expiryDate,_that.type,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankStockEntry implements BlankStockEntry {
  const _BlankStockEntry({required this.id, @JsonKey(name: 'blankId') required this.blankId, this.quantity = 0.0, @JsonKey(name: 'producedDate') this.producedDate = '', @JsonKey(name: 'expiryDate') this.expiryDate, this.type = 'production', @JsonKey(name: 'createdAt') this.createdAt});
  factory _BlankStockEntry.fromJson(Map<String, dynamic> json) => _$BlankStockEntryFromJson(json);

@override final  int id;
@override@JsonKey(name: 'blankId') final  int blankId;
@override@JsonKey() final  double quantity;
@override@JsonKey(name: 'producedDate') final  String producedDate;
@override@JsonKey(name: 'expiryDate') final  String? expiryDate;
@override@JsonKey() final  String type;
@override@JsonKey(name: 'createdAt') final  String? createdAt;

/// Create a copy of BlankStockEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankStockEntryCopyWith<_BlankStockEntry> get copyWith => __$BlankStockEntryCopyWithImpl<_BlankStockEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankStockEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankStockEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,blankId,quantity,producedDate,expiryDate,type,createdAt);

@override
String toString() {
  return 'BlankStockEntry(id: $id, blankId: $blankId, quantity: $quantity, producedDate: $producedDate, expiryDate: $expiryDate, type: $type, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$BlankStockEntryCopyWith<$Res> implements $BlankStockEntryCopyWith<$Res> {
  factory _$BlankStockEntryCopyWith(_BlankStockEntry value, $Res Function(_BlankStockEntry) _then) = __$BlankStockEntryCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'blankId') int blankId, double quantity,@JsonKey(name: 'producedDate') String producedDate,@JsonKey(name: 'expiryDate') String? expiryDate, String type,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class __$BlankStockEntryCopyWithImpl<$Res>
    implements _$BlankStockEntryCopyWith<$Res> {
  __$BlankStockEntryCopyWithImpl(this._self, this._then);

  final _BlankStockEntry _self;
  final $Res Function(_BlankStockEntry) _then;

/// Create a copy of BlankStockEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? blankId = null,Object? quantity = null,Object? producedDate = null,Object? expiryDate = freezed,Object? type = null,Object? createdAt = freezed,}) {
  return _then(_BlankStockEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,producedDate: null == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$BlankStockSummary {

@JsonKey(name: 'blankId') int get blankId; String get name; String get category; String get unit; double get stock;
/// Create a copy of BlankStockSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankStockSummaryCopyWith<BlankStockSummary> get copyWith => _$BlankStockSummaryCopyWithImpl<BlankStockSummary>(this as BlankStockSummary, _$identity);

  /// Serializes this BlankStockSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankStockSummary&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.stock, stock) || other.stock == stock));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,name,category,unit,stock);

@override
String toString() {
  return 'BlankStockSummary(blankId: $blankId, name: $name, category: $category, unit: $unit, stock: $stock)';
}


}

/// @nodoc
abstract mixin class $BlankStockSummaryCopyWith<$Res>  {
  factory $BlankStockSummaryCopyWith(BlankStockSummary value, $Res Function(BlankStockSummary) _then) = _$BlankStockSummaryCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, String name, String category, String unit, double stock
});




}
/// @nodoc
class _$BlankStockSummaryCopyWithImpl<$Res>
    implements $BlankStockSummaryCopyWith<$Res> {
  _$BlankStockSummaryCopyWithImpl(this._self, this._then);

  final BlankStockSummary _self;
  final $Res Function(BlankStockSummary) _then;

/// Create a copy of BlankStockSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? blankId = null,Object? name = null,Object? category = null,Object? unit = null,Object? stock = null,}) {
  return _then(_self.copyWith(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankStockSummary].
extension BlankStockSummaryPatterns on BlankStockSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankStockSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankStockSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankStockSummary value)  $default,){
final _that = this;
switch (_that) {
case _BlankStockSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankStockSummary value)?  $default,){
final _that = this;
switch (_that) {
case _BlankStockSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double stock)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankStockSummary() when $default != null:
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.stock);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double stock)  $default,) {final _that = this;
switch (_that) {
case _BlankStockSummary():
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.stock);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double stock)?  $default,) {final _that = this;
switch (_that) {
case _BlankStockSummary() when $default != null:
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.stock);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankStockSummary implements BlankStockSummary {
  const _BlankStockSummary({@JsonKey(name: 'blankId') required this.blankId, required this.name, this.category = '', this.unit = '', this.stock = 0.0});
  factory _BlankStockSummary.fromJson(Map<String, dynamic> json) => _$BlankStockSummaryFromJson(json);

@override@JsonKey(name: 'blankId') final  int blankId;
@override final  String name;
@override@JsonKey() final  String category;
@override@JsonKey() final  String unit;
@override@JsonKey() final  double stock;

/// Create a copy of BlankStockSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankStockSummaryCopyWith<_BlankStockSummary> get copyWith => __$BlankStockSummaryCopyWithImpl<_BlankStockSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankStockSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankStockSummary&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.stock, stock) || other.stock == stock));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,name,category,unit,stock);

@override
String toString() {
  return 'BlankStockSummary(blankId: $blankId, name: $name, category: $category, unit: $unit, stock: $stock)';
}


}

/// @nodoc
abstract mixin class _$BlankStockSummaryCopyWith<$Res> implements $BlankStockSummaryCopyWith<$Res> {
  factory _$BlankStockSummaryCopyWith(_BlankStockSummary value, $Res Function(_BlankStockSummary) _then) = __$BlankStockSummaryCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, String name, String category, String unit, double stock
});




}
/// @nodoc
class __$BlankStockSummaryCopyWithImpl<$Res>
    implements _$BlankStockSummaryCopyWith<$Res> {
  __$BlankStockSummaryCopyWithImpl(this._self, this._then);

  final _BlankStockSummary _self;
  final $Res Function(_BlankStockSummary) _then;

/// Create a copy of BlankStockSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? blankId = null,Object? name = null,Object? category = null,Object? unit = null,Object? stock = null,}) {
  return _then(_BlankStockSummary(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$StockCreate {

@JsonKey(name: 'blankId') int get blankId; double get quantity; String get type;@JsonKey(name: 'producedDate') String get producedDate;@JsonKey(name: 'expiryDate') String? get expiryDate;
/// Create a copy of StockCreate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StockCreateCopyWith<StockCreate> get copyWith => _$StockCreateCopyWithImpl<StockCreate>(this as StockCreate, _$identity);

  /// Serializes this StockCreate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StockCreate&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.type, type) || other.type == type)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,quantity,type,producedDate,expiryDate);

@override
String toString() {
  return 'StockCreate(blankId: $blankId, quantity: $quantity, type: $type, producedDate: $producedDate, expiryDate: $expiryDate)';
}


}

/// @nodoc
abstract mixin class $StockCreateCopyWith<$Res>  {
  factory $StockCreateCopyWith(StockCreate value, $Res Function(StockCreate) _then) = _$StockCreateCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, double quantity, String type,@JsonKey(name: 'producedDate') String producedDate,@JsonKey(name: 'expiryDate') String? expiryDate
});




}
/// @nodoc
class _$StockCreateCopyWithImpl<$Res>
    implements $StockCreateCopyWith<$Res> {
  _$StockCreateCopyWithImpl(this._self, this._then);

  final StockCreate _self;
  final $Res Function(StockCreate) _then;

/// Create a copy of StockCreate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? blankId = null,Object? quantity = null,Object? type = null,Object? producedDate = null,Object? expiryDate = freezed,}) {
  return _then(_self.copyWith(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,producedDate: null == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StockCreate].
extension StockCreatePatterns on StockCreate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StockCreate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StockCreate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StockCreate value)  $default,){
final _that = this;
switch (_that) {
case _StockCreate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StockCreate value)?  $default,){
final _that = this;
switch (_that) {
case _StockCreate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  double quantity,  String type, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StockCreate() when $default != null:
return $default(_that.blankId,_that.quantity,_that.type,_that.producedDate,_that.expiryDate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  double quantity,  String type, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate)  $default,) {final _that = this;
switch (_that) {
case _StockCreate():
return $default(_that.blankId,_that.quantity,_that.type,_that.producedDate,_that.expiryDate);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'blankId')  int blankId,  double quantity,  String type, @JsonKey(name: 'producedDate')  String producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate)?  $default,) {final _that = this;
switch (_that) {
case _StockCreate() when $default != null:
return $default(_that.blankId,_that.quantity,_that.type,_that.producedDate,_that.expiryDate);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StockCreate implements StockCreate {
  const _StockCreate({@JsonKey(name: 'blankId') required this.blankId, required this.quantity, required this.type, @JsonKey(name: 'producedDate') this.producedDate = '', @JsonKey(name: 'expiryDate') this.expiryDate});
  factory _StockCreate.fromJson(Map<String, dynamic> json) => _$StockCreateFromJson(json);

@override@JsonKey(name: 'blankId') final  int blankId;
@override final  double quantity;
@override final  String type;
@override@JsonKey(name: 'producedDate') final  String producedDate;
@override@JsonKey(name: 'expiryDate') final  String? expiryDate;

/// Create a copy of StockCreate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StockCreateCopyWith<_StockCreate> get copyWith => __$StockCreateCopyWithImpl<_StockCreate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StockCreateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StockCreate&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.type, type) || other.type == type)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,quantity,type,producedDate,expiryDate);

@override
String toString() {
  return 'StockCreate(blankId: $blankId, quantity: $quantity, type: $type, producedDate: $producedDate, expiryDate: $expiryDate)';
}


}

/// @nodoc
abstract mixin class _$StockCreateCopyWith<$Res> implements $StockCreateCopyWith<$Res> {
  factory _$StockCreateCopyWith(_StockCreate value, $Res Function(_StockCreate) _then) = __$StockCreateCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, double quantity, String type,@JsonKey(name: 'producedDate') String producedDate,@JsonKey(name: 'expiryDate') String? expiryDate
});




}
/// @nodoc
class __$StockCreateCopyWithImpl<$Res>
    implements _$StockCreateCopyWith<$Res> {
  __$StockCreateCopyWithImpl(this._self, this._then);

  final _StockCreate _self;
  final $Res Function(_StockCreate) _then;

/// Create a copy of StockCreate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? blankId = null,Object? quantity = null,Object? type = null,Object? producedDate = null,Object? expiryDate = freezed,}) {
  return _then(_StockCreate(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,producedDate: null == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$BlankDemand {

@JsonKey(name: 'blankId') int get blankId; String get name; String get category; String get unit; double get demand; double get stock; double get shortage;
/// Create a copy of BlankDemand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankDemandCopyWith<BlankDemand> get copyWith => _$BlankDemandCopyWithImpl<BlankDemand>(this as BlankDemand, _$identity);

  /// Serializes this BlankDemand to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankDemand&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.demand, demand) || other.demand == demand)&&(identical(other.stock, stock) || other.stock == stock)&&(identical(other.shortage, shortage) || other.shortage == shortage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,name,category,unit,demand,stock,shortage);

@override
String toString() {
  return 'BlankDemand(blankId: $blankId, name: $name, category: $category, unit: $unit, demand: $demand, stock: $stock, shortage: $shortage)';
}


}

/// @nodoc
abstract mixin class $BlankDemandCopyWith<$Res>  {
  factory $BlankDemandCopyWith(BlankDemand value, $Res Function(BlankDemand) _then) = _$BlankDemandCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, String name, String category, String unit, double demand, double stock, double shortage
});




}
/// @nodoc
class _$BlankDemandCopyWithImpl<$Res>
    implements $BlankDemandCopyWith<$Res> {
  _$BlankDemandCopyWithImpl(this._self, this._then);

  final BlankDemand _self;
  final $Res Function(BlankDemand) _then;

/// Create a copy of BlankDemand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? blankId = null,Object? name = null,Object? category = null,Object? unit = null,Object? demand = null,Object? stock = null,Object? shortage = null,}) {
  return _then(_self.copyWith(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,demand: null == demand ? _self.demand : demand // ignore: cast_nullable_to_non_nullable
as double,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as double,shortage: null == shortage ? _self.shortage : shortage // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankDemand].
extension BlankDemandPatterns on BlankDemand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankDemand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankDemand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankDemand value)  $default,){
final _that = this;
switch (_that) {
case _BlankDemand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankDemand value)?  $default,){
final _that = this;
switch (_that) {
case _BlankDemand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double demand,  double stock,  double shortage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankDemand() when $default != null:
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.demand,_that.stock,_that.shortage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double demand,  double stock,  double shortage)  $default,) {final _that = this;
switch (_that) {
case _BlankDemand():
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.demand,_that.stock,_that.shortage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'blankId')  int blankId,  String name,  String category,  String unit,  double demand,  double stock,  double shortage)?  $default,) {final _that = this;
switch (_that) {
case _BlankDemand() when $default != null:
return $default(_that.blankId,_that.name,_that.category,_that.unit,_that.demand,_that.stock,_that.shortage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankDemand implements BlankDemand {
  const _BlankDemand({@JsonKey(name: 'blankId') required this.blankId, required this.name, this.category = '', this.unit = '', this.demand = 0.0, this.stock = 0.0, this.shortage = 0.0});
  factory _BlankDemand.fromJson(Map<String, dynamic> json) => _$BlankDemandFromJson(json);

@override@JsonKey(name: 'blankId') final  int blankId;
@override final  String name;
@override@JsonKey() final  String category;
@override@JsonKey() final  String unit;
@override@JsonKey() final  double demand;
@override@JsonKey() final  double stock;
@override@JsonKey() final  double shortage;

/// Create a copy of BlankDemand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankDemandCopyWith<_BlankDemand> get copyWith => __$BlankDemandCopyWithImpl<_BlankDemand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankDemandToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankDemand&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.demand, demand) || other.demand == demand)&&(identical(other.stock, stock) || other.stock == stock)&&(identical(other.shortage, shortage) || other.shortage == shortage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,blankId,name,category,unit,demand,stock,shortage);

@override
String toString() {
  return 'BlankDemand(blankId: $blankId, name: $name, category: $category, unit: $unit, demand: $demand, stock: $stock, shortage: $shortage)';
}


}

/// @nodoc
abstract mixin class _$BlankDemandCopyWith<$Res> implements $BlankDemandCopyWith<$Res> {
  factory _$BlankDemandCopyWith(_BlankDemand value, $Res Function(_BlankDemand) _then) = __$BlankDemandCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'blankId') int blankId, String name, String category, String unit, double demand, double stock, double shortage
});




}
/// @nodoc
class __$BlankDemandCopyWithImpl<$Res>
    implements _$BlankDemandCopyWith<$Res> {
  __$BlankDemandCopyWithImpl(this._self, this._then);

  final _BlankDemand _self;
  final $Res Function(_BlankDemand) _then;

/// Create a copy of BlankDemand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? blankId = null,Object? name = null,Object? category = null,Object? unit = null,Object? demand = null,Object? stock = null,Object? shortage = null,}) {
  return _then(_BlankDemand(
blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,demand: null == demand ? _self.demand : demand // ignore: cast_nullable_to_non_nullable
as double,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as double,shortage: null == shortage ? _self.shortage : shortage // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BlankStockLog {

 int get id;@JsonKey(name: 'blankId') int get blankId;@JsonKey(name: 'quantityChange') double get quantityChange; String get type;@JsonKey(name: 'producedDate') String? get producedDate;@JsonKey(name: 'expiryDate') String? get expiryDate;@JsonKey(name: 'createdAt') String? get createdAt;
/// Create a copy of BlankStockLog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlankStockLogCopyWith<BlankStockLog> get copyWith => _$BlankStockLogCopyWithImpl<BlankStockLog>(this as BlankStockLog, _$identity);

  /// Serializes this BlankStockLog to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlankStockLog&&(identical(other.id, id) || other.id == id)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantityChange, quantityChange) || other.quantityChange == quantityChange)&&(identical(other.type, type) || other.type == type)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,blankId,quantityChange,type,producedDate,expiryDate,createdAt);

@override
String toString() {
  return 'BlankStockLog(id: $id, blankId: $blankId, quantityChange: $quantityChange, type: $type, producedDate: $producedDate, expiryDate: $expiryDate, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $BlankStockLogCopyWith<$Res>  {
  factory $BlankStockLogCopyWith(BlankStockLog value, $Res Function(BlankStockLog) _then) = _$BlankStockLogCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'blankId') int blankId,@JsonKey(name: 'quantityChange') double quantityChange, String type,@JsonKey(name: 'producedDate') String? producedDate,@JsonKey(name: 'expiryDate') String? expiryDate,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class _$BlankStockLogCopyWithImpl<$Res>
    implements $BlankStockLogCopyWith<$Res> {
  _$BlankStockLogCopyWithImpl(this._self, this._then);

  final BlankStockLog _self;
  final $Res Function(BlankStockLog) _then;

/// Create a copy of BlankStockLog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? blankId = null,Object? quantityChange = null,Object? type = null,Object? producedDate = freezed,Object? expiryDate = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantityChange: null == quantityChange ? _self.quantityChange : quantityChange // ignore: cast_nullable_to_non_nullable
as double,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,producedDate: freezed == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String?,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlankStockLog].
extension BlankStockLogPatterns on BlankStockLog {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlankStockLog value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlankStockLog() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlankStockLog value)  $default,){
final _that = this;
switch (_that) {
case _BlankStockLog():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlankStockLog value)?  $default,){
final _that = this;
switch (_that) {
case _BlankStockLog() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'blankId')  int blankId, @JsonKey(name: 'quantityChange')  double quantityChange,  String type, @JsonKey(name: 'producedDate')  String? producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlankStockLog() when $default != null:
return $default(_that.id,_that.blankId,_that.quantityChange,_that.type,_that.producedDate,_that.expiryDate,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'blankId')  int blankId, @JsonKey(name: 'quantityChange')  double quantityChange,  String type, @JsonKey(name: 'producedDate')  String? producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate, @JsonKey(name: 'createdAt')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _BlankStockLog():
return $default(_that.id,_that.blankId,_that.quantityChange,_that.type,_that.producedDate,_that.expiryDate,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'blankId')  int blankId, @JsonKey(name: 'quantityChange')  double quantityChange,  String type, @JsonKey(name: 'producedDate')  String? producedDate, @JsonKey(name: 'expiryDate')  String? expiryDate, @JsonKey(name: 'createdAt')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _BlankStockLog() when $default != null:
return $default(_that.id,_that.blankId,_that.quantityChange,_that.type,_that.producedDate,_that.expiryDate,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlankStockLog implements BlankStockLog {
  const _BlankStockLog({required this.id, @JsonKey(name: 'blankId') required this.blankId, @JsonKey(name: 'quantityChange') required this.quantityChange, required this.type, @JsonKey(name: 'producedDate') this.producedDate, @JsonKey(name: 'expiryDate') this.expiryDate, @JsonKey(name: 'createdAt') this.createdAt});
  factory _BlankStockLog.fromJson(Map<String, dynamic> json) => _$BlankStockLogFromJson(json);

@override final  int id;
@override@JsonKey(name: 'blankId') final  int blankId;
@override@JsonKey(name: 'quantityChange') final  double quantityChange;
@override final  String type;
@override@JsonKey(name: 'producedDate') final  String? producedDate;
@override@JsonKey(name: 'expiryDate') final  String? expiryDate;
@override@JsonKey(name: 'createdAt') final  String? createdAt;

/// Create a copy of BlankStockLog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlankStockLogCopyWith<_BlankStockLog> get copyWith => __$BlankStockLogCopyWithImpl<_BlankStockLog>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlankStockLogToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlankStockLog&&(identical(other.id, id) || other.id == id)&&(identical(other.blankId, blankId) || other.blankId == blankId)&&(identical(other.quantityChange, quantityChange) || other.quantityChange == quantityChange)&&(identical(other.type, type) || other.type == type)&&(identical(other.producedDate, producedDate) || other.producedDate == producedDate)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,blankId,quantityChange,type,producedDate,expiryDate,createdAt);

@override
String toString() {
  return 'BlankStockLog(id: $id, blankId: $blankId, quantityChange: $quantityChange, type: $type, producedDate: $producedDate, expiryDate: $expiryDate, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$BlankStockLogCopyWith<$Res> implements $BlankStockLogCopyWith<$Res> {
  factory _$BlankStockLogCopyWith(_BlankStockLog value, $Res Function(_BlankStockLog) _then) = __$BlankStockLogCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'blankId') int blankId,@JsonKey(name: 'quantityChange') double quantityChange, String type,@JsonKey(name: 'producedDate') String? producedDate,@JsonKey(name: 'expiryDate') String? expiryDate,@JsonKey(name: 'createdAt') String? createdAt
});




}
/// @nodoc
class __$BlankStockLogCopyWithImpl<$Res>
    implements _$BlankStockLogCopyWith<$Res> {
  __$BlankStockLogCopyWithImpl(this._self, this._then);

  final _BlankStockLog _self;
  final $Res Function(_BlankStockLog) _then;

/// Create a copy of BlankStockLog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? blankId = null,Object? quantityChange = null,Object? type = null,Object? producedDate = freezed,Object? expiryDate = freezed,Object? createdAt = freezed,}) {
  return _then(_BlankStockLog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,blankId: null == blankId ? _self.blankId : blankId // ignore: cast_nullable_to_non_nullable
as int,quantityChange: null == quantityChange ? _self.quantityChange : quantityChange // ignore: cast_nullable_to_non_nullable
as double,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,producedDate: freezed == producedDate ? _self.producedDate : producedDate // ignore: cast_nullable_to_non_nullable
as String?,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event_photo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EventPhoto {

 int get id;@JsonKey(name: 'event_id') int get eventId;@JsonKey(name: 'photo_id') int get photoId;@JsonKey(name: 'photo_hash') String get photoHash; String get tags; int get position;@JsonKey(name: 'created_at') String? get createdAt;
/// Create a copy of EventPhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPhotoCopyWith<EventPhoto> get copyWith => _$EventPhotoCopyWithImpl<EventPhoto>(this as EventPhoto, _$identity);

  /// Serializes this EventPhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.photoId, photoId) || other.photoId == photoId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,eventId,photoId,photoHash,tags,position,createdAt);

@override
String toString() {
  return 'EventPhoto(id: $id, eventId: $eventId, photoId: $photoId, photoHash: $photoHash, tags: $tags, position: $position, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $EventPhotoCopyWith<$Res>  {
  factory $EventPhotoCopyWith(EventPhoto value, $Res Function(EventPhoto) _then) = _$EventPhotoCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'event_id') int eventId,@JsonKey(name: 'photo_id') int photoId,@JsonKey(name: 'photo_hash') String photoHash, String tags, int position,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class _$EventPhotoCopyWithImpl<$Res>
    implements $EventPhotoCopyWith<$Res> {
  _$EventPhotoCopyWithImpl(this._self, this._then);

  final EventPhoto _self;
  final $Res Function(EventPhoto) _then;

/// Create a copy of EventPhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? eventId = null,Object? photoId = null,Object? photoHash = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as int,photoId: null == photoId ? _self.photoId : photoId // ignore: cast_nullable_to_non_nullable
as int,photoHash: null == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EventPhoto].
extension EventPhotoPatterns on EventPhoto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EventPhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EventPhoto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EventPhoto value)  $default,){
final _that = this;
switch (_that) {
case _EventPhoto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EventPhoto value)?  $default,){
final _that = this;
switch (_that) {
case _EventPhoto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'event_id')  int eventId, @JsonKey(name: 'photo_id')  int photoId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EventPhoto() when $default != null:
return $default(_that.id,_that.eventId,_that.photoId,_that.photoHash,_that.tags,_that.position,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'event_id')  int eventId, @JsonKey(name: 'photo_id')  int photoId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _EventPhoto():
return $default(_that.id,_that.eventId,_that.photoId,_that.photoHash,_that.tags,_that.position,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'event_id')  int eventId, @JsonKey(name: 'photo_id')  int photoId, @JsonKey(name: 'photo_hash')  String photoHash,  String tags,  int position, @JsonKey(name: 'created_at')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _EventPhoto() when $default != null:
return $default(_that.id,_that.eventId,_that.photoId,_that.photoHash,_that.tags,_that.position,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EventPhoto implements EventPhoto {
  const _EventPhoto({required this.id, @JsonKey(name: 'event_id') required this.eventId, @JsonKey(name: 'photo_id') required this.photoId, @JsonKey(name: 'photo_hash') required this.photoHash, this.tags = '', this.position = 0, @JsonKey(name: 'created_at') this.createdAt});
  factory _EventPhoto.fromJson(Map<String, dynamic> json) => _$EventPhotoFromJson(json);

@override final  int id;
@override@JsonKey(name: 'event_id') final  int eventId;
@override@JsonKey(name: 'photo_id') final  int photoId;
@override@JsonKey(name: 'photo_hash') final  String photoHash;
@override@JsonKey() final  String tags;
@override@JsonKey() final  int position;
@override@JsonKey(name: 'created_at') final  String? createdAt;

/// Create a copy of EventPhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EventPhotoCopyWith<_EventPhoto> get copyWith => __$EventPhotoCopyWithImpl<_EventPhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EventPhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EventPhoto&&(identical(other.id, id) || other.id == id)&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.photoId, photoId) || other.photoId == photoId)&&(identical(other.photoHash, photoHash) || other.photoHash == photoHash)&&(identical(other.tags, tags) || other.tags == tags)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,eventId,photoId,photoHash,tags,position,createdAt);

@override
String toString() {
  return 'EventPhoto(id: $id, eventId: $eventId, photoId: $photoId, photoHash: $photoHash, tags: $tags, position: $position, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$EventPhotoCopyWith<$Res> implements $EventPhotoCopyWith<$Res> {
  factory _$EventPhotoCopyWith(_EventPhoto value, $Res Function(_EventPhoto) _then) = __$EventPhotoCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'event_id') int eventId,@JsonKey(name: 'photo_id') int photoId,@JsonKey(name: 'photo_hash') String photoHash, String tags, int position,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class __$EventPhotoCopyWithImpl<$Res>
    implements _$EventPhotoCopyWith<$Res> {
  __$EventPhotoCopyWithImpl(this._self, this._then);

  final _EventPhoto _self;
  final $Res Function(_EventPhoto) _then;

/// Create a copy of EventPhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? eventId = null,Object? photoId = null,Object? photoHash = null,Object? tags = null,Object? position = null,Object? createdAt = freezed,}) {
  return _then(_EventPhoto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as int,photoId: null == photoId ? _self.photoId : photoId // ignore: cast_nullable_to_non_nullable
as int,photoHash: null == photoHash ? _self.photoHash : photoHash // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

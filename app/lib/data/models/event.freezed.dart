// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BakeryEvent {

 String get id; DateTime get timestamp; String get type; String get summary; String get loggedBy;
/// Create a copy of BakeryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BakeryEventCopyWith<BakeryEvent> get copyWith => _$BakeryEventCopyWithImpl<BakeryEvent>(this as BakeryEvent, _$identity);

  /// Serializes this BakeryEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BakeryEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.type, type) || other.type == type)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,timestamp,type,summary,loggedBy);

@override
String toString() {
  return 'BakeryEvent(id: $id, timestamp: $timestamp, type: $type, summary: $summary, loggedBy: $loggedBy)';
}


}

/// @nodoc
abstract mixin class $BakeryEventCopyWith<$Res>  {
  factory $BakeryEventCopyWith(BakeryEvent value, $Res Function(BakeryEvent) _then) = _$BakeryEventCopyWithImpl;
@useResult
$Res call({
 String id, DateTime timestamp, String type, String summary, String loggedBy
});




}
/// @nodoc
class _$BakeryEventCopyWithImpl<$Res>
    implements $BakeryEventCopyWith<$Res> {
  _$BakeryEventCopyWithImpl(this._self, this._then);

  final BakeryEvent _self;
  final $Res Function(BakeryEvent) _then;

/// Create a copy of BakeryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? timestamp = null,Object? type = null,Object? summary = null,Object? loggedBy = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BakeryEvent].
extension BakeryEventPatterns on BakeryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BakeryEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BakeryEvent value)  $default,){
final _that = this;
switch (_that) {
case _BakeryEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BakeryEvent value)?  $default,){
final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime timestamp,  String type,  String summary,  String loggedBy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.loggedBy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime timestamp,  String type,  String summary,  String loggedBy)  $default,) {final _that = this;
switch (_that) {
case _BakeryEvent():
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.loggedBy);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime timestamp,  String type,  String summary,  String loggedBy)?  $default,) {final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.loggedBy);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BakeryEvent implements BakeryEvent {
  const _BakeryEvent({required this.id, required this.timestamp, this.type = 'note', required this.summary, this.loggedBy = ''});
  factory _BakeryEvent.fromJson(Map<String, dynamic> json) => _$BakeryEventFromJson(json);

@override final  String id;
@override final  DateTime timestamp;
@override@JsonKey() final  String type;
@override final  String summary;
@override@JsonKey() final  String loggedBy;

/// Create a copy of BakeryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BakeryEventCopyWith<_BakeryEvent> get copyWith => __$BakeryEventCopyWithImpl<_BakeryEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BakeryEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BakeryEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.type, type) || other.type == type)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,timestamp,type,summary,loggedBy);

@override
String toString() {
  return 'BakeryEvent(id: $id, timestamp: $timestamp, type: $type, summary: $summary, loggedBy: $loggedBy)';
}


}

/// @nodoc
abstract mixin class _$BakeryEventCopyWith<$Res> implements $BakeryEventCopyWith<$Res> {
  factory _$BakeryEventCopyWith(_BakeryEvent value, $Res Function(_BakeryEvent) _then) = __$BakeryEventCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime timestamp, String type, String summary, String loggedBy
});




}
/// @nodoc
class __$BakeryEventCopyWithImpl<$Res>
    implements _$BakeryEventCopyWith<$Res> {
  __$BakeryEventCopyWithImpl(this._self, this._then);

  final _BakeryEvent _self;
  final $Res Function(_BakeryEvent) _then;

/// Create a copy of BakeryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? timestamp = null,Object? type = null,Object? summary = null,Object? loggedBy = null,}) {
  return _then(_BakeryEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

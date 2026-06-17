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

 int get id;@JsonKey(fromJson: _timestampFromJson) DateTime get timestamp; String get type; String get summary; List<String> get tags;@JsonKey(name: 'logged_by') String get loggedBy; String get source; Map<String, dynamic> get data;@JsonKey(name: 'order_id') int? get orderId;
/// Create a copy of BakeryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BakeryEventCopyWith<BakeryEvent> get copyWith => _$BakeryEventCopyWithImpl<BakeryEvent>(this as BakeryEvent, _$identity);

  /// Serializes this BakeryEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BakeryEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.type, type) || other.type == type)&&(identical(other.summary, summary) || other.summary == summary)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.orderId, orderId) || other.orderId == orderId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,timestamp,type,summary,const DeepCollectionEquality().hash(tags),loggedBy,source,const DeepCollectionEquality().hash(data),orderId);

@override
String toString() {
  return 'BakeryEvent(id: $id, timestamp: $timestamp, type: $type, summary: $summary, tags: $tags, loggedBy: $loggedBy, source: $source, data: $data, orderId: $orderId)';
}


}

/// @nodoc
abstract mixin class $BakeryEventCopyWith<$Res>  {
  factory $BakeryEventCopyWith(BakeryEvent value, $Res Function(BakeryEvent) _then) = _$BakeryEventCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(fromJson: _timestampFromJson) DateTime timestamp, String type, String summary, List<String> tags,@JsonKey(name: 'logged_by') String loggedBy, String source, Map<String, dynamic> data,@JsonKey(name: 'order_id') int? orderId
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? timestamp = null,Object? type = null,Object? summary = null,Object? tags = null,Object? loggedBy = null,Object? source = null,Object? data = null,Object? orderId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,orderId: freezed == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as int?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(fromJson: _timestampFromJson)  DateTime timestamp,  String type,  String summary,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  Map<String, dynamic> data, @JsonKey(name: 'order_id')  int? orderId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.tags,_that.loggedBy,_that.source,_that.data,_that.orderId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(fromJson: _timestampFromJson)  DateTime timestamp,  String type,  String summary,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  Map<String, dynamic> data, @JsonKey(name: 'order_id')  int? orderId)  $default,) {final _that = this;
switch (_that) {
case _BakeryEvent():
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.tags,_that.loggedBy,_that.source,_that.data,_that.orderId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(fromJson: _timestampFromJson)  DateTime timestamp,  String type,  String summary,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  Map<String, dynamic> data, @JsonKey(name: 'order_id')  int? orderId)?  $default,) {final _that = this;
switch (_that) {
case _BakeryEvent() when $default != null:
return $default(_that.id,_that.timestamp,_that.type,_that.summary,_that.tags,_that.loggedBy,_that.source,_that.data,_that.orderId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BakeryEvent implements BakeryEvent {
  const _BakeryEvent({required this.id, @JsonKey(fromJson: _timestampFromJson) required this.timestamp, this.type = 'note', required this.summary, final  List<String> tags = const <String>[], @JsonKey(name: 'logged_by') this.loggedBy = '', this.source = 'app', final  Map<String, dynamic> data = const <String, dynamic>{}, @JsonKey(name: 'order_id') this.orderId}): _tags = tags,_data = data;
  factory _BakeryEvent.fromJson(Map<String, dynamic> json) => _$BakeryEventFromJson(json);

@override final  int id;
@override@JsonKey(fromJson: _timestampFromJson) final  DateTime timestamp;
@override@JsonKey() final  String type;
@override final  String summary;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey(name: 'logged_by') final  String loggedBy;
@override@JsonKey() final  String source;
 final  Map<String, dynamic> _data;
@override@JsonKey() Map<String, dynamic> get data {
  if (_data is EqualUnmodifiableMapView) return _data;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_data);
}

@override@JsonKey(name: 'order_id') final  int? orderId;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BakeryEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.type, type) || other.type == type)&&(identical(other.summary, summary) || other.summary == summary)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other._data, _data)&&(identical(other.orderId, orderId) || other.orderId == orderId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,timestamp,type,summary,const DeepCollectionEquality().hash(_tags),loggedBy,source,const DeepCollectionEquality().hash(_data),orderId);

@override
String toString() {
  return 'BakeryEvent(id: $id, timestamp: $timestamp, type: $type, summary: $summary, tags: $tags, loggedBy: $loggedBy, source: $source, data: $data, orderId: $orderId)';
}


}

/// @nodoc
abstract mixin class _$BakeryEventCopyWith<$Res> implements $BakeryEventCopyWith<$Res> {
  factory _$BakeryEventCopyWith(_BakeryEvent value, $Res Function(_BakeryEvent) _then) = __$BakeryEventCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(fromJson: _timestampFromJson) DateTime timestamp, String type, String summary, List<String> tags,@JsonKey(name: 'logged_by') String loggedBy, String source, Map<String, dynamic> data,@JsonKey(name: 'order_id') int? orderId
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? timestamp = null,Object? type = null,Object? summary = null,Object? tags = null,Object? loggedBy = null,Object? source = null,Object? data = null,Object? orderId = freezed,}) {
  return _then(_BakeryEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self._data : data // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,orderId: freezed == orderId ? _self.orderId : orderId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on

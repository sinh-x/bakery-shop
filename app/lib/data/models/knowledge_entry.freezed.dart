// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'knowledge_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$KnowledgeEntry {

 int get id; String get title; String get content; String get type; List<String> get tags;@JsonKey(name: 'logged_by') String get loggedBy; String get source; DateTime get createdAt; DateTime get updatedAt; bool get pinned;@JsonKey(name: 'pinned_at') DateTime? get pinnedAt; List<KnowledgePhoto> get photos;
/// Create a copy of KnowledgeEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KnowledgeEntryCopyWith<KnowledgeEntry> get copyWith => _$KnowledgeEntryCopyWithImpl<KnowledgeEntry>(this as KnowledgeEntry, _$identity);

  /// Serializes this KnowledgeEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KnowledgeEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.content, content) || other.content == content)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.pinnedAt, pinnedAt) || other.pinnedAt == pinnedAt)&&const DeepCollectionEquality().equals(other.photos, photos));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,content,type,const DeepCollectionEquality().hash(tags),loggedBy,source,createdAt,updatedAt,pinned,pinnedAt,const DeepCollectionEquality().hash(photos));

@override
String toString() {
  return 'KnowledgeEntry(id: $id, title: $title, content: $content, type: $type, tags: $tags, loggedBy: $loggedBy, source: $source, createdAt: $createdAt, updatedAt: $updatedAt, pinned: $pinned, pinnedAt: $pinnedAt, photos: $photos)';
}


}

/// @nodoc
abstract mixin class $KnowledgeEntryCopyWith<$Res>  {
  factory $KnowledgeEntryCopyWith(KnowledgeEntry value, $Res Function(KnowledgeEntry) _then) = _$KnowledgeEntryCopyWithImpl;
@useResult
$Res call({
 int id, String title, String content, String type, List<String> tags,@JsonKey(name: 'logged_by') String loggedBy, String source, DateTime createdAt, DateTime updatedAt, bool pinned,@JsonKey(name: 'pinned_at') DateTime? pinnedAt, List<KnowledgePhoto> photos
});




}
/// @nodoc
class _$KnowledgeEntryCopyWithImpl<$Res>
    implements $KnowledgeEntryCopyWith<$Res> {
  _$KnowledgeEntryCopyWithImpl(this._self, this._then);

  final KnowledgeEntry _self;
  final $Res Function(KnowledgeEntry) _then;

/// Create a copy of KnowledgeEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? content = null,Object? type = null,Object? tags = null,Object? loggedBy = null,Object? source = null,Object? createdAt = null,Object? updatedAt = null,Object? pinned = null,Object? pinnedAt = freezed,Object? photos = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,pinnedAt: freezed == pinnedAt ? _self.pinnedAt : pinnedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,photos: null == photos ? _self.photos : photos // ignore: cast_nullable_to_non_nullable
as List<KnowledgePhoto>,
  ));
}

}


/// Adds pattern-matching-related methods to [KnowledgeEntry].
extension KnowledgeEntryPatterns on KnowledgeEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KnowledgeEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KnowledgeEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KnowledgeEntry value)  $default,){
final _that = this;
switch (_that) {
case _KnowledgeEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KnowledgeEntry value)?  $default,){
final _that = this;
switch (_that) {
case _KnowledgeEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String title,  String content,  String type,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  DateTime createdAt,  DateTime updatedAt,  bool pinned, @JsonKey(name: 'pinned_at')  DateTime? pinnedAt,  List<KnowledgePhoto> photos)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KnowledgeEntry() when $default != null:
return $default(_that.id,_that.title,_that.content,_that.type,_that.tags,_that.loggedBy,_that.source,_that.createdAt,_that.updatedAt,_that.pinned,_that.pinnedAt,_that.photos);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String title,  String content,  String type,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  DateTime createdAt,  DateTime updatedAt,  bool pinned, @JsonKey(name: 'pinned_at')  DateTime? pinnedAt,  List<KnowledgePhoto> photos)  $default,) {final _that = this;
switch (_that) {
case _KnowledgeEntry():
return $default(_that.id,_that.title,_that.content,_that.type,_that.tags,_that.loggedBy,_that.source,_that.createdAt,_that.updatedAt,_that.pinned,_that.pinnedAt,_that.photos);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String title,  String content,  String type,  List<String> tags, @JsonKey(name: 'logged_by')  String loggedBy,  String source,  DateTime createdAt,  DateTime updatedAt,  bool pinned, @JsonKey(name: 'pinned_at')  DateTime? pinnedAt,  List<KnowledgePhoto> photos)?  $default,) {final _that = this;
switch (_that) {
case _KnowledgeEntry() when $default != null:
return $default(_that.id,_that.title,_that.content,_that.type,_that.tags,_that.loggedBy,_that.source,_that.createdAt,_that.updatedAt,_that.pinned,_that.pinnedAt,_that.photos);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _KnowledgeEntry implements KnowledgeEntry {
  const _KnowledgeEntry({required this.id, required this.title, this.content = '', this.type = 'note', final  List<String> tags = const <String>[], @JsonKey(name: 'logged_by') this.loggedBy = '', this.source = 'app', required this.createdAt, required this.updatedAt, this.pinned = false, @JsonKey(name: 'pinned_at') this.pinnedAt, final  List<KnowledgePhoto> photos = const <KnowledgePhoto>[]}): _tags = tags,_photos = photos;
  factory _KnowledgeEntry.fromJson(Map<String, dynamic> json) => _$KnowledgeEntryFromJson(json);

@override final  int id;
@override final  String title;
@override@JsonKey() final  String content;
@override@JsonKey() final  String type;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey(name: 'logged_by') final  String loggedBy;
@override@JsonKey() final  String source;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  bool pinned;
@override@JsonKey(name: 'pinned_at') final  DateTime? pinnedAt;
 final  List<KnowledgePhoto> _photos;
@override@JsonKey() List<KnowledgePhoto> get photos {
  if (_photos is EqualUnmodifiableListView) return _photos;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_photos);
}


/// Create a copy of KnowledgeEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KnowledgeEntryCopyWith<_KnowledgeEntry> get copyWith => __$KnowledgeEntryCopyWithImpl<_KnowledgeEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$KnowledgeEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KnowledgeEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.content, content) || other.content == content)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.loggedBy, loggedBy) || other.loggedBy == loggedBy)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.pinnedAt, pinnedAt) || other.pinnedAt == pinnedAt)&&const DeepCollectionEquality().equals(other._photos, _photos));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,content,type,const DeepCollectionEquality().hash(_tags),loggedBy,source,createdAt,updatedAt,pinned,pinnedAt,const DeepCollectionEquality().hash(_photos));

@override
String toString() {
  return 'KnowledgeEntry(id: $id, title: $title, content: $content, type: $type, tags: $tags, loggedBy: $loggedBy, source: $source, createdAt: $createdAt, updatedAt: $updatedAt, pinned: $pinned, pinnedAt: $pinnedAt, photos: $photos)';
}


}

/// @nodoc
abstract mixin class _$KnowledgeEntryCopyWith<$Res> implements $KnowledgeEntryCopyWith<$Res> {
  factory _$KnowledgeEntryCopyWith(_KnowledgeEntry value, $Res Function(_KnowledgeEntry) _then) = __$KnowledgeEntryCopyWithImpl;
@override @useResult
$Res call({
 int id, String title, String content, String type, List<String> tags,@JsonKey(name: 'logged_by') String loggedBy, String source, DateTime createdAt, DateTime updatedAt, bool pinned,@JsonKey(name: 'pinned_at') DateTime? pinnedAt, List<KnowledgePhoto> photos
});




}
/// @nodoc
class __$KnowledgeEntryCopyWithImpl<$Res>
    implements _$KnowledgeEntryCopyWith<$Res> {
  __$KnowledgeEntryCopyWithImpl(this._self, this._then);

  final _KnowledgeEntry _self;
  final $Res Function(_KnowledgeEntry) _then;

/// Create a copy of KnowledgeEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? content = null,Object? type = null,Object? tags = null,Object? loggedBy = null,Object? source = null,Object? createdAt = null,Object? updatedAt = null,Object? pinned = null,Object? pinnedAt = freezed,Object? photos = null,}) {
  return _then(_KnowledgeEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,loggedBy: null == loggedBy ? _self.loggedBy : loggedBy // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,pinnedAt: freezed == pinnedAt ? _self.pinnedAt : pinnedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,photos: null == photos ? _self._photos : photos // ignore: cast_nullable_to_non_nullable
as List<KnowledgePhoto>,
  ));
}


}


/// @nodoc
mixin _$KnowledgePhoto {

 String get hash; String get url; String get caption; int get position;
/// Create a copy of KnowledgePhoto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KnowledgePhotoCopyWith<KnowledgePhoto> get copyWith => _$KnowledgePhotoCopyWithImpl<KnowledgePhoto>(this as KnowledgePhoto, _$identity);

  /// Serializes this KnowledgePhoto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KnowledgePhoto&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.url, url) || other.url == url)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.position, position) || other.position == position));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,hash,url,caption,position);

@override
String toString() {
  return 'KnowledgePhoto(hash: $hash, url: $url, caption: $caption, position: $position)';
}


}

/// @nodoc
abstract mixin class $KnowledgePhotoCopyWith<$Res>  {
  factory $KnowledgePhotoCopyWith(KnowledgePhoto value, $Res Function(KnowledgePhoto) _then) = _$KnowledgePhotoCopyWithImpl;
@useResult
$Res call({
 String hash, String url, String caption, int position
});




}
/// @nodoc
class _$KnowledgePhotoCopyWithImpl<$Res>
    implements $KnowledgePhotoCopyWith<$Res> {
  _$KnowledgePhotoCopyWithImpl(this._self, this._then);

  final KnowledgePhoto _self;
  final $Res Function(KnowledgePhoto) _then;

/// Create a copy of KnowledgePhoto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hash = null,Object? url = null,Object? caption = null,Object? position = null,}) {
  return _then(_self.copyWith(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [KnowledgePhoto].
extension KnowledgePhotoPatterns on KnowledgePhoto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KnowledgePhoto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KnowledgePhoto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KnowledgePhoto value)  $default,){
final _that = this;
switch (_that) {
case _KnowledgePhoto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KnowledgePhoto value)?  $default,){
final _that = this;
switch (_that) {
case _KnowledgePhoto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String hash,  String url,  String caption,  int position)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KnowledgePhoto() when $default != null:
return $default(_that.hash,_that.url,_that.caption,_that.position);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String hash,  String url,  String caption,  int position)  $default,) {final _that = this;
switch (_that) {
case _KnowledgePhoto():
return $default(_that.hash,_that.url,_that.caption,_that.position);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String hash,  String url,  String caption,  int position)?  $default,) {final _that = this;
switch (_that) {
case _KnowledgePhoto() when $default != null:
return $default(_that.hash,_that.url,_that.caption,_that.position);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _KnowledgePhoto implements KnowledgePhoto {
  const _KnowledgePhoto({required this.hash, required this.url, this.caption = '', this.position = 0});
  factory _KnowledgePhoto.fromJson(Map<String, dynamic> json) => _$KnowledgePhotoFromJson(json);

@override final  String hash;
@override final  String url;
@override@JsonKey() final  String caption;
@override@JsonKey() final  int position;

/// Create a copy of KnowledgePhoto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KnowledgePhotoCopyWith<_KnowledgePhoto> get copyWith => __$KnowledgePhotoCopyWithImpl<_KnowledgePhoto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$KnowledgePhotoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KnowledgePhoto&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.url, url) || other.url == url)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.position, position) || other.position == position));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,hash,url,caption,position);

@override
String toString() {
  return 'KnowledgePhoto(hash: $hash, url: $url, caption: $caption, position: $position)';
}


}

/// @nodoc
abstract mixin class _$KnowledgePhotoCopyWith<$Res> implements $KnowledgePhotoCopyWith<$Res> {
  factory _$KnowledgePhotoCopyWith(_KnowledgePhoto value, $Res Function(_KnowledgePhoto) _then) = __$KnowledgePhotoCopyWithImpl;
@override @useResult
$Res call({
 String hash, String url, String caption, int position
});




}
/// @nodoc
class __$KnowledgePhotoCopyWithImpl<$Res>
    implements _$KnowledgePhotoCopyWith<$Res> {
  __$KnowledgePhotoCopyWithImpl(this._self, this._then);

  final _KnowledgePhoto _self;
  final $Res Function(_KnowledgePhoto) _then;

/// Create a copy of KnowledgePhoto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hash = null,Object? url = null,Object? caption = null,Object? position = null,}) {
  return _then(_KnowledgePhoto(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,caption: null == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on

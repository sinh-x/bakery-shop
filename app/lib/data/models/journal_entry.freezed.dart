// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'journal_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$JournalLine {

 String get id;@JsonKey(name: 'journalEntryId') String get journalEntryId;@JsonKey(name: 'accountId') String get accountId; double get debit; double get credit; String get description;@JsonKey(name: 'accountCode') String? get accountCode;@JsonKey(name: 'accountName') String? get accountName;@JsonKey(name: 'accountType') String? get accountType;
/// Create a copy of JournalLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JournalLineCopyWith<JournalLine> get copyWith => _$JournalLineCopyWithImpl<JournalLine>(this as JournalLine, _$identity);

  /// Serializes this JournalLine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JournalLine&&(identical(other.id, id) || other.id == id)&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.debit, debit) || other.debit == debit)&&(identical(other.credit, credit) || other.credit == credit)&&(identical(other.description, description) || other.description == description)&&(identical(other.accountCode, accountCode) || other.accountCode == accountCode)&&(identical(other.accountName, accountName) || other.accountName == accountName)&&(identical(other.accountType, accountType) || other.accountType == accountType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,journalEntryId,accountId,debit,credit,description,accountCode,accountName,accountType);

@override
String toString() {
  return 'JournalLine(id: $id, journalEntryId: $journalEntryId, accountId: $accountId, debit: $debit, credit: $credit, description: $description, accountCode: $accountCode, accountName: $accountName, accountType: $accountType)';
}


}

/// @nodoc
abstract mixin class $JournalLineCopyWith<$Res>  {
  factory $JournalLineCopyWith(JournalLine value, $Res Function(JournalLine) _then) = _$JournalLineCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'journalEntryId') String journalEntryId,@JsonKey(name: 'accountId') String accountId, double debit, double credit, String description,@JsonKey(name: 'accountCode') String? accountCode,@JsonKey(name: 'accountName') String? accountName,@JsonKey(name: 'accountType') String? accountType
});




}
/// @nodoc
class _$JournalLineCopyWithImpl<$Res>
    implements $JournalLineCopyWith<$Res> {
  _$JournalLineCopyWithImpl(this._self, this._then);

  final JournalLine _self;
  final $Res Function(JournalLine) _then;

/// Create a copy of JournalLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? journalEntryId = null,Object? accountId = null,Object? debit = null,Object? credit = null,Object? description = null,Object? accountCode = freezed,Object? accountName = freezed,Object? accountType = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as double,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as double,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,accountCode: freezed == accountCode ? _self.accountCode : accountCode // ignore: cast_nullable_to_non_nullable
as String?,accountName: freezed == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as String?,accountType: freezed == accountType ? _self.accountType : accountType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [JournalLine].
extension JournalLinePatterns on JournalLine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JournalLine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JournalLine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JournalLine value)  $default,){
final _that = this;
switch (_that) {
case _JournalLine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JournalLine value)?  $default,){
final _that = this;
switch (_that) {
case _JournalLine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'journalEntryId')  String journalEntryId, @JsonKey(name: 'accountId')  String accountId,  double debit,  double credit,  String description, @JsonKey(name: 'accountCode')  String? accountCode, @JsonKey(name: 'accountName')  String? accountName, @JsonKey(name: 'accountType')  String? accountType)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JournalLine() when $default != null:
return $default(_that.id,_that.journalEntryId,_that.accountId,_that.debit,_that.credit,_that.description,_that.accountCode,_that.accountName,_that.accountType);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'journalEntryId')  String journalEntryId, @JsonKey(name: 'accountId')  String accountId,  double debit,  double credit,  String description, @JsonKey(name: 'accountCode')  String? accountCode, @JsonKey(name: 'accountName')  String? accountName, @JsonKey(name: 'accountType')  String? accountType)  $default,) {final _that = this;
switch (_that) {
case _JournalLine():
return $default(_that.id,_that.journalEntryId,_that.accountId,_that.debit,_that.credit,_that.description,_that.accountCode,_that.accountName,_that.accountType);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'journalEntryId')  String journalEntryId, @JsonKey(name: 'accountId')  String accountId,  double debit,  double credit,  String description, @JsonKey(name: 'accountCode')  String? accountCode, @JsonKey(name: 'accountName')  String? accountName, @JsonKey(name: 'accountType')  String? accountType)?  $default,) {final _that = this;
switch (_that) {
case _JournalLine() when $default != null:
return $default(_that.id,_that.journalEntryId,_that.accountId,_that.debit,_that.credit,_that.description,_that.accountCode,_that.accountName,_that.accountType);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JournalLine implements JournalLine {
  const _JournalLine({required this.id, @JsonKey(name: 'journalEntryId') required this.journalEntryId, @JsonKey(name: 'accountId') required this.accountId, this.debit = 0.0, this.credit = 0.0, this.description = '', @JsonKey(name: 'accountCode') this.accountCode, @JsonKey(name: 'accountName') this.accountName, @JsonKey(name: 'accountType') this.accountType});
  factory _JournalLine.fromJson(Map<String, dynamic> json) => _$JournalLineFromJson(json);

@override final  String id;
@override@JsonKey(name: 'journalEntryId') final  String journalEntryId;
@override@JsonKey(name: 'accountId') final  String accountId;
@override@JsonKey() final  double debit;
@override@JsonKey() final  double credit;
@override@JsonKey() final  String description;
@override@JsonKey(name: 'accountCode') final  String? accountCode;
@override@JsonKey(name: 'accountName') final  String? accountName;
@override@JsonKey(name: 'accountType') final  String? accountType;

/// Create a copy of JournalLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JournalLineCopyWith<_JournalLine> get copyWith => __$JournalLineCopyWithImpl<_JournalLine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JournalLineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JournalLine&&(identical(other.id, id) || other.id == id)&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.debit, debit) || other.debit == debit)&&(identical(other.credit, credit) || other.credit == credit)&&(identical(other.description, description) || other.description == description)&&(identical(other.accountCode, accountCode) || other.accountCode == accountCode)&&(identical(other.accountName, accountName) || other.accountName == accountName)&&(identical(other.accountType, accountType) || other.accountType == accountType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,journalEntryId,accountId,debit,credit,description,accountCode,accountName,accountType);

@override
String toString() {
  return 'JournalLine(id: $id, journalEntryId: $journalEntryId, accountId: $accountId, debit: $debit, credit: $credit, description: $description, accountCode: $accountCode, accountName: $accountName, accountType: $accountType)';
}


}

/// @nodoc
abstract mixin class _$JournalLineCopyWith<$Res> implements $JournalLineCopyWith<$Res> {
  factory _$JournalLineCopyWith(_JournalLine value, $Res Function(_JournalLine) _then) = __$JournalLineCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'journalEntryId') String journalEntryId,@JsonKey(name: 'accountId') String accountId, double debit, double credit, String description,@JsonKey(name: 'accountCode') String? accountCode,@JsonKey(name: 'accountName') String? accountName,@JsonKey(name: 'accountType') String? accountType
});




}
/// @nodoc
class __$JournalLineCopyWithImpl<$Res>
    implements _$JournalLineCopyWith<$Res> {
  __$JournalLineCopyWithImpl(this._self, this._then);

  final _JournalLine _self;
  final $Res Function(_JournalLine) _then;

/// Create a copy of JournalLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? journalEntryId = null,Object? accountId = null,Object? debit = null,Object? credit = null,Object? description = null,Object? accountCode = freezed,Object? accountName = freezed,Object? accountType = freezed,}) {
  return _then(_JournalLine(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as double,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as double,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,accountCode: freezed == accountCode ? _self.accountCode : accountCode // ignore: cast_nullable_to_non_nullable
as String?,accountName: freezed == accountName ? _self.accountName : accountName // ignore: cast_nullable_to_non_nullable
as String?,accountType: freezed == accountType ? _self.accountType : accountType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$JournalEntry {

 String get id; String get description;@JsonKey(name: 'sourceType') String get sourceType;@JsonKey(name: 'sourceId') String? get sourceId;@JsonKey(name: 'lockedAt', fromJson: parseApiDateTime) DateTime? get lockedAt;@JsonKey(name: 'lockedBy') String get lockedBy;@JsonKey(name: 'createdAt', fromJson: parseApiDateTime) DateTime? get createdAt;@JsonKey(name: 'transactionDate') String? get transactionDate; List<JournalLine> get lines;
/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JournalEntryCopyWith<JournalEntry> get copyWith => _$JournalEntryCopyWithImpl<JournalEntry>(this as JournalEntry, _$identity);

  /// Serializes this JournalEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JournalEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.description, description) || other.description == description)&&(identical(other.sourceType, sourceType) || other.sourceType == sourceType)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.lockedAt, lockedAt) || other.lockedAt == lockedAt)&&(identical(other.lockedBy, lockedBy) || other.lockedBy == lockedBy)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.transactionDate, transactionDate) || other.transactionDate == transactionDate)&&const DeepCollectionEquality().equals(other.lines, lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,description,sourceType,sourceId,lockedAt,lockedBy,createdAt,transactionDate,const DeepCollectionEquality().hash(lines));

@override
String toString() {
  return 'JournalEntry(id: $id, description: $description, sourceType: $sourceType, sourceId: $sourceId, lockedAt: $lockedAt, lockedBy: $lockedBy, createdAt: $createdAt, transactionDate: $transactionDate, lines: $lines)';
}


}

/// @nodoc
abstract mixin class $JournalEntryCopyWith<$Res>  {
  factory $JournalEntryCopyWith(JournalEntry value, $Res Function(JournalEntry) _then) = _$JournalEntryCopyWithImpl;
@useResult
$Res call({
 String id, String description,@JsonKey(name: 'sourceType') String sourceType,@JsonKey(name: 'sourceId') String? sourceId,@JsonKey(name: 'lockedAt', fromJson: parseApiDateTime) DateTime? lockedAt,@JsonKey(name: 'lockedBy') String lockedBy,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime) DateTime? createdAt,@JsonKey(name: 'transactionDate') String? transactionDate, List<JournalLine> lines
});




}
/// @nodoc
class _$JournalEntryCopyWithImpl<$Res>
    implements $JournalEntryCopyWith<$Res> {
  _$JournalEntryCopyWithImpl(this._self, this._then);

  final JournalEntry _self;
  final $Res Function(JournalEntry) _then;

/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? description = null,Object? sourceType = null,Object? sourceId = freezed,Object? lockedAt = freezed,Object? lockedBy = null,Object? createdAt = freezed,Object? transactionDate = freezed,Object? lines = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,sourceType: null == sourceType ? _self.sourceType : sourceType // ignore: cast_nullable_to_non_nullable
as String,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,lockedAt: freezed == lockedAt ? _self.lockedAt : lockedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lockedBy: null == lockedBy ? _self.lockedBy : lockedBy // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,transactionDate: freezed == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as List<JournalLine>,
  ));
}

}


/// Adds pattern-matching-related methods to [JournalEntry].
extension JournalEntryPatterns on JournalEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JournalEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JournalEntry value)  $default,){
final _that = this;
switch (_that) {
case _JournalEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JournalEntry value)?  $default,){
final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String description, @JsonKey(name: 'sourceType')  String sourceType, @JsonKey(name: 'sourceId')  String? sourceId, @JsonKey(name: 'lockedAt', fromJson: parseApiDateTime)  DateTime? lockedAt, @JsonKey(name: 'lockedBy')  String lockedBy, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime)  DateTime? createdAt, @JsonKey(name: 'transactionDate')  String? transactionDate,  List<JournalLine> lines)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
return $default(_that.id,_that.description,_that.sourceType,_that.sourceId,_that.lockedAt,_that.lockedBy,_that.createdAt,_that.transactionDate,_that.lines);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String description, @JsonKey(name: 'sourceType')  String sourceType, @JsonKey(name: 'sourceId')  String? sourceId, @JsonKey(name: 'lockedAt', fromJson: parseApiDateTime)  DateTime? lockedAt, @JsonKey(name: 'lockedBy')  String lockedBy, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime)  DateTime? createdAt, @JsonKey(name: 'transactionDate')  String? transactionDate,  List<JournalLine> lines)  $default,) {final _that = this;
switch (_that) {
case _JournalEntry():
return $default(_that.id,_that.description,_that.sourceType,_that.sourceId,_that.lockedAt,_that.lockedBy,_that.createdAt,_that.transactionDate,_that.lines);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String description, @JsonKey(name: 'sourceType')  String sourceType, @JsonKey(name: 'sourceId')  String? sourceId, @JsonKey(name: 'lockedAt', fromJson: parseApiDateTime)  DateTime? lockedAt, @JsonKey(name: 'lockedBy')  String lockedBy, @JsonKey(name: 'createdAt', fromJson: parseApiDateTime)  DateTime? createdAt, @JsonKey(name: 'transactionDate')  String? transactionDate,  List<JournalLine> lines)?  $default,) {final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
return $default(_that.id,_that.description,_that.sourceType,_that.sourceId,_that.lockedAt,_that.lockedBy,_that.createdAt,_that.transactionDate,_that.lines);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JournalEntry implements JournalEntry {
  const _JournalEntry({required this.id, this.description = '', @JsonKey(name: 'sourceType') this.sourceType = '', @JsonKey(name: 'sourceId') this.sourceId, @JsonKey(name: 'lockedAt', fromJson: parseApiDateTime) this.lockedAt, @JsonKey(name: 'lockedBy') this.lockedBy = '', @JsonKey(name: 'createdAt', fromJson: parseApiDateTime) this.createdAt, @JsonKey(name: 'transactionDate') this.transactionDate, final  List<JournalLine> lines = const <JournalLine>[]}): _lines = lines;
  factory _JournalEntry.fromJson(Map<String, dynamic> json) => _$JournalEntryFromJson(json);

@override final  String id;
@override@JsonKey() final  String description;
@override@JsonKey(name: 'sourceType') final  String sourceType;
@override@JsonKey(name: 'sourceId') final  String? sourceId;
@override@JsonKey(name: 'lockedAt', fromJson: parseApiDateTime) final  DateTime? lockedAt;
@override@JsonKey(name: 'lockedBy') final  String lockedBy;
@override@JsonKey(name: 'createdAt', fromJson: parseApiDateTime) final  DateTime? createdAt;
@override@JsonKey(name: 'transactionDate') final  String? transactionDate;
 final  List<JournalLine> _lines;
@override@JsonKey() List<JournalLine> get lines {
  if (_lines is EqualUnmodifiableListView) return _lines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lines);
}


/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JournalEntryCopyWith<_JournalEntry> get copyWith => __$JournalEntryCopyWithImpl<_JournalEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JournalEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JournalEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.description, description) || other.description == description)&&(identical(other.sourceType, sourceType) || other.sourceType == sourceType)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.lockedAt, lockedAt) || other.lockedAt == lockedAt)&&(identical(other.lockedBy, lockedBy) || other.lockedBy == lockedBy)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.transactionDate, transactionDate) || other.transactionDate == transactionDate)&&const DeepCollectionEquality().equals(other._lines, _lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,description,sourceType,sourceId,lockedAt,lockedBy,createdAt,transactionDate,const DeepCollectionEquality().hash(_lines));

@override
String toString() {
  return 'JournalEntry(id: $id, description: $description, sourceType: $sourceType, sourceId: $sourceId, lockedAt: $lockedAt, lockedBy: $lockedBy, createdAt: $createdAt, transactionDate: $transactionDate, lines: $lines)';
}


}

/// @nodoc
abstract mixin class _$JournalEntryCopyWith<$Res> implements $JournalEntryCopyWith<$Res> {
  factory _$JournalEntryCopyWith(_JournalEntry value, $Res Function(_JournalEntry) _then) = __$JournalEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String description,@JsonKey(name: 'sourceType') String sourceType,@JsonKey(name: 'sourceId') String? sourceId,@JsonKey(name: 'lockedAt', fromJson: parseApiDateTime) DateTime? lockedAt,@JsonKey(name: 'lockedBy') String lockedBy,@JsonKey(name: 'createdAt', fromJson: parseApiDateTime) DateTime? createdAt,@JsonKey(name: 'transactionDate') String? transactionDate, List<JournalLine> lines
});




}
/// @nodoc
class __$JournalEntryCopyWithImpl<$Res>
    implements _$JournalEntryCopyWith<$Res> {
  __$JournalEntryCopyWithImpl(this._self, this._then);

  final _JournalEntry _self;
  final $Res Function(_JournalEntry) _then;

/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? description = null,Object? sourceType = null,Object? sourceId = freezed,Object? lockedAt = freezed,Object? lockedBy = null,Object? createdAt = freezed,Object? transactionDate = freezed,Object? lines = null,}) {
  return _then(_JournalEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,sourceType: null == sourceType ? _self.sourceType : sourceType // ignore: cast_nullable_to_non_nullable
as String,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,lockedAt: freezed == lockedAt ? _self.lockedAt : lockedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lockedBy: null == lockedBy ? _self.lockedBy : lockedBy // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,transactionDate: freezed == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self._lines : lines // ignore: cast_nullable_to_non_nullable
as List<JournalLine>,
  ));
}


}


/// @nodoc
mixin _$JournalListResponse {

 int get total; int get limit; int get offset; List<JournalEntry> get items;
/// Create a copy of JournalListResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JournalListResponseCopyWith<JournalListResponse> get copyWith => _$JournalListResponseCopyWithImpl<JournalListResponse>(this as JournalListResponse, _$identity);

  /// Serializes this JournalListResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JournalListResponse&&(identical(other.total, total) || other.total == total)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, items));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,total,limit,offset,const DeepCollectionEquality().hash(items));

@override
String toString() {
  return 'JournalListResponse(total: $total, limit: $limit, offset: $offset, items: $items)';
}


}

/// @nodoc
abstract mixin class $JournalListResponseCopyWith<$Res>  {
  factory $JournalListResponseCopyWith(JournalListResponse value, $Res Function(JournalListResponse) _then) = _$JournalListResponseCopyWithImpl;
@useResult
$Res call({
 int total, int limit, int offset, List<JournalEntry> items
});




}
/// @nodoc
class _$JournalListResponseCopyWithImpl<$Res>
    implements $JournalListResponseCopyWith<$Res> {
  _$JournalListResponseCopyWithImpl(this._self, this._then);

  final JournalListResponse _self;
  final $Res Function(JournalListResponse) _then;

/// Create a copy of JournalListResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? total = null,Object? limit = null,Object? offset = null,Object? items = null,}) {
  return _then(_self.copyWith(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<JournalEntry>,
  ));
}

}


/// Adds pattern-matching-related methods to [JournalListResponse].
extension JournalListResponsePatterns on JournalListResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JournalListResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JournalListResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JournalListResponse value)  $default,){
final _that = this;
switch (_that) {
case _JournalListResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JournalListResponse value)?  $default,){
final _that = this;
switch (_that) {
case _JournalListResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int total,  int limit,  int offset,  List<JournalEntry> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JournalListResponse() when $default != null:
return $default(_that.total,_that.limit,_that.offset,_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int total,  int limit,  int offset,  List<JournalEntry> items)  $default,) {final _that = this;
switch (_that) {
case _JournalListResponse():
return $default(_that.total,_that.limit,_that.offset,_that.items);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int total,  int limit,  int offset,  List<JournalEntry> items)?  $default,) {final _that = this;
switch (_that) {
case _JournalListResponse() when $default != null:
return $default(_that.total,_that.limit,_that.offset,_that.items);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JournalListResponse implements JournalListResponse {
  const _JournalListResponse({this.total = 0, this.limit = 100, this.offset = 0, final  List<JournalEntry> items = const <JournalEntry>[]}): _items = items;
  factory _JournalListResponse.fromJson(Map<String, dynamic> json) => _$JournalListResponseFromJson(json);

@override@JsonKey() final  int total;
@override@JsonKey() final  int limit;
@override@JsonKey() final  int offset;
 final  List<JournalEntry> _items;
@override@JsonKey() List<JournalEntry> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of JournalListResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JournalListResponseCopyWith<_JournalListResponse> get copyWith => __$JournalListResponseCopyWithImpl<_JournalListResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JournalListResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JournalListResponse&&(identical(other.total, total) || other.total == total)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other._items, _items));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,total,limit,offset,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'JournalListResponse(total: $total, limit: $limit, offset: $offset, items: $items)';
}


}

/// @nodoc
abstract mixin class _$JournalListResponseCopyWith<$Res> implements $JournalListResponseCopyWith<$Res> {
  factory _$JournalListResponseCopyWith(_JournalListResponse value, $Res Function(_JournalListResponse) _then) = __$JournalListResponseCopyWithImpl;
@override @useResult
$Res call({
 int total, int limit, int offset, List<JournalEntry> items
});




}
/// @nodoc
class __$JournalListResponseCopyWithImpl<$Res>
    implements _$JournalListResponseCopyWith<$Res> {
  __$JournalListResponseCopyWithImpl(this._self, this._then);

  final _JournalListResponse _self;
  final $Res Function(_JournalListResponse) _then;

/// Create a copy of JournalListResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? total = null,Object? limit = null,Object? offset = null,Object? items = null,}) {
  return _then(_JournalListResponse(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<JournalEntry>,
  ));
}


}

// dart format on

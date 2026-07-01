import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'journal_entry.freezed.dart';
part 'journal_entry.g.dart';

@freezed
sealed class JournalLine with _$JournalLine {
  const factory JournalLine({
    required String id,
    @JsonKey(name: 'journalEntryId') required String journalEntryId,
    @JsonKey(name: 'accountId') required String accountId,
    @Default(0.0) double debit,
    @Default(0.0) double credit,
    @Default('') String description,
    @JsonKey(name: 'accountCode') String? accountCode,
    @JsonKey(name: 'accountName') String? accountName,
    @JsonKey(name: 'accountType') String? accountType,
  }) = _JournalLine;

  factory JournalLine.fromJson(Map<String, dynamic> json) =>
      _$JournalLineFromJson(json);
}

@freezed
sealed class JournalEntry with _$JournalEntry {
  const factory JournalEntry({
    required String id,
    @Default('') String description,
    @JsonKey(name: 'sourceType') @Default('') String sourceType,
    @JsonKey(name: 'sourceId') String? sourceId,
    @JsonKey(name: 'lockedAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? lockedAt,
    @JsonKey(name: 'lockedBy') @Default('') String lockedBy,
    @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'transactionDate') String? transactionDate,
    @Default(<JournalLine>[]) List<JournalLine> lines,
  }) = _JournalEntry;

  factory JournalEntry.fromJson(Map<String, dynamic> json) =>
      _$JournalEntryFromJson(json);
}

@freezed
sealed class JournalListResponse with _$JournalListResponse {
  const factory JournalListResponse({
    @Default(0) int total,
    @Default(100) int limit,
    @Default(0) int offset,
    @Default(<JournalEntry>[]) List<JournalEntry> items,
  }) = _JournalListResponse;

  factory JournalListResponse.fromJson(Map<String, dynamic> json) =>
      _$JournalListResponseFromJson(json);
}
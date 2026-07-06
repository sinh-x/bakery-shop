// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journal_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_JournalLine _$JournalLineFromJson(Map<String, dynamic> json) => _JournalLine(
  id: json['id'] as String,
  journalEntryId: json['journalEntryId'] as String,
  accountId: json['accountId'] as String,
  debit: (json['debit'] as num?)?.toDouble() ?? 0.0,
  credit: (json['credit'] as num?)?.toDouble() ?? 0.0,
  description: json['description'] as String? ?? '',
  accountCode: json['accountCode'] as String?,
  accountName: json['accountName'] as String?,
  accountType: json['accountType'] as String?,
);

Map<String, dynamic> _$JournalLineToJson(_JournalLine instance) =>
    <String, dynamic>{
      'id': instance.id,
      'journalEntryId': instance.journalEntryId,
      'accountId': instance.accountId,
      'debit': instance.debit,
      'credit': instance.credit,
      'description': instance.description,
      'accountCode': instance.accountCode,
      'accountName': instance.accountName,
      'accountType': instance.accountType,
    };

_JournalEntry _$JournalEntryFromJson(Map<String, dynamic> json) =>
    _JournalEntry(
      id: json['id'] as String,
      description: json['description'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      sourceId: json['sourceId'] as String?,
      lockedAt: parseApiDateTime(json['lockedAt'] as String?),
      lockedBy: json['lockedBy'] as String? ?? '',
      createdAt: parseApiDateTime(json['createdAt'] as String?),
      transactionDate: json['transactionDate'] as String?,
      lines:
          (json['lines'] as List<dynamic>?)
              ?.map((e) => JournalLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <JournalLine>[],
    );

Map<String, dynamic> _$JournalEntryToJson(_JournalEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'description': instance.description,
      'sourceType': instance.sourceType,
      'sourceId': instance.sourceId,
      'lockedAt': timestampToJson(instance.lockedAt),
      'lockedBy': instance.lockedBy,
      'createdAt': timestampToJson(instance.createdAt),
      'transactionDate': instance.transactionDate,
      'lines': instance.lines,
    };

_JournalListResponse _$JournalListResponseFromJson(Map<String, dynamic> json) =>
    _JournalListResponse(
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 100,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <JournalEntry>[],
    );

Map<String, dynamic> _$JournalListResponseToJson(
  _JournalListResponse instance,
) => <String, dynamic>{
  'total': instance.total,
  'limit': instance.limit,
  'offset': instance.offset,
  'items': instance.items,
};

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'checklist_entry.freezed.dart';
part 'checklist_entry.g.dart';

@freezed
sealed class ChecklistEntry with _$ChecklistEntry {
  const factory ChecklistEntry({
    required int id,
    @JsonKey(name: 'template_id') required int templateId,
    @JsonKey(name: 'checklist_date') required String checklistDate,
    @Default(false) bool completed,
    @JsonKey(name: 'completed_by') @Default('') String completedBy,
    @JsonKey(
      name: 'completed_at',
      fromJson: parseApiDateTime,
      toJson: timestampToJson,
    )
    DateTime? completedAt,
    @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'template_name') String? templateName,
    @JsonKey(name: 'template_period') String? templatePeriod,
    @JsonKey(name: 'template_sort_order') int? templateSortOrder,
  }) = _ChecklistEntry;

  factory ChecklistEntry.fromJson(Map<String, dynamic> json) =>
      _$ChecklistEntryFromJson(json);
}

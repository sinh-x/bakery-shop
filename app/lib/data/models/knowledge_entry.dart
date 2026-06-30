import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'knowledge_entry.freezed.dart';
part 'knowledge_entry.g.dart';

@freezed
sealed class KnowledgeEntry with _$KnowledgeEntry {
  const factory KnowledgeEntry({
    required int id,
    required String title,
    @Default('') String content,
    @Default('note') String type,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'logged_by') @Default('') String loggedBy,
    @Default('app') String source,
    @JsonKey(name: 'created_at', fromJson: parseApiDateTimeRequired)
    required DateTime createdAt,
    @JsonKey(name: 'updated_at', fromJson: parseApiDateTimeRequired)
    required DateTime updatedAt,
    @Default(false) bool pinned,
    @JsonKey(name: 'pinned_at', fromJson: parseApiDateTime) DateTime? pinnedAt,
    @Default(<KnowledgePhoto>[]) List<KnowledgePhoto> photos,
  }) = _KnowledgeEntry;

  factory KnowledgeEntry.fromJson(Map<String, dynamic> json) =>
      _$KnowledgeEntryFromJson(json);
}

@freezed
sealed class KnowledgePhoto with _$KnowledgePhoto {
  const factory KnowledgePhoto({
    required String hash,
    required String url,
    @Default('') String caption,
    @Default(0) int position,
  }) = _KnowledgePhoto;

  factory KnowledgePhoto.fromJson(Map<String, dynamic> json) =>
      _$KnowledgePhotoFromJson(json);
}

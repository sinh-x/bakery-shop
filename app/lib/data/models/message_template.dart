import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'message_template.freezed.dart';
part 'message_template.g.dart';

/// One message template row returned by ``GET /api/templates`` (DG-375
/// Phase 2).
///
/// Mirrors the backend `MessageTemplate` dataclass from
/// `src/baker/models/template.py`. Templates are either system-wide
/// (``isSystem = true``, admin-managed via FR6) or personal
/// (``isSystem = false``, owned by a specific staff member via
/// [createdByStaffId], managed via FR7). Template [body] stores raw
/// placeholder syntax (e.g. ``{customer_name}``, ``{order_code}``) that is
/// resolved client-side; the backend stores the body verbatim (FR4).
///
/// The 6 allowed [scenario] slugs are: ``ask_info``, ``confirm_order``,
/// ``final_message``, ``follow_up``, ``status_update``, ``payment_request``.
/// The list endpoint orders rows by scenario, sort_order, id so the client
/// can group them by scenario for the picker modal (FR1).
@freezed
sealed class MessageTemplate with _$MessageTemplate {
  const factory MessageTemplate({
    required int id,
    required String scenario,
    required String name,
    @Default('') String body,
    @JsonKey(name: 'is_system') @Default(false) bool isSystem,
    @JsonKey(name: 'created_by_staff_id') int? createdByStaffId,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @Default(true) bool active,
    @JsonKey(name: 'created_at', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'updated_at', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? updatedAt,
  }) = _MessageTemplate;

  factory MessageTemplate.fromJson(Map<String, dynamic> json) =>
      _$MessageTemplateFromJson(json);
}
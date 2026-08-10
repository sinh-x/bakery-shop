import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/template_service.dart';
import '../models/message_template.dart';

/// Default built-in message templates bundled in the app as an offline
/// fallback (DG-375 FR9 / NFR3).
///
/// These 8 templates across 6 scenarios match the backend seed data from
/// migration v100 (`SEED_MESSAGE_TEMPLATES` in
/// `src/baker/db/schema/_constants.py`). They are shown when the backend is
/// unavailable so basic template functionality works without network.
/// All are system templates (``isSystem = true``). Template bodies use
/// placeholder syntax resolved client-side.
///
/// See `docs/agent-teams/requirements/artifacts/2026-08-08-order-message-templates.md`
/// Appendix A for the canonical text content.
@visibleForTesting
const List<MessageTemplate> defaultTemplatesFallback = [
  MessageTemplate(
    id: -1,
    scenario: 'ask_info',
    name: 'Hỏi thông tin đặt bánh',
    body: 'Dạ mình đặt bánh khi nào lấy ạ? Cho shop xin nội dung ghi kèm bánh và số điện thoại để ghi đơn nhé.',
    isSystem: true,
    sortOrder: 1,
    active: true,
  ),
  MessageTemplate(
    id: -2,
    scenario: 'confirm_order',
    name: 'Xác nhận đơn — Pickup',
    body: 'Dạ shop gửi xác nhận đơn bánh mã {public_order_code} của mình ạ:\n'
        '{items_list}\n'
        'Tổng cộng: {total_price}\n'
        'Mình nhận bánh ở tiệm Đoàn Gia - Ninh Diêm, 61 Hòn Khói vào {due_date} {due_time} ạ.\n'
        'Mình xem lại giúp shop nha.',
    isSystem: true,
    sortOrder: 2,
    active: true,
  ),
  MessageTemplate(
    id: -3,
    scenario: 'confirm_order',
    name: 'Xác nhận đơn — Delivery',
    body: 'Dạ shop gửi xác nhận đơn bánh mã {public_order_code} của mình ạ:\n'
        '{items_list}\n'
        'Tổng cộng: {total_price}\n'
        'Shop sẽ giao bánh tới {delivery_address} vào {due_date} {due_time} ạ.\n'
        'Mình xem lại giúp shop nha.',
    isSystem: true,
    sortOrder: 3,
    active: true,
  ),
  MessageTemplate(
    id: -4,
    scenario: 'confirm_order',
    name: 'Xác nhận đơn — Gửi xe buýt',
    body: 'Dạ shop gửi xác nhận đơn bánh mã {public_order_code} của mình ạ:\n'
        '{items_list}\n'
        'Tổng cộng: {total_price}\n'
        'Shop sẽ gửi bánh qua xe buýt vào {due_date} {due_time} ạ.\n'
        'Mình xem lại giúp shop nha.',
    isSystem: true,
    sortOrder: 4,
    active: true,
  ),
  MessageTemplate(
    id: -5,
    scenario: 'final_message',
    name: 'Bánh đã sẵn sàng',
    body: 'Dạ bánh của mình đã sẵn sàng ạ. Mã đơn {public_order_code}.\n'
        '{items_list}\n'
        '{delivery_type, select: pickup: Mình qua tiệm Đoàn Gia - Ninh Diêm, 61 Hòn Khói nhận bánh nha. | delivery: Shop đang giao bánh tới {delivery_address} ạ.}\n'
        'Mình nhận bánh kiểm tra giúp shop nha. Cảm ơn mình nhiều ạ!',
    isSystem: true,
    sortOrder: 5,
    active: true,
  ),
  MessageTemplate(
    id: -6,
    scenario: 'follow_up',
    name: 'Cảm ơn khách hàng',
    body: 'Dạ shop cảm ơn mình đã ủng hộ Đoàn Gia ạ. Bánh mình dùng có ngon không ạ? '
        'Có gì mình góp ý giúp shop nha. Lần sau mình cần bánh cứ nhắn shop ạ!',
    isSystem: true,
    sortOrder: 6,
    active: true,
  ),
  MessageTemplate(
    id: -7,
    scenario: 'status_update',
    name: 'Cập nhật trạng thái đơn',
    body: 'Dạ shop cập nhật đơn bánh mã {public_order_code} của mình: '
        '{status, select: confirmed: đã xác nhận | in_progress: đang làm | ready: đã sẵn sàng | delivering: đang giao} ạ.\n'
        'Dự kiến {delivery_type, select: pickup: mình qua nhận lúc {due_date} {due_time} | delivery: giao tới {delivery_address} lúc {due_date} {due_time}} ạ.',
    isSystem: true,
    sortOrder: 7,
    active: true,
  ),
  MessageTemplate(
    id: -8,
    scenario: 'payment_request',
    name: 'Yêu cầu thanh toán',
    body: 'Dạ shop gửi mình thông tin thanh toán đơn bánh mã {public_order_code} ạ:\n'
        '{items_list}\n'
        'Tổng cộng: {total_price}\n'
        '{notes, if: Đã ghi chú: {notes}}\n'
        'Mình chuyển khoản giúp shop qua:\n'
        '- Ngân hàng: ...\n'
        '- Số tài khoản: ...\n'
        '- Chủ tài khoản: ...\n'
        'Mình chuyển xong nhắn shop xác nhận nha. Cảm ơn mình ạ!',
    isSystem: true,
    sortOrder: 8,
    active: true,
  ),
];

/// Template list notifier (DG-375 Phase 2 — FR1 / NFR3).
///
/// Fetches system + the caller's personal templates from
/// ``GET /api/templates``. On failure (backend unavailable), falls back to
/// the bundled [defaultTemplatesFallback] so basic template functionality
/// works offline (NFR3). The list is ordered by scenario, sort_order, id
/// (matching the backend's ordering) so the UI can group it by scenario
/// for the picker modal (FR1).
class TemplateListNotifier extends AsyncNotifier<List<MessageTemplate>> {
  @override
  Future<List<MessageTemplate>> build() async {
    try {
      return await ref.read(templateServiceProvider).listTemplates();
    } catch (error) {
      // NFR3: fall back to bundled defaults when the backend is unavailable.
      return defaultTemplatesFallback;
    }
  }

  /// Re-fetches templates from the backend. On failure falls back to the
  /// bundled defaults so the UI always has something to show.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(templateServiceProvider).listTemplates();
    });
    // NFR3: if the fetch errored, replace with bundled defaults so the UI
    // can still render the picker modal.
    state = state.when(
      data: AsyncData.new,
      loading: () => const AsyncLoading(),
      error: (_, _) => const AsyncData(defaultTemplatesFallback),
    );
  }

  /// Create a template (FR6 / FR7). Admin callers create system templates;
  /// staff callers create personal templates. On success the new template
  /// is prepended to the list (preserving scenario, sort_order, id ordering
  /// on the next full refresh); on failure the error is surfaced via
  /// [AsyncValue.error].
  Future<MessageTemplate> createTemplate({
    required String scenario,
    required String name,
    required String body,
    bool isSystem = false,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final service = ref.read(templateServiceProvider);
    final created = await service.createTemplate(
      scenario: scenario,
      name: name,
      body: body,
      isSystem: isSystem,
      sortOrder: sortOrder,
      active: active,
    );
    final existing = state.asData?.value ?? const <MessageTemplate>[];
    state = AsyncData([...existing, created]);
    return created;
  }

  /// Update a template (FR6 / FR7). On success the list entry is replaced
  /// with the updated value.
  Future<MessageTemplate> updateTemplate(
    int id, {
    String? scenario,
    String? name,
    String? body,
    bool? isSystem,
    int? sortOrder,
    bool? active,
  }) async {
    final service = ref.read(templateServiceProvider);
    final updated = await service.updateTemplate(
      id,
      scenario: scenario,
      name: name,
      body: body,
      isSystem: isSystem,
      sortOrder: sortOrder,
      active: active,
    );
    state = state.whenData(
      (templates) => templates.map((t) => t.id == id ? updated : t).toList(),
    );
    return updated;
  }

  /// Delete a template (FR6 / FR7). On success the entry is removed from the
  /// list.
  Future<void> deleteTemplate(int id) async {
    final service = ref.read(templateServiceProvider);
    await service.deleteTemplate(id);
    state = state.whenData(
      (templates) => templates.where((t) => t.id != id).toList(),
    );
  }
}

/// Template list provider (FR1). AsyncNotifier wrapping
/// ``GET /api/templates`` with offline fallback (NFR3).
final templateListProvider =
    AsyncNotifierProvider<TemplateListNotifier, List<MessageTemplate>>(
  TemplateListNotifier.new,
);
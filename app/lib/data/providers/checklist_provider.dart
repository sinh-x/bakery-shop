import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/checklist_service.dart';
import '../models/checklist_template.dart';
import '../models/checklist_entry.dart';
import '../../shared/utils/date_formatting.dart';

// ── Checklist template provider ────────────────────────────────────────────

class ChecklistTemplatesNotifier
    extends AsyncNotifier<List<ChecklistTemplate>> {
  @override
  Future<List<ChecklistTemplate>> build() async {
    final service = ref.read(checklistServiceProvider);
    return service.listTemplates();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final service = ref.read(checklistServiceProvider);
      return service.listTemplates();
    });
  }

  Future<void> createTemplate({
    required String name,
    required String period,
    int? sortOrder,
  }) async {
    final service = ref.read(checklistServiceProvider);
    final existing = state.asData?.value ?? [];
    final periodItems =
        existing.where((t) => t.period == period).toList();
    final nextOrder = periodItems.isEmpty
        ? 0
        : periodItems.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) +
            1;
    final created = await service.createTemplate(
      name: name,
      period: period,
      sortOrder: sortOrder ?? nextOrder,
    );
    state = AsyncData([...existing, created]);
  }

  Future<void> updateTemplate(
    int id, {
    String? name,
    String? period,
    int? sortOrder,
    bool? active,
  }) async {
    final service = ref.read(checklistServiceProvider);
    final updated = await service.updateTemplate(
      id,
      name: name,
      period: period,
      sortOrder: sortOrder,
      active: active,
    );
    state = state.whenData(
      (templates) =>
          templates.map((t) => t.id == id ? updated : t).toList(),
    );
  }

  Future<void> deleteTemplate(int id) async {
    final service = ref.read(checklistServiceProvider);
    await service.deleteTemplate(id);
    state = state.whenData(
      (templates) => templates.where((t) => t.id != id).toList(),
    );
  }

  Future<void> reorderTemplate(int id, int newSortOrder) async {
    await updateTemplate(id, sortOrder: newSortOrder);
  }
}

final checklistTemplatesProvider =
    AsyncNotifierProvider<ChecklistTemplatesNotifier, List<ChecklistTemplate>>(
  ChecklistTemplatesNotifier.new,
);

// ── Daily checklist provider ───────────────────────────────────────────────

class DailyChecklistState {
  final String date;
  final List<ChecklistEntry> entries;

  const DailyChecklistState({required this.date, required this.entries});

  List<ChecklistEntry> get openingEntries =>
      entries.where((e) => e.templatePeriod == 'opening').toList();

  List<ChecklistEntry> get closingEntries =>
      entries.where((e) => e.templatePeriod == 'closing').toList();
}

class DailyChecklistNotifier
    extends AsyncNotifier<DailyChecklistState> {
  @override
  Future<DailyChecklistState> build() async {
    return _fetch();
  }

  Future<DailyChecklistState> _fetch({String? date}) async {
    final service = ref.read(checklistServiceProvider);
    final data = await service.getDailyChecklist(date: date);
    final dateStr = data['date'] as String;
    final entriesJson = data['entries'] as List;
    final entries = entriesJson
        .map((json) =>
            ChecklistEntry.fromJson(json as Map<String, dynamic>))
        .toList();
    return DailyChecklistState(date: dateStr, entries: entries);
  }

  Future<void> refresh({String? date}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(date: date));
  }

  Future<void> toggleEntry(int entryId, String staffName) async {
    final service = ref.read(checklistServiceProvider);
    final updated = await service.toggleEntry(entryId, staffName);
    state = state.whenData((current) {
      final newEntries = current.entries
          .map((e) => e.id == entryId ? updated : e)
          .toList();
      return DailyChecklistState(date: current.date, entries: newEntries);
    });
  }
}

final dailyChecklistProvider =
    AsyncNotifierProvider<DailyChecklistNotifier, DailyChecklistState>(
  DailyChecklistNotifier.new,
);

// ── Checklist history provider ─────────────────────────────────────────────

class ChecklistHistoryNotifier
    extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    // default: last 7 days
    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 6));
    final service = ref.read(checklistServiceProvider);
    return service.getHistory(
      fromDate: _fmt(from),
      toDate: _fmt(to),
    );
  }

  Future<void> fetchRange(DateTime from, DateTime to) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final service = ref.read(checklistServiceProvider);
      return service.getHistory(fromDate: _fmt(from), toDate: _fmt(to));
    });
  }

  String _fmt(DateTime dt) => formatApiDate(dt);
}

final checklistHistoryProvider =
    AsyncNotifierProvider<ChecklistHistoryNotifier, List<Map<String, dynamic>>>(
  ChecklistHistoryNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/knowledge_service.dart';
import '../models/knowledge_entry.dart';

class KnowledgeEntriesNotifier extends AsyncNotifier<List<KnowledgeEntry>> {
  @override
  Future<List<KnowledgeEntry>> build() async {
    return ref.read(knowledgeServiceProvider).listEntries();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(knowledgeServiceProvider).listEntries();
    });
  }

  Future<void> createEntry({
    required String title,
    String content = '',
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
  }) async {
    final service = ref.read(knowledgeServiceProvider);
    final created = await service.createEntry(
      title: title,
      content: content,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
    );
    final existing = state.asData?.value ?? [];
    state = AsyncData([created, ...existing]);
  }

  Future<void> updateEntry(
    int id, {
    String? title,
    String? content,
    String? type,
    List<String>? tags,
  }) async {
    final service = ref.read(knowledgeServiceProvider);
    final updated = await service.updateEntry(
      id,
      title: title,
      content: content,
      type: type,
      tags: tags,
    );
    state = state.whenData(
      (entries) =>
          entries.map((e) => e.id == id ? updated : e).toList(),
    );
  }

  Future<void> deleteEntry(int id) async {
    final service = ref.read(knowledgeServiceProvider);
    await service.deleteEntry(id);
    state = state.whenData(
      (entries) => entries.where((e) => e.id != id).toList(),
    );
  }

  Future<KnowledgeEntry> pinEntry(int id, bool pin) async {
    final service = ref.read(knowledgeServiceProvider);
    final updated = pin
        ? await service.pinEntry(id)
        : await service.unpinEntry(id);
    state = state.whenData(
      (entries) => entries.map((e) => e.id == id ? updated : e).toList(),
    );
    return updated;
  }
}

final knowledgeEntriesProvider =
    AsyncNotifierProvider<KnowledgeEntriesNotifier, List<KnowledgeEntry>>(
  KnowledgeEntriesNotifier.new,
);

class KnowledgeEntryDetailNotifier
    extends AsyncNotifier<KnowledgeEntry?> {
  final int id;

  KnowledgeEntryDetailNotifier(this.id);

  @override
  Future<KnowledgeEntry?> build() async {
    return ref.read(knowledgeServiceProvider).getEntry(id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(knowledgeServiceProvider).getEntry(id);
    });
  }
}

final knowledgeEntryDetailProvider = AsyncNotifierProvider.family<
    KnowledgeEntryDetailNotifier, KnowledgeEntry?, int>(
  (id) => KnowledgeEntryDetailNotifier(id),
);

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/knowledge_entry.dart';
import '../../data/providers/knowledge_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

const _kTypeChips = [
  ('recipe', 'Công thức'),
  ('procedure', 'Quy trình'),
  ('equipment', 'Thiết bị'),
  ('supplier', 'Nhà cung cấp'),
  ('reference', 'Tham khảo'),
  ('note', 'Ghi chú'),
];

class KnowledgeListScreen extends ConsumerStatefulWidget {
  const KnowledgeListScreen({super.key, this.initialType});

  final String? initialType;
  @override
  ConsumerState<KnowledgeListScreen> createState() => _KnowledgeListScreenState();
}

class _KnowledgeListScreenState extends ConsumerState<KnowledgeListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  late String? _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.invalidate(knowledgeEntriesProvider);
    });
  }

  void _setTypeFilter(String? type) {
    setState(() => _selectedType = type);
    ref.invalidate(knowledgeEntriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(knowledgeEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.knowledgeTitle),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: VN.searchKnowledge,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Type filter chips (horizontal scroll)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Tất cả'),
                    selected: _selectedType == null,
                    onSelected: (_) => _setTypeFilter(null),
                  ),
                ),
                ..._kTypeChips.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(t.$2),
                    selected: _selectedType == t.$1,
                    onSelected: (_) => _setTypeFilter(t.$1),
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Entries list
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(VN.apiError),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(knowledgeEntriesProvider),
                      child: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (entries) {
                // Filter locally (listEntries already fetches with search/type from API)
                final filtered = _filterEntries(entries);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          VN.noKnowledgeEntries,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  );
                }

                // Partition pinned vs unpinned
                final pinned = filtered.where((e) => e.pinned).toList();
                final unpinned = filtered.where((e) => !e.pinned).toList();

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(knowledgeEntriesProvider);
                  },
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // Pinned section
                      if (pinned.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            '📌 Đã ghim',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                        ...pinned.map((entry) => _KnowledgeEntryCard(
                          entry: entry,
                          onTap: () => context.push('/knowledge/${entry.id}'),
                        )),
                        const SizedBox(height: 8),
                      ],
                      // Unpinned section
                      ...unpinned.map((entry) => _KnowledgeEntryCard(
                        entry: entry,
                        onTap: () => context.push('/knowledge/${entry.id}'),
                      )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/knowledge/new'),
        tooltip: VN.createKnowledge,
        child: const Icon(Icons.add),
      ),
    );
  }

  List<KnowledgeEntry> _filterEntries(List<KnowledgeEntry> entries) {
    return entries.where((e) {
      if (_selectedType != null && e.type != _selectedType) {
        return false;
      }
      if (_searchCtrl.text.isNotEmpty) {
        final q = _searchCtrl.text.toLowerCase();
        if (!e.title.toLowerCase().contains(q) &&
            !e.content.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

class _KnowledgeEntryCard extends StatelessWidget {
  const _KnowledgeEntryCard({required this.entry, required this.onTap});

  final KnowledgeEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeLabel = VN.knowledgeTypes[entry.type] ?? entry.type;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('📌', style: TextStyle(fontSize: 14)),
                    ),
                  Expanded(
                    child: Text(
                      entry.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.photos.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo, size: 12, color: Colors.blue.shade700),
                          const SizedBox(width: 2),
                          Text(
                            '${entry.photos.length}',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(typeLabel, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: entry.tags
                      .take(5)
                      .map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(tag, style: TextStyle(fontSize: 10, color: Colors.amber.shade800)),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatDate(entry.updatedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    return '$day/$month/$year';
  }
}

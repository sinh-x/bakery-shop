import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/providers/knowledge_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/knowledge_photo_gallery.dart';

class KnowledgeDetailScreen extends ConsumerWidget {
  const KnowledgeDetailScreen({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(knowledgeEntryDetailProvider(entryId));

    return entryAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(knowledgeEntryDetailProvider(entryId)),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
      ),
      data: (entry) {
        if (entry == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text(VN.apiError)),
          );
        }

        final typeLabel = VN.knowledgeTypes[entry.type] ?? entry.type;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(entry.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: VN.share,
                onPressed: () {
                  Share.share('${entry.title}\n\n${entry.content}');
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: VN.editKnowledge,
                onPressed: () => context.push('/knowledge/${entry.id}/edit'),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(VN.confirmDeleteKnowledge),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(VN.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                            child: const Text(VN.deleteKnowledge),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(knowledgeEntriesProvider.notifier).deleteEntry(entry.id);
                      if (context.mounted) {
                        showTopSnackBar(context, VN.knowledgeDeleted);
                        context.pop();
                      }
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Text(VN.deleteKnowledge,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Title
              Text(entry.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),

              // Type chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(typeLabel, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 12),

              // Tags
              if (entry.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: entry.tags
                      .map((tag) => Chip(
                            label: Text(tag),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),

              if (entry.tags.isNotEmpty) const SizedBox(height: 16),

              // Photo gallery
              if (entry.photos.isNotEmpty) ...[
                KnowledgePhotoGallery(
                  photos: entry.photos,
                  baseUrl: '',
                ),
                const SizedBox(height: 16),
              ],

              // Content
              if (entry.content.isNotEmpty)
                Text(
                  entry.content,
                  style: theme.textTheme.bodyLarge,
                ),

              const SizedBox(height: 16),

              // Updated at
              Text(
                'Cập nhật: ${_formatDateTime(entry.updatedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/shared/labels/shared.dart';

class _HubTile {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class KnowledgeBaseScreen extends ConsumerWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const tiles = [
      _HubTile(
        icon: Icons.event_note_outlined,
        title: 'Sự kiện',
        subtitle: VN.knowledgeBaseEventsSubtitle,
        route: '/events',
      ),
      _HubTile(
        icon: Icons.checklist,
        title: 'Checklist hàng ngày',
        subtitle: VN.knowledgeBaseChecklistSubtitle,
        route: '/checklist',
      ),
      _HubTile(
        icon: Icons.menu_book,
        title: 'Tài liệu tri thức',
        subtitle: VN.knowledgeBaseDocsSubtitle,
        route: '/knowledge',
      ),
    ];

    // ignore: prefer_const_constructors
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.tabKnowledgeBase),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => context.push(tile.route),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        tile.icon,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tile.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tile.subtitle,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/event.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/events.dart';

const _kTypeIcons = <String, IconData>{
  'note': Icons.edit_note,
  'equipment': Icons.warning_amber,
  'production': Icons.bakery_dining,
  'inventory': Icons.inventory_2,
  'expense': Icons.payments,
  'delivery': Icons.local_shipping,
  'order': Icons.receipt_long,
};

const _kTypeLabels = <String, String>{
  'note': VN.eventNote,
  'equipment': VN.typeEquipment,
  'production': VN.eventProduction,
  'inventory': VN.eventInventory,
  'expense': VN.eventExpense,
  'delivery': VN.eventDelivery,
  'order': VN.eventOrder,
};

Color _badgeColor(String type) {
  switch (type) {
    case 'equipment':
      return Colors.orange.shade100;
    case 'production':
      return Colors.amber.shade100;
    case 'inventory':
      return Colors.green.shade100;
    case 'expense':
      return Colors.purple.shade100;
    case 'delivery':
      return Colors.teal.shade100;
    case 'order':
      return Colors.indigo.shade100;
    default:
      return Colors.blue.shade100;
  }
}

Color _iconColor(String type) {
  switch (type) {
    case 'equipment':
      return Colors.orange.shade700;
    case 'production':
      return Colors.amber.shade700;
    case 'inventory':
      return Colors.green.shade700;
    case 'expense':
      return Colors.purple.shade700;
    case 'delivery':
      return Colors.teal.shade700;
    case 'order':
      return Colors.indigo.shade700;
    default:
      return Colors.blue.shade700;
  }
}

/// Full-screen event detail view.
///
/// Shows all event fields and provides an edit action that opens [EventFormScreen].
class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.event});

  final BakeryEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = _kTypeLabels[event.type] ?? event.type;
    final typeIcon = _kTypeIcons[event.type] ?? Icons.event_note;

    return Scaffold(
      appBar: AppBar(
        title: Text(typeLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: VN.editEvent,
            onPressed: () =>
                context.push('/events/${event.id}/edit', extra: event),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Type badge + timestamp row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _badgeColor(event.type),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(typeIcon, size: 24, color: _iconColor(event.type)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(typeLabel, style: theme.textTheme.titleMedium),
                  Text(
                    formatDisplay(event.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Summary
          Text(
            VN.eventSummary,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(event.summary, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),

          // Tags
          if (event.tags.isNotEmpty) ...[
            Text(
              VN.tagsLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: event.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Logged by
          if (event.loggedBy.isNotEmpty)
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${VN.loggedBy}: ${event.displayLoggedBy}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

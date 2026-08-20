import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/event.dart';
import '../../../data/providers/events_provider.dart';
import '../../../shared/utils/date_formatting.dart';
import '../providers/event_history_filter_notifier.dart';
import 'event_card_photo_count.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/shared.dart';
enum _DateRange { today, week, month, all }

const _kDateRangeLabels = {
  _DateRange.today: EventsLabels.filterToday,
  _DateRange.week: EventsLabels.filterWeek,
  _DateRange.month: EventsLabels.filterMonth,
  _DateRange.all: EventsLabels.filterAll,
};

EventHistoryDateRange _toPublicRange(_DateRange r) {
  switch (r) {
    case _DateRange.today:
      return EventHistoryDateRange.today;
    case _DateRange.week:
      return EventHistoryDateRange.week;
    case _DateRange.month:
      return EventHistoryDateRange.month;
    case _DateRange.all:
      return EventHistoryDateRange.all;
  }
}

_DateRange _fromPublicRange(EventHistoryDateRange r) {
  switch (r) {
    case EventHistoryDateRange.today:
      return _DateRange.today;
    case EventHistoryDateRange.week:
      return _DateRange.week;
    case EventHistoryDateRange.month:
      return _DateRange.month;
    case EventHistoryDateRange.all:
      return _DateRange.all;
  }
}

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
  'note': EventsLabels.eventNote,
  'equipment': EventsLabels.typeEquipment,
  'production': EventsLabels.eventProduction,
  'inventory': EventsLabels.eventInventory,
  'expense': EventsLabels.eventExpense,
  'delivery': EventsLabels.eventDelivery,
  'order': EventsLabels.eventOrder,
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

/// Scrollable event history list with filter bar.
///
/// Filter bar includes date range chips, type dropdown, and search.
/// Filter changes call [eventsProvider.notifier.refresh].
/// Must be placed inside an [Expanded] or [Flexible] by the parent.
class EventHistoryList extends ConsumerStatefulWidget {
  const EventHistoryList({super.key});

  @override
  ConsumerState<EventHistoryList> createState() => _EventHistoryListState();
}

class _EventHistoryListState extends ConsumerState<EventHistoryList> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? _sinceFor(_DateRange range) {
    final now = DateTime.now();
    DateTime? base;
    switch (range) {
      case _DateRange.today:
        base = now;
      case _DateRange.week:
        base = now.subtract(const Duration(days: 7));
      case _DateRange.month:
        base = now.subtract(const Duration(days: 30));
      case _DateRange.all:
        return null;
    }
    return formatApiDate(base);
  }

  void _applyFilters() {
    final filter = ref.read(eventHistoryFilterProvider);
    final search = _searchCtrl.text.trim();
    ref.read(eventsProvider.notifier).refresh(
          type: filter.typeFilter,
          search: search.isNotEmpty ? search : null,
          since: _sinceFor(_fromPublicRange(filter.dateRange)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = ref.watch(eventsProvider);
    final filter = ref.watch(eventHistoryFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(EventsLabels.recentEvents, style: theme.textTheme.titleMedium),
        ),
        _buildFilterBar(theme, filter),
        const Divider(height: 1),
        Expanded(
          child: events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    SharedLabels.errorLoading,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _applyFilters,
                    child: const Text(SharedLabels.retry),
                  ),
                ],
              ),
            ),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text(
                      EventsLabels.noEvents,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (ctx, i) => _EventCard(event: list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme, EventHistoryFilterState filter) {
    final notifier = ref.read(eventHistoryFilterProvider.notifier);
    final dateRange = _fromPublicRange(filter.dateRange);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _DateRange.values.map((range) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_kDateRangeLabels[range]!),
                    selected: dateRange == range,
                    onSelected: (_) {
                      notifier.setDateRange(_toPublicRange(range));
                      _applyFilters();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Type filter + search row
          Row(
            children: [
              DropdownButton<String?>(
                value: filter.typeFilter,
                hint: const Text(EventsLabels.filterAll),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(EventsLabels.filterAll),
                  ),
                  ..._kTypeLabels.entries.map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.key,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _kTypeIcons[e.key] ?? Icons.event_note,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(e.value),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  notifier.setTypeFilter(v);
                  _applyFilters();
                },
              ),
              if (filter.searchExpanded) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: EventsLabels.searchEvents,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          notifier.collapseSearch();
                          _searchCtrl.clear();
                          _applyFilters();
                        },
                      ),
                    ),
                    onSubmitted: (_) => _applyFilters(),
                    onChanged: (v) {
                      if (v.isEmpty) _applyFilters();
                    },
                  ),
                ),
              ] else ...[
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: EventsLabels.searchEvents,
                  onPressed: () => notifier.setSearchExpanded(true),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final BakeryEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _kTypeIcons[event.type] ?? Icons.event_note;

    return InkWell(
      onTap: () => context.push('/events/${event.id}', extra: event),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _badgeColor(event.type),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: _iconColor(event.type)),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time + logged by + photo count
                Row(
                  children: [
                    Text(
                      formatDisplayTime(event.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (event.loggedBy.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '— ${event.displayLoggedBy}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    EventCardPhotoCount(eventId: event.id),
                  ],
                ),
                const SizedBox(height: 2),
                // Summary
                Text(
                  event.summary,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                // Tag chips (read-only)
                if (event.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: event.tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

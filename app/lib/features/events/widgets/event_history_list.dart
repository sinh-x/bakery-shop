import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/event.dart';
import '../../../providers/events_provider.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/events.dart';

enum _DateRange { today, week, month, all }

const _kDateRangeLabels = {
  _DateRange.today: VN.filterToday,
  _DateRange.week: VN.filterWeek,
  _DateRange.month: VN.filterMonth,
  _DateRange.all: VN.filterAll,
};

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
  _DateRange _dateRange = _DateRange.today;
  String? _typeFilter;
  bool _searchExpanded = false;
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
    final search = _searchCtrl.text.trim();
    ref.read(eventsProvider.notifier).refresh(
          type: _typeFilter,
          search: search.isNotEmpty ? search : null,
          since: _sinceFor(_dateRange),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = ref.watch(eventsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(VN.recentEvents, style: theme.textTheme.titleMedium),
        ),
        _buildFilterBar(theme),
        const Divider(height: 1),
        Expanded(
          child: events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    VN.errorLoading,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _applyFilters,
                    child: const Text(VN.retry),
                  ),
                ],
              ),
            ),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text(
                      VN.noEvents,
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

  Widget _buildFilterBar(ThemeData theme) {
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
                    selected: _dateRange == range,
                    onSelected: (_) {
                      setState(() => _dateRange = range);
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
                value: _typeFilter,
                hint: const Text(VN.filterAll),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(VN.filterAll),
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
                  setState(() => _typeFilter = v);
                  _applyFilters();
                },
              ),
              if (_searchExpanded) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: VN.searchEvents,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchExpanded = false;
                            _searchCtrl.clear();
                          });
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
                  tooltip: VN.searchEvents,
                  onPressed: () => setState(() => _searchExpanded = true),
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
                // Time + logged by
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
                        '— ${event.loggedBy}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

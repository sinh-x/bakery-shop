import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../../data/models/message_template.dart';
import '../../../../shared/labels/templates.dart';
import 'template_management_tile.dart';

/// Scenario-grouped list of templates shown inside one tab of the template
/// management screen.
class TemplateGroupedList extends StatelessWidget {
  const TemplateGroupedList({
    super.key,
    required this.templates,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MessageTemplate> templates;
  final bool isAdmin;
  final ValueChanged<MessageTemplate> onEdit;
  final ValueChanged<MessageTemplate> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.message_outlined, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text(TemplatesLabels.managementEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }
    // Memoize the scenario grouping so it only recomputes when the templates
    // list actually changes (CQ-Grouping), rather than on every frame. We
    // store the previous source list and grouped result on the State so a
    // rebuild with identical templates reuses the cached grouping.
    final grouped = _groupedCache(templates);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              TemplatesLabels.scenarioLabel(entry.key),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final template in entry.value)
            TemplateManagementTile(
              template: template,
              canEdit: isAdmin,
              onEdit: () => onEdit(template),
              onDelete: () => onDelete(template),
            ),
        ],
      ],
    );
  }

  static _GroupedCache? _cache;

  /// Returns the cached grouping for [templates], recomputing only when the
  /// list identity or contents change (CQ-Grouping).
  static Map<String, List<MessageTemplate>> _groupedCache(
      List<MessageTemplate> templates) {
    final cached = _cache;
    if (cached != null && listEquals(cached.templates, templates)) {
      return cached.grouped;
    }
    final grouped = <String, List<MessageTemplate>>{};
    for (final t in templates) {
      grouped.putIfAbsent(t.scenario, () => []).add(t);
    }
    _cache = _GroupedCache(templates, grouped);
    return grouped;
  }
}

/// Cached (source list, scenario-grouped result) pair used by
/// [TemplateGroupedList._groupedCache] (CQ-Grouping).
class _GroupedCache {
  const _GroupedCache(this.templates, this.grouped);

  final List<MessageTemplate> templates;
  final Map<String, List<MessageTemplate>> grouped;
}
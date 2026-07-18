import 'package:flutter/material.dart';

import '../../../data/api/audit_log_service.dart';
import '../../../shared/labels/audit_log.dart';

/// A single audit log entry rendered as a Material list tile (FR24).
///
/// Shows the user, action (with a colored chip), entity type + id, timestamp,
/// and expandable old/new value sections. The tile is a [StatefulWidget] only
/// to track the expansion toggle; that is an acceptable local-UI-state use of
/// `setState` (§4 animation/widget-toggle exception).
class AuditLogTile extends StatefulWidget {
  const AuditLogTile({super.key, required this.entry});

  final AuditLogEntry entry;

  @override
  State<AuditLogTile> createState() => _AuditLogTileState();
}

class _AuditLogTileState extends State<AuditLogTile> {
  bool _expanded = false;

  Color _actionColor(String action) {
    switch (action) {
      case 'create':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _actionColor(e.action).withValues(alpha: 0.15),
              child: Icon(Icons.history, color: _actionColor(e.action)),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    e.username,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _actionColor(e.action).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AuditLogLabels.actionLabel(e.action),
                    style: TextStyle(
                      color: _actionColor(e.action),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${AuditLogLabels.entityTypeLabel(e.entityType)} '
                '• ${AuditLogLabels.colEntityId}: ${e.entityId} '
                '• ${e.createdAt}',
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.oldValue != null && e.oldValue!.isNotEmpty)
                    _ValueBlock(
                      label: AuditLogLabels.colOldValue,
                      value: e.oldValue!,
                    ),
                  if (e.oldValue != null && e.oldValue!.isNotEmpty)
                    const SizedBox(height: 8),
                  if (e.newValue != null && e.newValue!.isNotEmpty)
                    _ValueBlock(
                      label: AuditLogLabels.colNewValue,
                      value: e.newValue!,
                    ),
                  if ((e.oldValue == null || e.oldValue!.isEmpty) &&
                      (e.newValue == null || e.newValue!.isEmpty))
                    const Text('—'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
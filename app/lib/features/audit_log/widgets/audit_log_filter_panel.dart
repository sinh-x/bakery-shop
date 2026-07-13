import 'package:flutter/material.dart';

import '../../../data/api/audit_log_service.dart';
import '../../../shared/labels/audit_log.dart';

/// Filter controls for the audit log screen (FR24: user, date range, entity
/// type).
///
/// The panel is a self-contained [StatefulWidget] because it manages local
/// text-editing controllers for the username and date fields while the user
/// edits them; the actual filter state lives in [AuditLogNotifier]. On
/// "Apply" the panel calls [onApply] with the assembled [AuditLogFilters].
///
/// Per the Flutter coding standards (§4) the local text-controller state is
/// an acceptable `setState` use case (text editing controllers).
class AuditLogFilterPanel extends StatefulWidget {
  const AuditLogFilterPanel({
    super.key,
    required this.current,
    required this.onApply,
    required this.onClear,
  });

  final AuditLogFilters current;
  final ValueChanged<AuditLogFilters> onApply;
  final VoidCallback onClear;

  @override
  State<AuditLogFilterPanel> createState() => _AuditLogFilterPanelState();
}

class _AuditLogFilterPanelState extends State<AuditLogFilterPanel> {
  late final TextEditingController _usernameController;
  late final TextEditingController _dateFromController;
  late final TextEditingController _dateToController;
  late String _entityType;

  static const List<String> _entityTypes = [
    '',
    'config',
    'product',
    'category',
    'checklist_template',
    'staff',
  ];

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.current.username);
    _dateFromController = TextEditingController(text: widget.current.dateFrom);
    _dateToController = TextEditingController(text: widget.current.dateTo);
    _entityType = widget.current.entityType;
  }

  @override
  void didUpdateWidget(covariant AuditLogFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      if (widget.current.username != _usernameController.text) {
        _usernameController.text = widget.current.username;
      }
      if (widget.current.dateFrom != _dateFromController.text) {
        _dateFromController.text = widget.current.dateFrom;
      }
      if (widget.current.dateTo != _dateToController.text) {
        _dateToController.text = widget.current.dateTo;
      }
      _entityType = widget.current.entityType;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _dateFromController.dispose();
    _dateToController.dispose();
    super.dispose();
  }

  AuditLogFilters _buildFilters() => AuditLogFilters(
        username: _usernameController.text.trim(),
        entityType: _entityType,
        dateFrom: _dateFromController.text.trim(),
        dateTo: _dateToController.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(
              label: AuditLogLabels.filterUser,
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  hintText: AuditLogLabels.filterUserHint,
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: AuditLogLabels.filterEntityType,
              child: DropdownButtonFormField<String>(
                key: ValueKey('entity_type_$_entityType'),
                initialValue: _entityType,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _entityTypes
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e.isEmpty
                              ? AuditLogLabels.entityTypeAll
                              : AuditLogLabels.entityTypeLabel(e),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _entityType = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    label: AuditLogLabels.filterDateFrom,
                    child: TextField(
                      controller: _dateFromController,
                      decoration: const InputDecoration(
                        hintText: 'YYYY-MM-DD',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabeledField(
                    label: AuditLogLabels.filterDateTo,
                    child: TextField(
                      controller: _dateToController,
                      decoration: const InputDecoration(
                        hintText: 'YYYY-MM-DD',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OverflowBar(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.filter_list),
                  label: const Text(AuditLogLabels.applyFilters),
                  onPressed: () => widget.onApply(_buildFilters()),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text(AuditLogLabels.clearFilters),
                  onPressed: () {
                    _usernameController.clear();
                    _dateFromController.clear();
                    _dateToController.clear();
                    setState(() => _entityType = '');
                    widget.onClear();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small helper: a label above a child input widget.
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
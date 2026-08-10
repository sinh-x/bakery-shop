import 'package:flutter/material.dart';

import '../../../data/models/message_template.dart';
import '../../../shared/labels/templates.dart';

/// A single template row inside the management screen list (DG-375 Phase 4).
///
/// Shows the template name, scenario tag, and (when [canEdit] is true) edit
/// and delete affordances. Tapping the row also opens the editor.
class TemplateManagementTile extends StatelessWidget {
  const TemplateManagementTile({
    super.key,
    required this.template,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final MessageTemplate template;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = !template.active;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Row(
          children: [
            Flexible(
              child: Text(
                template.name,
                style: inactive
                    ? theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)
                    : theme.textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (inactive)
              Text(
                '(${TemplatesLabels.editorActiveLabel.toLowerCase()}: off)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
        subtitle: Text(
          template.body.split('\n').first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        trailing: canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: TemplatesLabels.managementEditTooltip,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: TemplatesLabels.managementDeleteTooltip,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                  ),
                ],
              )
            : null,
        onTap: canEdit ? onEdit : null,
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/message_template.dart';
import '../../../data/providers/template_providers.dart';
import '../../../shared/labels/templates.dart';
import 'widgets/template_editor_screen.dart';
import 'widgets/template_management_tile.dart';

/// Template management screen (DG-375 Phase 4 / FR6, FR7, FR10 / AC6, AC7).
///
/// A full-screen management surface for message templates. It exposes two
/// tabs:
/// - **Hệ thống** (system templates) — admin-managed, visible to all staff
///   (FR6 / AC6). Non-admin callers can browse but the edit/delete actions
///   and the add button are hidden.
/// - **Cá nhân** (personal templates) — owned by the signed-in staff member
///   (FR7 / AC7).
///
/// Templates within each tab are grouped by scenario (matching the picker
/// modal). Each row uses [TemplateManagementTile] which exposes edit and
/// delete actions. The FAB opens [TemplateEditorScreen] in create mode.
class TemplateManagementScreen extends ConsumerStatefulWidget {
  const TemplateManagementScreen({
    super.key,
    this.isAdmin = false,
  });

  /// Whether the current caller is an admin. Controls the add button on the
  /// system tab and the edit/delete affordances on system rows.
  final bool isAdmin;

  @override
  ConsumerState<TemplateManagementScreen> createState() =>
      _TemplateManagementScreenState();
}

class _TemplateManagementScreenState
    extends ConsumerState<TemplateManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isSystemTab => _tabController.index == 0;

  Future<void> _openEditor({MessageTemplate? template}) async {
    final isSystem = template?.isSystem ?? _isSystemTab;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplateEditorScreen(
          template: template,
          initialIsSystem: isSystem,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    // Refresh list after returning so newly created/edited rows show up.
    if (mounted) {
      await ref.read(templateListProvider.notifier).refresh();
    }
  }

  Future<void> _deleteTemplate(MessageTemplate template) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(TemplatesLabels.managementDeleteConfirmTitle),
            content: Text(TemplatesLabels.managementDeleteConfirmBody
                .replaceAll('{name}', template.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(VN.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(TemplatesLabels.managementDeleteConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(templateListProvider.notifier).deleteTemplate(template.id);
      if (mounted) {
        showTopSnackBar(
          context,
          TemplatesLabels.managementDeletedSnack.replaceAll('{name}', template.name),
        );
      }
    } catch (e) {
      if (mounted) showTopSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templateListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(TemplatesLabels.managementTitle),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: TemplatesLabels.managementSystemTab),
            Tab(text: TemplatesLabels.managementPersonalTab),
          ],
        ),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ManagementErrorView(error: e),
        data: (templates) => TabBarView(
          controller: _tabController,
          children: [
            _TemplateGroupedList(
              templates: templates.where((t) => t.isSystem).toList(),
              isAdmin: widget.isAdmin,
              onEdit: (t) => _openEditor(template: t),
              onDelete: _deleteTemplate,
            ),
            _TemplateGroupedList(
              templates: templates.where((t) => !t.isSystem).toList(),
              isAdmin: true, // personal tab always editable by owner
              onEdit: (t) => _openEditor(template: t),
              onDelete: _deleteTemplate,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: TemplatesLabels.managementAddButton,
        onPressed: _openEditor,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Error view for the management screen. Offers a retry button that
/// re-fetches templates (which falls back to bundled defaults when the
/// backend is still unavailable).
class _ManagementErrorView extends ConsumerWidget {
  const _ManagementErrorView({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('${VN.apiError}: $error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => ref.read(templateListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}

/// Scenario-grouped list of templates shown inside one tab.
class _TemplateGroupedList extends StatelessWidget {
  const _TemplateGroupedList({
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
    final grouped = <String, List<MessageTemplate>>{};
    for (final t in templates) {
      grouped.putIfAbsent(t.scenario, () => []).add(t);
    }
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
}
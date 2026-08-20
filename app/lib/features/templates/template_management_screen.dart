import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/message_template.dart';
import '../../../data/providers/template_providers.dart';
import '../../../shared/labels/templates.dart';
import '../../../shared/utils.dart' show showTopSnackBar;
import 'providers/template_management_notifier.dart';
import 'widgets/management_error_view.dart';
import 'widgets/template_editor_screen.dart';
import 'widgets/template_grouped_list.dart';
import 'widgets/template_management_tile.dart';
import 'package:bakery_app/shared/labels/shared.dart';
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
    _tabController.addListener(_syncTabIndex);
  }

  @override
  void dispose() {
    _tabController.removeListener(_syncTabIndex);
    _tabController.dispose();
    super.dispose();
  }

  void _syncTabIndex() {
    if (!_tabController.indexIsChanging) return;
    ref.read(templateManagementProvider.notifier).setTabIndex(_tabController.index);
  }

  Future<void> _openEditor({MessageTemplate? template}) async {
    final mgmt = ref.read(templateManagementProvider);
    final isSystem = template?.isSystem ?? mgmt.isSystemTab;
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
                child: const Text(SharedLabels.cancel),
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
          onTap: (_) => ref
              .read(templateManagementProvider.notifier)
              .setTabIndex(_tabController.index),
          tabs: const [
            Tab(text: TemplatesLabels.managementSystemTab),
            Tab(text: TemplatesLabels.managementPersonalTab),
          ],
        ),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ManagementErrorView(error: e),
        data: (templates) => TabBarView(
          controller: _tabController,
          children: [
            TemplateGroupedList(
              templates: templates.where((t) => t.isSystem).toList(),
              isAdmin: widget.isAdmin,
              onEdit: (t) => _openEditor(template: t),
              onDelete: _deleteTemplate,
            ),
            TemplateGroupedList(
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
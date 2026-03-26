import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/checklist_template.dart';
import '../../data/providers/checklist_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class ChecklistConfigScreen extends ConsumerStatefulWidget {
  const ChecklistConfigScreen({super.key});

  @override
  ConsumerState<ChecklistConfigScreen> createState() =>
      _ChecklistConfigScreenState();
}

class _ChecklistConfigScreenState
    extends ConsumerState<ChecklistConfigScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  Future<void> _showAddDialog(String period) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(period == 'opening' ? 'Thêm mục mở cửa' : 'Thêm mục đóng cửa'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên mục',
            hintText: 'Nhập tên công việc...',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await ref
            .read(checklistTemplatesProvider.notifier)
            .createTemplate(name: nameCtrl.text.trim(), period: period);
        if (mounted) {
          showTopSnackBar(context, 'Đã thêm mục checklist');
        }
      } catch (e) {
        if (mounted) {
          showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
        }
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _showEditDialog(ChecklistTemplate template) async {
    final nameCtrl = TextEditingController(text: template.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa mục checklist'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên mục',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.save),
          ),
        ],
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await ref
            .read(checklistTemplatesProvider.notifier)
            .updateTemplate(template.id, name: nameCtrl.text.trim());
        if (mounted) {
          showTopSnackBar(context, 'Đã cập nhật mục checklist');
        }
      } catch (e) {
        if (mounted) {
          showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
        }
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _confirmDelete(ChecklistTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa mục checklist'),
        content: Text('Xóa "${template.name}"? Thao tác này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.remove),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(checklistTemplatesProvider.notifier)
            .deleteTemplate(template.id);
        if (mounted) {
          showTopSnackBar(context, 'Đã xóa mục checklist');
        }
      } catch (e) {
        if (mounted) {
          showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
        }
      }
    }
  }

  Future<void> _moveUp(List<ChecklistTemplate> items, int index) async {
    if (index == 0) return;
    final item = items[index];
    final above = items[index - 1];
    try {
      await ref
          .read(checklistTemplatesProvider.notifier)
          .updateTemplate(item.id, sortOrder: above.sortOrder);
      await ref
          .read(checklistTemplatesProvider.notifier)
          .updateTemplate(above.id, sortOrder: item.sortOrder);
      await ref.read(checklistTemplatesProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _moveDown(List<ChecklistTemplate> items, int index) async {
    if (index == items.length - 1) return;
    final item = items[index];
    final below = items[index + 1];
    try {
      await ref
          .read(checklistTemplatesProvider.notifier)
          .updateTemplate(item.id, sortOrder: below.sortOrder);
      await ref
          .read(checklistTemplatesProvider.notifier)
          .updateTemplate(below.id, sortOrder: item.sortOrder);
      await ref.read(checklistTemplatesProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(checklistTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình checklist'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.wb_sunny_outlined), text: 'Mở cửa'),
            Tab(icon: Icon(Icons.nights_stay_outlined), text: 'Đóng cửa'),
          ],
        ),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(checklistTemplatesProvider.notifier).refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (templates) {
          final openingItems = templates
              .where((t) => t.period == 'opening')
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          final closingItems = templates
              .where((t) => t.period == 'closing')
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          return TabBarView(
            controller: _tabController,
            children: [
              _TemplateList(
                items: openingItems,
                period: 'opening',
                onAdd: () => _showAddDialog('opening'),
                onEdit: _showEditDialog,
                onDelete: _confirmDelete,
                onMoveUp: (index) => _moveUp(openingItems, index),
                onMoveDown: (index) => _moveDown(openingItems, index),
              ),
              _TemplateList(
                items: closingItems,
                period: 'closing',
                onAdd: () => _showAddDialog('closing'),
                onEdit: _showEditDialog,
                onDelete: _confirmDelete,
                onMoveUp: (index) => _moveUp(closingItems, index),
                onMoveDown: (index) => _moveDown(closingItems, index),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TemplateList extends StatelessWidget {
  const _TemplateList({
    required this.items,
    required this.period,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final List<ChecklistTemplate> items;
  final String period;
  final VoidCallback onAdd;
  final Future<void> Function(ChecklistTemplate) onEdit;
  final Future<void> Function(ChecklistTemplate) onDelete;
  final Future<void> Function(int index) onMoveUp;
  final Future<void> Function(int index) onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    period == 'opening'
                        ? 'Chưa có mục mở cửa nào'
                        : 'Chưa có mục đóng cửa nào',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                        radius: 16,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(item.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: index == 0
                                ? null
                                : () => onMoveUp(index),
                            tooltip: 'Lên',
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: index == items.length - 1
                                ? null
                                : () => onMoveDown(index),
                            tooltip: 'Xuống',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => onEdit(item),
                            tooltip: 'Sửa',
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 18, color: Colors.red.shade400),
                            onPressed: () => onDelete(item),
                            tooltip: VN.remove,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: Text(
                  period == 'opening' ? 'Thêm mục mở cửa' : 'Thêm mục đóng cửa',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

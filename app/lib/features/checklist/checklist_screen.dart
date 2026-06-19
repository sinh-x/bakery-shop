import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/checklist_entry.dart';
import '../../data/providers/checklist_provider.dart';
import '../../providers/events_provider.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/checklist.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, AutoRefreshMixin {
  late TabController _tabController;

  @override
  String screenRoutePath() => '/checklist';

  @override
  void invalidateProviders() {
    ref.invalidate(dailyChecklistProvider);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _toggle(ChecklistEntry entry) async {
    final staffName = ref.read(loggedByProvider);
    if (staffName.isEmpty) {
      showTopSnackBar(
        context,
        'Vui lòng chọn tên nhân viên trong Cài đặt trước khi đánh dấu',
        backgroundColor: Colors.orange,
      );
      return;
    }
    try {
      await ref
          .read(dailyChecklistProvider.notifier)
          .toggleEntry(entry.id, staffName);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
      }
    }
  }

  void _onAppBarMenuSelected(String value) {
    switch (value) {
      case 'history':
        context.push('/checklist/history');
        return;
      case 'config':
        context.push('/checklist/config');
        return;
      default:
        assert(() {
          debugPrint('Unknown checklist app bar menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklistAsync = ref.watch(dailyChecklistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist hàng ngày'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () =>
                ref.read(dailyChecklistProvider.notifier).refresh(),
          ),
          AppBarOverflowMenu(
            onSelected: _onAppBarMenuSelected,
            items: const [
              PopupMenuItem<String>(value: 'history', child: Text('Lịch sử')),
              PopupMenuItem<String>(value: 'config', child: Text('Cấu hình')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.wb_sunny_outlined), text: 'Mở cửa'),
            Tab(icon: Icon(Icons.nights_stay_outlined), text: 'Đóng cửa'),
          ],
        ),
      ),
      body: checklistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(dailyChecklistProvider.notifier).refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (checklist) {
          final dateLabel = _formatDate(checklist.date);

          return Column(
            children: [
              // Date header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ChecklistTab(
                      entries: checklist.openingEntries,
                      emptyMessage: 'Chưa có mục mở cửa nào',
                      onToggle: _toggle,
                    ),
                    _ChecklistTab(
                      entries: checklist.closingEntries,
                      emptyMessage: 'Chưa có mục đóng cửa nào',
                      onToggle: _toggle,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final weekdays = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'Chủ nhật',
      ];
      final weekday = weekdays[dt.weekday - 1];
      return '$weekday, ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _ChecklistTab extends StatelessWidget {
  const _ChecklistTab({
    required this.entries,
    required this.emptyMessage,
    required this.onToggle,
  });

  final List<ChecklistEntry> entries;
  final String emptyMessage;
  final Future<void> Function(ChecklistEntry) onToggle;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      );
    }

    final completedCount = entries.where((e) => e.completed).length;

    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: entries.isEmpty ? 0 : completedCount / entries.length,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 8,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$completedCount/${entries.length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ChecklistEntryTile(entry: entry, onToggle: onToggle);
            },
          ),
        ),
      ],
    );
  }
}

class _ChecklistEntryTile extends StatefulWidget {
  const _ChecklistEntryTile({required this.entry, required this.onToggle});

  final ChecklistEntry entry;
  final Future<void> Function(ChecklistEntry) onToggle;

  @override
  State<_ChecklistEntryTile> createState() => _ChecklistEntryTileState();
}

class _ChecklistEntryTileState extends State<_ChecklistEntryTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final completed = entry.completed;

    return ListTile(
      leading: _loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Checkbox(
              value: completed,
              onChanged: (_) => _handleToggle(),
              activeColor: Colors.green,
            ),
      title: Text(
        entry.templateName ?? 'Mục checklist',
        style: TextStyle(
          decoration: completed ? TextDecoration.lineThrough : null,
          color: completed ? Colors.grey : null,
          fontWeight: completed ? FontWeight.normal : FontWeight.w500,
        ),
      ),
      subtitle: completed && entry.completedBy.isNotEmpty
          ? Text(
              '${entry.completedBy}${_formatCompletedAt(entry.completedAt)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
            )
          : null,
      onTap: _loading ? null : _handleToggle,
      tileColor: completed ? Colors.green.withValues(alpha: 0.04) : null,
    );
  }

  Future<void> _handleToggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onToggle(widget.entry);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatCompletedAt(String? completedAt) {
    if (completedAt == null) return '';
    try {
      final dt = DateTime.parse(completedAt);
      return ' • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

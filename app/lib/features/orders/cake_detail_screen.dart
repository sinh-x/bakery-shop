import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/order_photo.dart';
import '../../data/models/work_item.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/order_photo_section.dart';

const _workItemStatusColors = {
  'pending': Colors.grey,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
};

const _workItemStatusRank = {
  'pending': 0,
  'working': 1,
  'ready': 2,
  'delivered': 3,
};

bool _isBackwardItem(String current, String target) =>
    (_workItemStatusRank[target] ?? 0) < (_workItemStatusRank[current] ?? 0);

Future<String?> _showItemReasonDialog(
  BuildContext context,
  String targetStatus,
) async {
  final ctrl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(VN.statusReasonTitle),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: VN.statusReasonLabel,
              hintText: VN.statusReasonHint,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            autofocus: true,
            onChanged: (_) => setS(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text(VN.confirmStatusChange),
            ),
          ],
        ),
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

class CakeDetailScreen extends ConsumerStatefulWidget {
  const CakeDetailScreen({
    super.key,
    required this.orderRef,
    required this.workItemId,
  });

  final String orderRef;
  final String workItemId;

  @override
  ConsumerState<CakeDetailScreen> createState() => _CakeDetailScreenState();
}

class _CakeDetailScreenState extends ConsumerState<CakeDetailScreen> {
  bool _transitioning = false;

  Future<void> _onTransition(WorkItem item, String targetStatus) async {
    if (_transitioning) return;
    String reason = '';
    if (_isBackwardItem(item.status, targetStatus)) {
      final r = await _showItemReasonDialog(context, targetStatus);
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .transitionStatus(item.id, targetStatus, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.workItemStatusChanged)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final photosAsync = ref.watch(orderPhotosProvider(widget.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.cakeDetail),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: VN.viewOrder,
            onPressed: () => context.push('/orders/${widget.orderRef}'),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(orderWorkItemsProvider(widget.orderRef).notifier)
                    .refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (items) {
          final item = items
              .where((i) => i.id == widget.workItemId)
              .firstOrNull;
          if (item == null) {
            return Center(
              child: Text(
                'Không tìm thấy sản phẩm',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          final photos = photosAsync.value
                  ?.where((p) {
                    final wId = p.workItemId;
                    return wId != null &&
                        wId == int.tryParse(item.id);
                  })
                  .toList() ??
              [];

          return _CakeDetailBody(
            item: item,
            photos: photos,
            baseUrl: baseUrl,
            transitioning: _transitioning,
            onTransition: (t) => _onTransition(item, t),
          );
        },
      ),
    );
  }
}

class _CakeDetailBody extends StatelessWidget {
  const _CakeDetailBody({
    required this.item,
    required this.photos,
    required this.baseUrl,
    required this.transitioning,
    required this.onTransition,
  });

  final WorkItem item;
  final List<OrderPhoto> photos;
  final String baseUrl;
  final bool transitioning;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _workItemStatusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);
    const allStatuses = ['pending', 'working', 'ready', 'delivered'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ── Status chip ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withAlpha(120)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Product info ──────────────────────────────────────────────
        Text(
          item.productName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${item.quantity} × ${formatVND(item.unitPrice)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),

        // ── Birthday / age ────────────────────────────────────────────
        if (item.isBirthday) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('🎂', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                item.age != null
                    ? '${VN.birthdayWithAge} ${item.age} tuổi'
                    : VN.birthdayWithAge,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.pink.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],

        // ── Notes ─────────────────────────────────────────────────────
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel('Ghi chú'),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.notes,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],

        // ── Per-item photos ───────────────────────────────────────────
        const SizedBox(height: 16),
        _SectionLabel(VN.perItemPhotos),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noOrderPhotos,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final photo = photos[index];
                final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
                return GestureDetector(
                  onTap: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderPhotoViewer(
                        photos: photos,
                        initialIndex: index,
                        baseUrl: baseUrl,
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // ── Status transitions ────────────────────────────────────────
        const SizedBox(height: 16),
        _SectionLabel('Chuyển trạng thái'),
        const SizedBox(height: 8),
        if (transitioning)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allStatuses.map((s) {
              final isCurrent = s == item.status;
              final color = _workItemStatusColors[s] ?? Colors.grey;
              return FilterChip(
                label: Text(workItemStatusLabel(s)),
                selected: isCurrent,
                selectedColor: color.withAlpha(40),
                checkmarkColor: color,
                side: BorderSide(
                  color: isCurrent ? color : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color: isCurrent ? color : null,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                ),
                onSelected: isCurrent ? null : (_) => onTransition(s),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

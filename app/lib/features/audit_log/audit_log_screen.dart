import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/audit_log_service.dart';
import '../../data/providers/audit_log_provider.dart';
import '../../shared/labels/audit_log.dart';
import 'widgets/audit_log_filter_panel.dart';
import 'widgets/audit_log_tile.dart';

/// Admin-only audit log screen (FR24/AC20).
///
/// Displays paginated change history with filters for user, date range, and
/// entity type (config, products, checklist, categories, staff). Access is
/// gated by the router redirect guard (Phase 7) — only admin-role users can
/// reach this route. The screen consumes [auditLogProvider] (an
/// [AuditLogNotifier] calling `GET /api/audit-log`) and renders the
/// accumulated list with a "load more" affordance.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _filtersVisible = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Only auto-load when the user has actively scrolled (currentScroll > 0)
    // and is near the bottom. This avoids auto-loading the entire dataset
    // during the initial layout pass when the first page fits in viewport
    // (currentScroll stays at 0).
    if (currentScroll > 0 &&
        maxScroll - currentScroll <= 200) {
      final asyncValue = ref.read(auditLogProvider);
      final state = asyncValue.value;
      if (state != null && state.hasMore && !asyncValue.isLoading) {
        ref.read(auditLogProvider.notifier).loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncValue = ref.watch(auditLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AuditLogLabels.screenTitle),
        actions: [
          IconButton(
            icon: Icon(
              _filtersVisible ? Icons.filter_alt : Icons.filter_alt_off,
            ),
            tooltip: AuditLogLabels.applyFilters,
            onPressed: () =>
                setState(() => _filtersVisible = !_filtersVisible),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(auditLogProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_filtersVisible)
            AuditLogFilterPanel(
              current: asyncValue.value?.filters ?? const AuditLogFilters(),
              onApply: (filters) =>
                  ref.read(auditLogProvider.notifier).applyFilters(filters),
              onClear: () =>
                  ref.read(auditLogProvider.notifier).clearFilters(),
            ),
          Expanded(child: _body(asyncValue)),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<AuditLogState> asyncValue) {
    return asyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: AuditLogLabels.errorLoad,
        onRetry: () => ref.read(auditLogProvider.notifier).refresh(),
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return _EmptyView(onRefresh: () =>
              ref.read(auditLogProvider.notifier).refresh());
        }
        return _AuditLogList(
          scrollController: _scrollController,
          state: state,
          onLoadMore: () =>
              ref.read(auditLogProvider.notifier).loadMore(),
        );
      },
    );
  }
}

/// ListView of audit log entries with a trailing "load more" indicator when
/// [AuditLogState.hasMore] is true.
class _AuditLogList extends StatelessWidget {
  const _AuditLogList({
    required this.scrollController,
    required this.state,
    required this.onLoadMore,
  });

  final ScrollController scrollController;
  final AuditLogState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final itemCount = state.items.length + (state.hasMore ? 1 : 0);
    return ListView.builder(
      controller: scrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          // Footer indicator while more pages are available.
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                onPressed: onLoadMore,
                child: const Text(AuditLogLabels.loadMore),
              ),
            ),
          );
        }
        return AuditLogTile(entry: state.items[index]);
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(AuditLogLabels.empty),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRefresh,
            child: const Text(AuditLogLabels.retry),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(AuditLogLabels.retry),
          ),
        ],
      ),
    );
  }
}
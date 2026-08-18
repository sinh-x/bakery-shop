import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/audit_log_service.dart';
import '../../data/providers/audit_log_provider.dart';
import '../../shared/labels/audit_log.dart';
import 'widgets/audit_log_empty_view.dart';
import 'widgets/audit_log_error_view.dart';
import 'widgets/audit_log_filter_panel.dart';
import 'widgets/audit_log_list.dart';

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
      error: (error, _) => AuditLogErrorView(
        message: AuditLogLabels.errorLoad,
        onRetry: () => ref.read(auditLogProvider.notifier).refresh(),
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return AuditLogEmptyView(onRefresh: () =>
              ref.read(auditLogProvider.notifier).refresh());
        }
        return AuditLogList(
          scrollController: _scrollController,
          state: state,
          onLoadMore: () =>
              ref.read(auditLogProvider.notifier).loadMore(),
        );
      },
    );
  }
}
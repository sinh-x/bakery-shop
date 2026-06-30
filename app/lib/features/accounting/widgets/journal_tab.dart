import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/accounting_service.dart';
import '../../../providers/accounting_provider.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import '../providers/journal_pagination_notifier.dart';
import 'empty_state.dart';
import 'filter_bar.dart';
import 'journal_entry_card.dart';
import 'lock_confirm_dialog.dart';

/// Base page size used by the journal tab.
const int _journalPageSize = 100;

class JournalTab extends ConsumerStatefulWidget {
  const JournalTab({super.key});

  @override
  ConsumerState<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends ConsumerState<JournalTab> {
  String? _since;
  String? _until;
  int? _accountId;
  String? _sourceType;

  JournalFilter get _filter => JournalFilter(
        since: _since,
        until: _until,
        accountId: _accountId,
        sourceType: _sourceType,
        limit: _journalPageSize,
        offset: 0,
      );

  @override
  Widget build(BuildContext context) {
    final paginationAsync =
        ref.watch(journalPaginationProvider(_filter));

    return Column(
      children: [
        FilterBar(
          since: _since,
          until: _until,
          sourceType: _sourceType,
          accountsAsync: ref.watch(accountsProvider),
          accountId: _accountId,
          onSinceChanged: (v) => setState(() => _since = v),
          onUntilChanged: (v) => setState(() => _until = v),
          onSourceTypeChanged: (v) => setState(() => _sourceType = v),
          onAccountChanged: (v) => setState(() => _accountId = v),
          onLock: _showLockDialog,
        ),
        Expanded(
          child: paginationAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(VN.apiError),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(journalPaginationProvider(_filter)),
                    child: const Text(VN.retry),
                  ),
                ],
              ),
            ),
            data: (state) {
              final loaded = state.loaded;
              if (loaded.isEmpty) {
                return const AccountingEmptyState(text: VN.accountingNoEntries);
              }
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: loaded.length,
                      itemBuilder: (context, index) =>
                          JournalEntryCard(entry: loaded[index]),
                    ),
                  ),
                  if (state.loadMoreError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Text(
                        VN.apiError,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.red),
                      ),
                    ),
                  if (state.hasMore)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: state.isLoadingMore
                            ? null
                            : () => ref
                                .read(journalPaginationProvider(_filter)
                                    .notifier)
                                .loadMore(),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          '${VN.accountingLoadMore} (${state.total - loaded.length})',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showLockDialog() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );
    if (picked == null || !mounted) return;

    final sinceStr = formatDisplay(picked.start, pattern: 'yyyy-MM-dd');
    final untilStr = formatDisplay(picked.end.add(const Duration(days: 1)), pattern: 'yyyy-MM-dd');
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => buildLockConfirmDialog(
        sinceStr: sinceStr,
        untilStr: untilStr,
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (confirmed != true) return;

    try {
      final service = ref.read(accountingServiceProvider);
      final count = await service.lockJournal(
        since: sinceStr,
        until: untilStr,
      );
      if (mounted) {
        showTopSnackBar(
          context,
          VN.accountingLockResult(count),
          backgroundColor: Colors.green,
        );
        // CQ-1: the accumulated pagination state lives in the notifier.
        // Invalidating the family re-runs build() for the current filter,
        // which replaces the accumulated list cleanly — no stale entries.
        ref.invalidate(journalPaginationProvider(_filter));
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
      }
    }
  }
}
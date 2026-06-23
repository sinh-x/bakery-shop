import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/accounting_service.dart';
import '../../../data/models/journal_entry.dart';
import '../../../providers/accounting_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import 'empty_state.dart';
import 'filter_bar.dart';
import 'journal_entry_card.dart';
import 'lock_confirm_dialog.dart';

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
  int _offset = 0;
  final int _pageSize = 100;
  List<JournalEntry> _loaded = [];
  int _total = 0;
  bool _isLoadingMore = false;

  @override
  Widget build(BuildContext context) {
    final filter = JournalFilter(
      since: _since,
      until: _until,
      accountId: _accountId,
      sourceType: _sourceType,
      limit: _pageSize,
      offset: _offset,
    );
    final journalAsync = ref.watch(journalEntriesProvider(filter));

    return Column(
      children: [
        FilterBar(
          since: _since,
          until: _until,
          sourceType: _sourceType,
          accountsAsync: ref.watch(accountsProvider),
          accountId: _accountId,
          onSinceChanged: (v) => setState(() {
            _since = v;
            _reset();
          }),
          onUntilChanged: (v) => setState(() {
            _until = v;
            _reset();
          }),
          onSourceTypeChanged: (v) => setState(() {
            _sourceType = v;
            _reset();
          }),
          onAccountChanged: (v) => setState(() {
            _accountId = v;
            _reset();
          }),
          onLock: _showLockDialog,
        ),
        Expanded(
          child: journalAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(VN.apiError),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      journalEntriesProvider(filter),
                    ),
                    child: const Text(VN.retry),
                  ),
                ],
              ),
            ),
            data: (response) {
              _total = response.total;
              if (_offset == 0) {
                _loaded = response.items;
              } else {
                _loaded.addAll(response.items);
              }
              _isLoadingMore = false;

              if (_loaded.isEmpty) {
                return const AccountingEmptyState(text: VN.accountingNoEntries);
              }
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _loaded.length,
                      itemBuilder: (context, index) =>
                          JournalEntryCard(entry: _loaded[index]),
                    ),
                  ),
                  if (_loaded.length < _total)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingMore
                            ? null
                            : () => setState(() {
                                  _isLoadingMore = true;
                                  _offset += _pageSize;
                                }),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          '${VN.accountingLoadMore} (${_total - _loaded.length})',
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

  /// Clears mutable pagination state so rapid filter changes and post-lock
  /// invalidation do not mix stale entries into `_loaded` (DG-189 m-1).
  void _reset() {
    _offset = 0;
    _loaded = [];
    _isLoadingMore = false;
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

    final sinceStr = _dateStr(picked.start);
    final untilStr = _dateStr(picked.end.add(const Duration(days: 1)));
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
        // m-1: reset mutable pagination state BEFORE invalidating the
        // provider so the refreshed result replaces `_loaded` cleanly
        // instead of appending to stale entries.
        _reset();
        ref.invalidate(journalEntriesProvider(JournalFilter(
          since: _since,
          until: _until,
          accountId: _accountId,
          sourceType: _sourceType,
          limit: _pageSize,
          offset: _offset,
        )));
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, VN.apiError, backgroundColor: Colors.red);
      }
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
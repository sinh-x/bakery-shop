import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/accounting_service.dart';
import '../../../data/models/account.dart';
import '../../../data/models/journal_entry.dart';
import '../../../providers/accounting_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

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
        _FilterBar(
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
                return const _EmptyList(text: VN.accountingNoEntries);
              }
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _loaded.length,
                      itemBuilder: (context, index) {
                        final entry = _loaded[index];
                        return _JournalEntryCard(entry: entry);
                      },
                    ),
                  ),
                  if (_loaded.length < _total)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingMore
                            ? null
                            : () {
                                setState(() {
                                  _isLoadingMore = true;
                                  _offset += _pageSize;
                                });
                              },
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

  void _reset() {
    _offset = 0;
    _loaded = [];
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(VN.accountingLockJournal),
        content: Text(
          '${VN.accountingFilterSince} $sinceStr\n'
          '${VN.accountingFilterUntil} $untilStr',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(VN.xacNhan),
          ),
        ],
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.since,
    required this.until,
    required this.sourceType,
    required this.accountsAsync,
    required this.accountId,
    required this.onSinceChanged,
    required this.onUntilChanged,
    required this.onSourceTypeChanged,
    required this.onAccountChanged,
    required this.onLock,
  });

  final String? since;
  final String? until;
  final String? sourceType;
  final AsyncValue<List<Account>> accountsAsync;
  final int? accountId;
  final ValueChanged<String?> onSinceChanged;
  final ValueChanged<String?> onUntilChanged;
  final ValueChanged<String?> onSourceTypeChanged;
  final ValueChanged<int?> onAccountChanged;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DateChip(
            label: VN.accountingFilterSince,
            value: since,
            onSelected: onSinceChanged,
          ),
          _DateChip(
            label: VN.accountingFilterUntil,
            value: until,
            onSelected: onUntilChanged,
          ),
          accountsAsync.when(
            loading: () => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (accounts) => DropdownButton<int?>(
              value: accountId,
              hint: const Text(VN.accountingFilterAccount),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text(VN.accountingFilterAccount),
                ),
                ...accounts.map(
                  (a) => DropdownMenuItem<int?>(
                    value: int.tryParse(a.id),
                    child: Text('${a.code} — ${a.name}'),
                  ),
                ),
              ],
              onChanged: onAccountChanged,
            ),
          ),
          DropdownButton<String?>(
            value: sourceType,
            hint: const Text(VN.accountingFilterSourceType),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Tất cả')),
              DropdownMenuItem<String?>(value: 'expense', child: Text('Chi phí')),
              DropdownMenuItem<String?>(
                value: 'payment_transaction',
                child: Text('Thanh toán'),
              ),
              DropdownMenuItem<String?>(value: 'order', child: Text('Đơn hàng')),
              DropdownMenuItem<String?>(
                value: 'order_cogs',
                child: Text('Giá vốn'),
              ),
              DropdownMenuItem<String?>(
                value: 'owner_capital',
                child: Text(VN.accountingOwnerCapital),
              ),
              DropdownMenuItem<String?>(
                value: 'owner_draw',
                child: Text(VN.accountingOwnerDraw),
              ),
              DropdownMenuItem<String?>(
                value: 'staff_reimburse',
                child: Text(VN.accountingStaffReimburse),
              ),
            ],
            onChanged: onSourceTypeChanged,
          ),
          FilledButton.tonalIcon(
            onPressed: onLock,
            icon: const Icon(Icons.lock_outline),
            label: const Text(VN.accountingLockJournal),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(value == null ? label : '$label: $value'),
      avatar: const Icon(Icons.calendar_today, size: 16),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) {
          onSelected(
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
    );
  }
}

class _JournalEntryCard extends StatelessWidget {
  const _JournalEntryCard({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDebit = entry.lines.fold<double>(
      0,
      (sum, l) => sum + l.debit,
    );
    final isLocked = entry.lockedAt != null && entry.lockedAt!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text(
          entry.description.isEmpty ? entry.sourceType : entry.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Row(
          children: [
            if (entry.createdAt != null) ...[
              Text(
                _formatTimestamp(entry.createdAt!),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.sourceType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
            ],
          ],
        ),
        trailing: Text(
          formatVND(totalDebit),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Tài khoản',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        VN.accountingDebit,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        VN.accountingCredit,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                ...entry.lines.map((line) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${line.accountCode ?? ''} ${line.accountName ?? ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line.debit > 0 ? formatVND(line.debit) : '—',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line.credit > 0 ? formatVND(line.credit) : '—',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ),
      ],
    );
  }
}
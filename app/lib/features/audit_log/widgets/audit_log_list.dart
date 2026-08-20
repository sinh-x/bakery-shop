import 'package:flutter/material.dart';

import '../../../data/providers/audit_log_provider.dart';
import '../../../shared/labels/audit_log.dart';
import 'audit_log_tile.dart';

/// ListView of audit log entries with a trailing "load more" indicator when
/// [AuditLogState.hasMore] is true.
class AuditLogList extends StatelessWidget {
  const AuditLogList({
    super.key,
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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/reconciliation_service.dart';
import 'reconciliation_notifier.dart';
import 'reconciliation_state.dart';

export 'reconciliation_math.dart';
export 'reconciliation_notifier.dart';
export 'reconciliation_state.dart';

final reconciliationProvider =
    NotifierProvider<ReconciliationNotifier, ReconciliationState>(
      ReconciliationNotifier.new,
    );

final reconciliationHistoryListProvider =
    FutureProvider<List<ReconciliationHistorySession>>((ref) async {
      return ref.read(reconciliationServiceProvider).getHistorySessions();
    });

final reconciliationHistoryDetailProvider =
    FutureProvider.family<ReconciliationHistoryDetail, int>((
      ref,
      sessionId,
    ) async {
      return ref
          .read(reconciliationServiceProvider)
          .getHistoryDetail(sessionId);
    });

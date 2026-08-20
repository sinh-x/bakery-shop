import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/reconciliation_service.dart';
import '../data/providers/reconciliation_state.dart';
import 'reconciliation_notifier.dart';

export 'reconciliation_notifier.dart';
export '../data/providers/reconciliation_math.dart';
export '../data/providers/reconciliation_state.dart';

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
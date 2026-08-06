/// Cash drawer transaction model (DG-343 Phase 2/6).
///
/// Mirrors each item in the JSON list returned by the backend endpoint
/// `GET /api/cash-drawer/{drawer_id}/transactions` (see
/// `src/baker/api/cash_drawer.py` `drawer_transactions` and
/// `CashDrawer.get_transactions` in `src/baker/models/cash_drawer.py`):
///
///   {
///     "id": "12",
///     "type": "cash_drawer_open",        // journal entry source_type
///     "amount": 1000000,                  // signed int (VND): + inflow, - outflow
///     "timestamp": "2026-08-01T08:00:00Z",// transaction_date fallback to created_at
///     "note": "Mở quầy sáng",             // journal entry description
///     "reference": "BKS-16-001",          // originating document (order ref / event summary)
///     "reference_detail": "Khách A",      // customer name or "staff — provider"
///     "shippingAmount": 30000             // bus-shipping portion (2200 credit)
///   }
///
/// `shippingAmount` (DG-363 Phase 3 / FR5) carries the bus-shipping portion
/// of a `payment_transaction` split into account 2200 by the backend. It is
/// non-zero only for `payment_transaction` rows with a held bus-shipping
/// amount; all other row types report `0`. The breakdown card uses it to
/// separate the shipping inflow into the `busShipping` category.
///
/// The backend computes `amount` as the net 1101 (Cash in Drawer) movement
/// (debit - credit) of the linked journal entry, so positive values are
/// inflows (cash sales, cash-in, opening balance, owner capital) and negative
/// values are outflows (cash-out, cash expenses, close-adjust shortages,
/// auto-transfer to owner). Non-cash operations (bank transfers, card
/// payments) carry no 1101 line and are excluded by the backend.
///
/// `type` is the raw journal `source_type` string; the Flutter UI maps it to
/// Vietnamese labels via `accountingSourceTypeLabel()` in
/// `vietnamese_labels.dart` (Phase 3).
///
/// Plain Dart class (no freezed codegen) — matches the `CashDrawer` and
/// `CashDrawerHistoryResponse` pattern for read-oriented models. `toJson` is
/// provided for symmetry and round-trip verification, even though the
/// client only reads these from the server (no request body needed).
library;

import '../../shared/utils/date_formatting.dart';

class CashDrawerTransaction {
  /// Backend renders `id` as a string via `str(je.id)`.
  final String id;

  /// Raw journal entry `source_type` (e.g. `cash_drawer_open`,
  /// `cash_drawer_cash_in`, `cash_drawer_cash_out`, `payment_transaction`,
  /// `expense`, `cash_drawer_close_adjust`). The UI maps this to a VN label.
  final String type;

  /// Signed net 1101 movement in VND. Positive = inflow, negative = outflow.
  final int amount;

  /// Business event date (journal `transaction_date`, falling back to
  /// `created_at` when NULL). Parsed via [parseApiDateTime].
  final DateTime? timestamp;

  /// Journal entry description; empty string when the backend has no note.
  final String note;

  /// Originating document reference (DG-343 Phase 4). For
  /// `payment_transaction` rows this is the order receiving code
  /// (`order_ref`); for `expense` rows it is the event `summary`; empty
  /// for drawer-only operations (open/cash-in/cash-out/close).
  final String reference;

  /// Secondary reference detail (DG-343 Phase 4). For
  /// `payment_transaction` rows this is the order's `customer_name`; for
  /// `expense` rows it is the "staff_name — payment_source" string parsed
  /// from the event JSON; empty for drawer-only operations.
  final String referenceDetail;

  /// Bus-shipping portion of a `payment_transaction` (DG-363 Phase 3 / FR5).
  /// Mirrors the net 2200 (Bus Shipping Held) credit the backend attaches
  /// to each payment transaction row. Zero for non-payment rows and for
  /// payments with no bus split. The breakdown card splits this amount
  /// into the `busShipping` category so it is not folded into `Bán hàng`.
  final int shippingAmount;

  const CashDrawerTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.timestamp,
    this.note = '',
    this.reference = '',
    this.referenceDetail = '',
    this.shippingAmount = 0,
  });

  /// Convenience: whether this transaction is a cash inflow (amount > 0).
  bool get isInflow => amount > 0;

  /// Convenience: whether this transaction is a cash outflow (amount < 0).
  bool get isOutflow => amount < 0;

  factory CashDrawerTransaction.fromJson(Map<String, dynamic> json) {
    return CashDrawerTransaction(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      timestamp: parseApiDateTime(json['timestamp'] as String?),
      note: (json['note'] as String?) ?? '',
      reference: (json['reference'] as String?) ?? '',
      referenceDetail: (json['referenceDetail'] as String?) ?? '',
      shippingAmount: (json['shippingAmount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'amount': amount,
        'timestamp': timestampToJson(timestamp),
        'note': note,
        'reference': reference,
        'referenceDetail': referenceDetail,
        'shippingAmount': shippingAmount,
      };

  @override
  String toString() =>
      'CashDrawerTransaction(id: $id, type: $type, amount: $amount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashDrawerTransaction &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Paginated transaction list envelope returned by
/// `GET /api/cash-drawer/{drawer_id}/transactions`.
///
///   { "total": 12, "limit": 50, "offset": 0, "items": [ ...CashDrawerTransaction... ] }
///
/// Mirrors the [CashDrawerHistoryResponse] shape so the pagination UI can
/// reuse the same infinite-scroll pattern (Phase 3).
class CashDrawerTransactionResponse {
  final int total;
  final int limit;
  final int offset;
  final List<CashDrawerTransaction> items;

  const CashDrawerTransactionResponse({
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  factory CashDrawerTransactionResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return CashDrawerTransactionResponse(
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
              .map((e) =>
                  CashDrawerTransaction.fromJson(e as Map<String, dynamic>))
              .toList()
          : const <CashDrawerTransaction>[],
    );
  }
}
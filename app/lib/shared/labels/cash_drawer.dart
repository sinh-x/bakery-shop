import 'package:bakery_app/shared/labels/accounting.dart';

/// Cash-drawer-domain Vietnamese labels for the bakery app (DG-324).
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the daily cash
/// drawer feature lives in its own domain file rather than being appended to
/// the monolithic `VN` class. Consumers import this file and use
/// `CashDrawerLabels.*` for new labels or `VN.*` for legacy labels still
/// re-exported via the per-domain label files.
class CashDrawerLabels {
  CashDrawerLabels._();

  // Knowledge base entry subtitle
  static const knowledgeBaseCashDrawerSubtitle =
      'Quỹ tiền mặt hàng ngày & chênh lệch';

  static const cashDrawerTitle = 'Tiền tại quầy';
  static const cashDrawerOpen = 'Mở quầy';
  static const cashDrawerClose = 'Đóng quầy';
  static const cashDrawerCashIn = 'Cho tiền vào quầy';
  static const cashDrawerCashOut = 'Lấy tiền khỏi quầy';
  static const cashDrawerOpeningBalance = 'Số dư đầu ngày';
  // DG-347 Phase 5: closing balance surfaced on closed drawer history rows.
  static const cashDrawerClosingBalance = 'Số dư cuối ngày';
  static const cashDrawerExpectedBalance = 'Số dư dự kiến';
  static const cashDrawerCountedAmount = 'Số tiền đếm được';
  static const cashDrawerDiscrepancy = 'Chênh lệch';
  static const cashDrawerStatus = 'Trạng thái';
  static const cashDrawerStatusOpen = 'Đang mở';
  static const cashDrawerStatusClosed = 'Đã đóng';
  // DG-347 Phase 5: removed per-accumulator labels (cashDrawerCashSales,
  // cashDrawerTienRutIn/Out, cashDrawerOwnerIn/Out, cashDrawerCashExpenses)
  // — the status card no longer shows an accumulator breakdown.
  static const cashDrawerHistory = 'Lịch sử quầy';
  static const cashDrawerNoActive = 'Không có quầy tiền mặt đang mở';
  static const cashDrawerAlreadyOpen =
      'Đã có quầy tiền mặt đang mở — phải đóng quầy hiện tại trước khi mở quầy mới.';
  static const cashDrawerAmountLabel = 'Số tiền (VND)';
  static const cashDrawerNoteLabel = 'Ghi chú (tùy chọn)';
  static const cashDrawerOpenSuccess = 'Đã mở quầy tiền mặt';
  static const cashDrawerCloseSuccess = 'Đã đóng quầy tiền mặt';
  static const cashDrawerCashInSuccess = 'Đã cho tiền vào quầy';
  static const cashDrawerCashOutSuccess = 'Đã lấy tiền khỏi quầy';
  static const cashDrawerSurplus = 'Thừa';
  static const cashDrawerShortage = 'Thiếu';
  static const cashDrawerExact = 'Khớp';

  /// FR9 carry-over proposal dialog labels.
  static const cashDrawerCarryOverTitle = 'Mang số dư sang hôm nay';
  static const cashDrawerCarryOverPrompt =
      'Quỹ hôm qua chưa đóng. Số dư dự kiến';
  static const cashDrawerCarryOverQuestion =
      'Bạn có muốn mang sang hôm nay không?';
  static const cashDrawerCarryOverAccept = 'Mang sang';
  static const cashDrawerCarryOverDecline = 'Không mang sang';

  /// DG-330: transfer proposal when opening balance < 1101 reference.
  static const cashDrawerTransferTitle = 'Chuyển tiền thừa vào quầy chủ';
  static const cashDrawerTransferQuestion =
      'Bạn có muốn chuyển số tiền thừa vào Tiền mặt chủ sở hữu?';
  static const cashDrawerTransferAccept = 'Chuyển';
  static const cashDrawerTransferDeclineBlocked =
      'Không thể mở quầy khi có chênh lệch âm chưa giải trình. '
      'Vui lòng chọn "Chuyển" hoặc liên hệ Kế toán.';

  /// DG-330: stock reconciliation confirmation when opening balance > 1101.
  static const cashDrawerStockReconTitle = 'Đối chiếu kho hàng';
  static const cashDrawerStockReconQuestion =
      'Bạn đã đối chiếu kho hàng POS chưa? Tiền thừa đến từ bán hàng?';
  static const cashDrawerStockReconAccept = 'Bán hàng';
  static const cashDrawerStockReconDecline = 'Chưa';
  static const cashDrawerExcessOwnerCapital = 'Chủ cho thêm vốn';

  /// DG-330: unidentified sale option after stock reconciliation.
  static const cashDrawerUnidentifiedSaleTitle = 'Doanh thu chưa xác định';
  static const cashDrawerUnidentifiedSaleQuestion =
      'Ghi nhận thành doanh thu chưa xác định với 50% giá vốn để dễ truy vết sau này?';
  static const cashDrawerUnidentifiedSaleAccept = 'Ghi nhận';
  static const cashDrawerUnidentifiedSaleDecline = 'Bỏ qua';

  /// DG-330: reference balance label in open dialog.
  static const cashDrawerReferenceBalance = 'Số dư kế toán 1101';

  /// DG-331 FR9: label for the previous close counted amount shown in the
  /// open dialog as a second reference point ("Số dư sau khi đóng quầy lần
  /// trước"). Follows the 1101 reference balance line.
  static const cashDrawerPreviousCloseBalance =
      'Số dư sau khi đóng quầy lần trước';

  /// Phase 4.1 F5/F6: "current balance" helper shown in the cash-in and
  /// cash-out dialogs so the owner knows how much is already in the drawer.
  static const cashDrawerCurrentBalance = 'Số dư hiện tại';

  /// DG-331: close surplus confirmation dialog labels. Shown when closing
  /// the drawer with counted > expected and the surplus has not yet been
  /// confirmed.
  static const cashDrawerCloseSurplusTitle = 'Xác nhận chênh lệch thừa';
  static const cashDrawerCloseSurplusQuestion =
      'Số tiền đếm được lớn hơn số dư dự kiến. Chủ thêm tiền mặt hay ghi nhận doanh thu chưa xác định?';
  static const cashDrawerCloseSurplusOwnerCash = 'Chủ thêm tiền mặt';
  static const cashDrawerCloseSurplusUnidentifiedSale =
      'Doanh thu chưa xác định';

  /// DG-331: close shortage confirmation dialog labels. Shown when closing
  /// the drawer with counted < expected and the shortage has not yet been
  /// confirmed.
  static const cashDrawerCloseShortageTitle = 'Xác nhận chênh lệch thiếu';
  static const cashDrawerCloseShortageQuestion =
      'Số tiền đếm được nhỏ hơn số dư dự kiến. Chủ rút tiền hay ghi nhận lỗ vốn chủ sở hữu?';
  static const cashDrawerCloseShortageOwnerWithdraw = 'Chủ rút tiền';
  static const cashDrawerCloseShortageEquityLoss = 'Lỗ vốn chủ sở hữu';

  /// DG-360 CQ-6: open-flow variants of the surplus/shortage confirmation
  /// dialogs. The close flow uses "Số dư dự kiến"/"Số tiền đếm được"; the
  /// open flow (reusing the same dialog) shows the 1101 accounting reference
  /// and the entered opening amount instead.
  static const cashDrawerOpenSurplusTitle =
      'Xác nhận chênh lệch thừa khi mở quầy';
  static const cashDrawerOpenSurplusReferenceLabel = 'Số dư kế toán 1101';
  static const cashDrawerOpenSurplusOpeningLabel = 'Số tiền mở quầy';
  static const cashDrawerOpenSurplusQuestion =
      'Số tiền mở quầy lớn hơn số dư kế toán 1101. Chủ thêm tiền mặt hay ghi nhận doanh thu chưa xác định?';

  static const cashDrawerOpenShortageTitle =
      'Xác nhận chênh lệch thiếu khi mở quầy';
  static const cashDrawerOpenShortageReferenceLabel = 'Số dư kế toán 1101';
  static const cashDrawerOpenShortageOpeningLabel = 'Số tiền mở quầy';
  static const cashDrawerOpenShortageQuestion =
      'Số tiền mở quầy nhỏ hơn số dư kế toán 1101. Chủ rút tiền hay ghi nhận lỗ vốn chủ sở hữu?';

  /// Cash-in source / cash-out destination dropdown labels (DG-330 Phase 8).
  static const cashDrawerSourceLabel = 'Nguồn tiền vào';
  static const cashDrawerDestinationLabel = 'Đích tiền ra';
  static const cashDrawerSourceOwner = 'Tiền mặt chủ sở hữu';
  static const cashDrawerSourceEmployee = 'Nhân viên';
  static const cashDrawerSourceEquity = 'Vốn chủ sở hữu';
  static const cashDrawerDestinationOwner = 'Tiền mặt chủ sở hữu';
  static const cashDrawerDestinationEmployee = 'Nhân viên ứng trước';
  static const cashDrawerStaffPickerLabel = 'Chọn nhân viên';
  static const cashDrawerStaffPickerHint = 'Chọn nhân viên';
  static const cashDrawerStaffRequired = 'Vui lòng chọn nhân viên';

  // ── Cash-drawer transaction history tab (DG-343 Phase 3) ────────────────
  /// "Chi tiết giao dịch" — the 3rd tab on the cash drawer screen (FR3).
  /// Shows the per-transaction detail list for the active or a closed drawer.
  static const cashDrawerTransactionsTab = 'Chi tiết giao dịch';

  /// Short transaction-type labels used in the per-transaction list (AC3).
  /// These are intentionally shorter than the journal `source_type` labels
  /// because each row already carries the amount, timestamp, and note — the
  /// type label is a one-word chip, not a full sentence.
  ///
  /// Mapping (journal `source_type` → short VN label):
  ///   cash_drawer_open          → Mở quầy
  ///   cash_drawer_cash_in       → Nạp tiền
  ///   cash_drawer_cash_out      → Rút tiền
  ///   payment_transaction       → Bán hàng
  ///   expense                   → Chi phí
  ///   cash_drawer_close_adjust  → Đóng quầy
  ///
  /// `owner_capital`, `owner_draw`, and `staff_reimburse` flow through the
  /// cash-in / cash-out source types in the drawer transaction list (the
  /// backend links the underlying journal entry, not the capital/draw
  /// adjustment), so they don't need a dedicated short label here. Unknown
  /// source types fall back to the raw string so the row stays visible.
  static const cashDrawerTxnTypeOpen = 'Mở quầy';
  static const cashDrawerTxnTypeCashIn = 'Nạp tiền';
  static const cashDrawerTxnTypeCashOut = 'Rút tiền';
  static const cashDrawerTxnTypeSale = 'Bán hàng';
  static const cashDrawerTxnTypeExpense = 'Chi phí';
  static const cashDrawerTxnTypeClose = 'Đóng quầy';
  // DG-363 Phase 3 (FR1): two new categories for the 2-group breakdown.
  /// "Hoàn tiền" — customer refund (payment_transaction with amount < 0).
  static const cashDrawerTxnTypeRefund = 'Hoàn tiền';

  /// "Phí ship bus" — bus-shipping portion split out of a payment inflow.
  static const cashDrawerTxnTypeBusShipping = 'Phí ship bus';

  // ── Cash-drawer transaction edit (DG-379 Phase 4.3 — FR1-FR3, AC1/AC2/AC4
  // /AC5/AC7) ────────────────────────────────────────────────────────────
  /// "Sửa giao dịch" — title of the edit-transaction dialog shown when the
  /// owner taps an open/close transaction card (AC1/AC2).
  static const cashDrawerEditTxnTitle = 'Sửa giao dịch';

  /// "Đã lưu giao dịch" — snackbar shown after a successful edit so the
  /// owner knows the journal entry + drawer balances were updated (AC7).
  static const cashDrawerEditTxnSaved = 'Đã lưu giao dịch';

  /// "Quầy đã đối soát — không thể sửa giao dịch" — lock notice shown when
  /// the owner taps a transaction belonging to a reconciled drawer (AC5).
  static const cashDrawerEditLockedReconciled =
      'Quầy đã đối soát — không thể sửa giao dịch';

  // ── Cash-drawer breakdown card (DG-359 Phase 1, DG-363 Phase 3) ────────
  /// Section title for the categorized in/out breakdown shown inside the
  /// active-drawer status card. Sits directly under the opening-balance row.
  static const cashDrawerBreakdownTitle = 'Phân tích tiền vào/ra';

  // DG-363 Phase 3 (FR1): 2-group structure headers.
  /// "Tiền vào" — header for the inflow group (Bán hàng, Nạp tiền, Mở quầy).
  static const cashDrawerBreakdownInflowGroup = 'Tiền vào';

  /// "Tiền ra" — header for the outflow group (Hoàn tiền, Chi phí, Rút tiền,
  /// Phí ship bus, Đóng quầy).
  static const cashDrawerBreakdownOutflowGroup = 'Tiền ra';

  /// Total row labels — the breakdown card footer summarises the category
  /// rows. "Tổng tiền vào" sums inflows; "Tổng tiền ra" sums outflows; their
  /// difference reconciles to the expected balance (FR3/AC3).
  static const cashDrawerBreakdownTotalIn = 'Tổng tiền vào';
  static const cashDrawerBreakdownTotalOut = 'Tổng tiền ra';

  /// "Số dư dự kiến" — the reconciled inflow − outflow total shown at the
  /// bottom of the breakdown card. Should match the status card's expected
  /// balance (FR3/AC3).
  static const cashDrawerBreakdownExpected = 'Số dư dự kiến';

  /// Count column header for the per-category transaction count.
  static const cashDrawerBreakdownCount = 'SL';

  /// DG-363 Phase 4 / FR7: placeholder shown in place of the breakdown card
  /// for closed drawers that have no persisted snapshot (e.g. drawers closed
  /// before the v097 migration backfilled snapshots). The requirements doc
  /// specifies an "N/A" / "Dữ liệu không có sẵn" display for this case.
  static const cashDrawerBreakdownSnapshotNa = 'Dữ liệu không có sẵn';

  /// Map a cash-drawer transaction `type` (journal `source_type`) to the
  /// short Vietnamese label used in the transaction list rows (AC3).
  ///
  /// Falls back to [AccountingLabels.accountingSourceTypeLabel] (and then
  /// the raw `sourceType`) so unknown source types remain visible rather
  /// than blank. Kept separate from [AccountingLabels.accountingSourceTypeLabel]
  /// because the transaction list uses the short chip-style labels above
  /// while the journal filter uses the longer accounting-style labels.
  static String cashDrawerTxnTypeLabel(String sourceType) {
    switch (sourceType) {
      case 'cash_drawer_open':
        return cashDrawerTxnTypeOpen;
      case 'cash_drawer_cash_in':
        return cashDrawerTxnTypeCashIn;
      case 'cash_drawer_cash_out':
        return cashDrawerTxnTypeCashOut;
      case 'payment_transaction':
        return cashDrawerTxnTypeSale;
      case 'expense':
        return cashDrawerTxnTypeExpense;
      case 'cash_drawer_close_adjust':
        return cashDrawerTxnTypeClose;
      default:
        return AccountingLabels.accountingSourceTypeLabel(sourceType);
    }
  }
}
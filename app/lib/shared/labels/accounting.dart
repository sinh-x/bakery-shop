/// Accounting-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the accounting
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class. Consumers import this file and use
/// `AccountingLabels.*` for accounting-domain strings.
class AccountingLabels {
  AccountingLabels._();

  // Accounting
  static const accountingTitle = 'Kế toán';
  static const accountingTabAccounts = 'Tài khoản';
  static const accountingTabJournal = 'Sổ nhật ký';
  static const accountingTabBalances = 'Số dư';
  static const accountingLockJournal = 'Khóa sổ';
  static const accountingLockConfirm = 'Khóa tất cả bút toán trong khoảng này?';
  static const accountingLockSuccess = 'Đã khóa sổ';
  static const accountingFilterSince = 'Từ ngày';
  static const accountingFilterUntil = 'Đến ngày';
  static const accountingFilterAccount = 'Tài khoản';
  static const accountingFilterSourceType = 'Loại giao dịch';
  static const accountingNoEntries = 'Không có bút toán nào';
  static const accountingDebit = 'Nợ';
  static const accountingCredit = 'Có';
  static const accountingBalance = 'Số dư';
  static const accountingOwnerCapital = 'Vốn chủ sở hữu vào';
  static const accountingOwnerDraw = 'Rút vốn';
  static const accountingStaffReimburse = 'Hoàn ứng';
  static const accountingLocked = 'Đã khóa';
  static const accountingUnlocked = 'Chưa khóa';
  static const accountingLoadMore = 'Tải thêm';

  /// Generic "load more" label for paginated list screens (DG-409 Phase 4 —
  /// products, customers, order history). Reused across domains so the
  /// pagination affordance stays consistent.
  static const loadMore = 'Tải thêm';

  static const accountingNoAccounts = 'Không có tài khoản';
  static const accountingNoBalances = 'Không có số dư';
  static const accountingSourceTypeAll = 'Tất cả';
  static const accountingSourceTypeExpense = 'Chi phí';
  static const accountingSourceTypePayment = 'Thanh toán';
  static const accountingSourceTypeOrder = 'Đơn hàng';
  static const accountingSourceTypeCogs = 'Giá vốn';
  static const accountingSourceTypeShippingHold = 'Ship bus giữ hộ';
  static const accountingSourceTypeShippingRelease = 'Trả ship bus';

  // Account type labels (account_type_helper.dart)
  static const accountingTypeAsset = 'Tài sản';
  static const accountingTypeLiability = 'Nợ phải trả';
  static const accountingTypeEquity = 'Vốn chủ sở hữu';
  static const accountingTypeIncome = 'Doanh thu';
  static const accountingTypeExpense = 'Chi phí';

  static String accountingLockResult(int count) => 'Đã khóa $count bút toán';

  /// Map a journal entry ``sourceType`` to a Vietnamese label.
  ///
  /// Falls back to the raw ``sourceType`` when no mapping exists so unknown
  /// source types remain visible rather than blank.
  static String accountingSourceTypeLabel(String sourceType) {
    switch (sourceType) {
      case 'expense':
        return accountingSourceTypeExpense;
      case 'payment_transaction':
        return accountingSourceTypePayment;
      case 'order':
        return accountingSourceTypeOrder;
      case 'order_cogs':
        return accountingSourceTypeCogs;
      case 'order_shipping_hold':
        return accountingSourceTypeShippingHold;
      case 'order_shipping_release':
        return accountingSourceTypeShippingRelease;
      case 'owner_capital':
        return accountingOwnerCapital;
      case 'owner_draw':
        return accountingOwnerDraw;
      case 'staff_reimburse':
        return accountingStaffReimburse;
      case 'cash_drawer_open':
        return accountingSourceTypeCashDrawerOpen;
      case 'cash_drawer_cash_in':
        return accountingSourceTypeCashDrawerCashIn;
      case 'cash_drawer_cash_out':
        return accountingSourceTypeCashDrawerCashOut;
      case 'cash_drawer_close_adjust':
        return accountingSourceTypeCashDrawerCloseAdjust;
      default:
        return sourceType;
    }
  }

  // Cash-drawer journal source types (extend the accounting source-type
  // vocabulary) — used by the journal filter and drawer movement history.
  // Kept here so the shared [accountingSourceTypeLabel] mapping resolves
  // cash-drawer source types in both the accounting journal filter and the
  // cash-drawer transaction history (see CashDrawerLabels).
  static const accountingSourceTypeCashDrawerOpen = 'Mở quầy tiền mặt';
  static const accountingSourceTypeCashDrawerCashIn = 'Cho tiền vào quầy';
  static const accountingSourceTypeCashDrawerCashOut = 'Lấy tiền khỏi quầy';
  static const accountingSourceTypeCashDrawerCloseAdjust =
      'Đóng quầy — điều chỉnh chênh lệch';
}
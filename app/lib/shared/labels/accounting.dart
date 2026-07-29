export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Accounting-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy for the accounting
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class. Consumers import this file and use
/// `AccountingLabels.*` for new labels or `VN.*` for legacy labels re-exported
/// above.
class AccountingLabels {
  AccountingLabels._();

  // Accounting screen
  static const accountingTitle = 'Kế toán';
  static const accountingTabAccounts = 'Tài khoản';
  static const accountingTabJournal = 'Sổ nhật ký';
  static const accountingTabBalances = 'Số dư';
  static const accountingLockJournal = 'Khóa sổ';
  static const accountingLockConfirm =
      'Khóa tất cả bút toán trong khoảng này?';
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
  static const accountingNoAccounts = 'Không có tài khoản';
  static const accountingNoBalances = 'Không có số dư';
  static const accountingSourceTypeAll = 'Tất cả';
  static const accountingSourceTypeExpense = 'Chi phí';
  static const accountingSourceTypePayment = 'Thanh toán';
  static const accountingSourceTypeOrder = 'Đơn hàng';
  static const accountingSourceTypeCogs = 'Giá vốn';
  static const accountingSourceTypeShippingHold = 'Ship bus giữ hộ';
  static const accountingSourceTypeShippingRelease = 'Trả ship bus';

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
      default:
        return sourceType;
    }
  }

  // Account type labels (account_type_helper.dart)
  static const accountingTypeAsset = 'Tài sản';
  static const accountingTypeLiability = 'Nợ phải trả';
  static const accountingTypeEquity = 'Vốn chủ sở hữu';
  static const accountingTypeIncome = 'Doanh thu';
  static const accountingTypeExpense = 'Chi phí';

  static String accountingLockResult(int count) =>
      'Đã khóa $count bút toán';

  // Expenses
  static const expenseTitle = 'Chi phí';
  static const expenseFormSection = 'Nhập chi phí';
  static const expenseHistorySection = 'Lịch sử chi phí';
  static const expenseAmountLabel = 'Số tiền (VND)';
  static const expenseCategoryLabel = 'Danh mục chi phí';
  static const expenseCategoryHint = 'Chọn danh mục chi phí';
  static const expensePaymentMethodLabel = 'Phương thức thanh toán';
  static const expenseVendorLabel = 'Nhà cung cấp';
  static const expenseNoteLabel = 'Ghi chú';
  static const expenseStaffNameLabel = 'Nhân viên';
  static const expensePaidByNameLabel = 'Người chi trả';
  static const expenseLoggedByLabel = 'Người ghi nhận';
  static const expenseCategoryIngredient = 'Nguyên liệu';
  static const expenseCategoryPackaging = 'Bao bì';
  static const expenseCategoryDelivery = 'Vận chuyển';
  static const expenseCategoryUtilities = 'Điện/nước';
  static const expenseCategoryTools = 'Dụng cụ';
  static const expenseCategoryRepair = 'Sửa chữa';
  static const expenseCategorySalaryAllowance = 'Lương/phụ cấp';
  static const expenseCategoryOther = 'Khác';

  // Expense subcategories (DG-302 Phase 3) — Nguyên liệu & Bao bì
  static const expenseSubcategoryEggs = 'Trứng';
  static const expenseSubcategoryCream = 'Kem';
  static const expenseSubcategoryFlour = 'Bột';
  static const expenseSubcategoryOtherAdditives = 'Phụ gia khác';
  static const expenseSubcategoryBoxAndBase = 'Hộp & đế';
  static const expenseSubcategoryAccessories = 'Phụ kiện';
  static const expenseSubcategoryWrap = 'Bọc nilon';

  // Expense subcategory form / report labels
  static const expenseSubcategoryLabel = 'Danh mục con';
  static const expenseSubcategoryHint = 'Chọn danh mục con';
  static const expenseSubcategoryNone = '—';
  static const expenseSaveAction = 'Lưu chi phí';
  static const expenseAddAction = 'Thêm chi phí';
  static const expenseUpdateAction = 'Cập nhật chi phí';
  static const expenseCancelEditAction = 'Hủy sửa';
  static const expenseApplyFiltersAction = 'Áp dụng lọc';
  static const expenseResetFiltersAction = 'Xóa lọc';
  static const expenseSearchLabel =
      'Tìm theo nội dung, nhà cung cấp, người ghi, người trả';
  static const expenseSinceLabel = 'Từ ngày';
  static const expenseUntilLabel = 'Đến ngày';
  static const expenseDateLabel = 'Ngày chi';
  static const expenseTimeLabel = 'Giờ chi';
  static const expenseNoHistory = 'Chưa có chi phí phù hợp bộ lọc';
  static const expenseAmountValidationMessage =
      'Số tiền phải là số nguyên VND lớn hơn 0';
  static const expenseStaffNameRequiredForAdvance =
      'Tên nhân viên là bắt buộc khi chọn Nhân viên ứng trước';
  static const expensePayerConfirmTitle = 'Xác nhận người chi trả';
  static const expensePayerConfirmPrompt =
      'Bạn chưa chọn Người chi trả. Dùng tên nhân viên làm người chi trả?';
  static const expensePayerUseStaff = 'Dùng tên nhân viên';
  static const expensePayerEnterCustom = 'Nhập tên khác';
  static const expensePayerCustomHint = 'Nhập tên người chi trả';
  static const expenseEmptyStaffWarning =
      'Vui lòng cài đặt tên nhân viên trong Cài đặt trước khi nhập chi phí.';

  // Payment sources
  static const expensePaymentSourceLabel = 'Nguồn tiền chi';
  static const paymentSourceShopCash = 'Shop tiền mặt';
  static const paymentSourcePhuongVCB = 'TK Phượng VCB';
  static const paymentSourceAnVCB = 'TK Ân VCB';
  static const paymentSourceStaffAdvance = 'Nhân viên ứng trước';

  // Target bank account selector for payment transactions (DG-244 Phase 2)
  static const paymentTargetAccountLabel = 'TK đích';
  static const paymentNoAccount = 'Chưa chọn';

  // Reimbursed
  static const reimbursedYes = 'Đã hoàn lại';
  static const reimbursedNo = 'Chưa hoàn lại';

  // Expense debt status (DG-212 Phase 3)
  static const debtStatusUnpaid = 'Chưa trả';
  static const debtStatusPaid = 'Đã trả';
  static const debtStatusPartial = 'Trả một phần';
  static const expenseCreditorLabel = 'Chủ nợ';
  static const expenseVendorAutocompleteHint =
      'Chọn từ nhà cung cấp đã dùng';
  static const expenseDebtVendorRequired =
      'Chủ nợ là bắt buộc khi chọn phương thức Nợ';

  // Debt list / settlement screens (DG-212 Phase 4)
  static const debtListTitle = 'Danh sách công nợ';
  static const debtListEmpty = 'Chưa có công nợ nào';
  static const debtListTotalOwed = 'Tổng còn nợ';
  static const debtListFilterStatusLabel = 'Trạng thái';
  static const debtListFilterAll = 'Tất cả';
  static const debtListCreditorTotal = 'Tổng nợ';
  static const debtListDebtCount = 'Số khoản nợ';
  static const debtListItemAmount = 'Tiền nợ';
  static const debtListItemSettled = 'Đã trả';
  static const debtListItemRemaining = 'Còn lại';
  static const debtListOpenSettlement = 'Thanh toán';
  static const debtListLoadError = 'Không tải được danh sách công nợ';

  // Debt settlement screen
  static const debtSettlementTitle = 'Thanh toán công nợ';
  static const debtSettlementAmountLabel = 'Số tiền thanh toán';
  static const debtSettlementAmountHint = 'Nhập số VND cần thanh toán';
  static const debtSettlementPaymentMethodLabel = 'Phương thức thanh toán';
  static const debtSettlementPaymentSourceLabel = 'Nguồn tiền';
  static const debtSettlementNoteLabel = 'Ghi chú';
  static const debtSettlementNoteHint = 'Ghi chú thanh toán (tùy chọn)';
  static const debtSettlementSaveAction = 'Xác nhận thanh toán';
  static const debtSettlementAmountRequired =
      'Vui lòng nhập số tiền thanh toán';
  static const debtSettlementAmountInvalid = 'Số tiền không hợp lệ';
  static const debtSettlementAmountExceedsRemaining =
      'Số thanh toán vượt quá nợ còn lại';
  static const debtSettlementPaymentSourceRequired = 'Nguồn tiền là bắt buộc';
  static const debtSettlementSuccess = 'Đã thanh toán công nợ';
  static const debtSettlementFailure = 'Thanh toán công nợ thất bại';
  static const debtSettlementRemainingLabel = 'Còn lại sau thanh toán';
  static const debtSettlementSummary = 'Thông tin công nợ';
  static const debtSettlementCreditor = 'Chủ nợ';
  static const debtSettlementTotalDebt = 'Tổng nợ ban đầu';
  static const debtSettlementSettledSoFar = 'Đã thanh toán';
}
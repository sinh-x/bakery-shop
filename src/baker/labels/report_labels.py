"""Vietnamese label constants for the ``baker report`` CLI group (DG-323).

Centralizes all user-facing Vietnamese strings used by the report group so
report.py and any other consumers avoid hardcoded English/VN fallbacks.
"""

# --- Report Title Labels ---
TRIAL_BALANCE_TITLE = "Bảng cân đối thử"
INCOME_STATEMENT_TITLE = "Báo cáo kết quả hoạt động kinh doanh"
INCOME_STATEMENT_DUE_DATE_TITLE = "Báo cáo kết quả hoạt động kinh doanh (theo ngày đến hạn)"
BALANCE_SHEET_TITLE = "Bảng cân đối kế toán"
GENERAL_LEDGER_TITLE = "Sổ cái"
ACCOUNT_LEDGER_TITLE = "Sổ chi tiết tài khoản"
EXPENSE_BY_CATEGORY_TITLE = "Chi phí theo danh mục"
COGS_AUDIT_TITLE = "Kiểm tra giá vốn"
ORDER_STATUS_TITLE = "Báo cáo trạng thái đơn hàng"
CASHFLOW_TITLE = "Báo cáo lưu chuyển tiền tệ (Phương pháp trực tiếp)"

# --- Column / Section Header Labels ---
LBL_CODE = "Mã"
LBL_ACCOUNT = "Tài khoản"
LBL_TYPE = "Loại"
LBL_DEBIT = "Nợ"
LBL_CREDIT = "Có"
LBL_TOTALS = "TỔNG CỘNG"
LBL_REVENUE = "Doanh thu"
LBL_COGS_5900 = "Giá vốn hàng bán (5900)"
LBL_GROSS_PROFIT = "Lợi nhuận gộp"
LBL_MARKUP_TRUNG_BAY = "Chênh lệch giá (trưng bày)"
LBL_OPERATING_EXPENSES = "Chi phí hoạt động"
LBL_NET_INCOME = "Lợi nhuận thuần"
LBL_ASSETS = "Tài sản"
LBL_LIABILITIES = "Nợ phải trả"
LBL_EQUITY = "Vốn chủ sở hữu"
LBL_TOTAL_ASSETS = "Tổng tài sản"
LBL_TOTAL_LIABILITIES_EQUITY = "Tổng nợ phải trả và vốn chủ sở hữu"
LBL_CATEGORY = "Danh mục"
LBL_TOTAL = "Tổng"
LBL_TOTAL_UPPER = "TỔNG"
LBL_UNCATEGORIZED = "(chưa phân loại)"
LBL_ORDER = "Đơn hàng"
LBL_ORDER_REF = "Mã ĐH"
LBL_RATIO = "Tỷ lệ"
LBL_STATUS = "Trạng thái"
LBL_DELIVERY_TYPE = "Loại giao hàng"
LBL_COUNT = "Số lượng"
LBL_VALUE = "Giá trị"
LBL_SUBTOTAL = "tổng phụ"
LBL_GRAND_TOTAL = "TỔNG CỘNG"
LBL_ORDERS = "Đơn hàng:"
LBL_DR = "Nợ"
LBL_CR = "Có"
LBL_PERIOD = "Kỳ:"
LBL_SOURCE = "nguồn="
LBL_LOCKED = "ĐÃ KHÓA"
LBL_NONE = "(trống)"
LBL_NO_ACTIVITY = "(không có hoạt động)"
LBL_SUBTOTAL_UPPER = "Tổng phụ"
LBL_OPENING_BALANCE = "Số dư đầu kỳ"
LBL_CLOSING_BALANCE = "Số dư cuối kỳ"
LBL_NET_CASH_FLOW = "Dòng tiền thuần"
LBL_RECONCILIATION = "Đối chiếu"
LBL_TOTAL_INFLOWS = "Tổng dòng tiền vào"
LBL_TOTAL_OUTFLOWS = "Tổng dòng tiền ra"
LBL_NET_OPERATING_CASHFLOW = "Dòng tiền thuần từ hoạt động kinh doanh"
LBL_NET_INVESTING_CASHFLOW = "Dòng tiền thuần từ hoạt động đầu tư"
LBL_NET_FINANCING_CASHFLOW = "Dòng tiền thuần từ hoạt động tài chính"

# --- Section Titles (Cashflow) ---
LBL_OPERATING_ACTIVITIES = "Hoạt động kinh doanh"
LBL_CASH_FROM_CUSTOMERS = "Tiền từ khách hàng"
LBL_CASH_PAID_SUPPLIERS = "Tiền trả cho nhà cung cấp/nhân viên"
LBL_INVESTING_ACTIVITIES = "Hoạt động đầu tư"
LBL_FINANCING_ACTIVITIES = "Hoạt động tài chính"
LBL_PER_ACCOUNT_BREAKDOWN = "Phân tích theo tài khoản"
LBL_INFLOWS = "Dòng vào"
LBL_OUTFLOWS = "Dòng ra"
LBL_NET = "Thuần"
LBL_OPENING = "Đầu kỳ"
LBL_CLOSING = "Cuối kỳ"
LBL_RECONCILIATION_DETAIL = "Đối chiếu (cuối kỳ - đầu kỳ)"

# --- Account Type Labels (map from DB type -> VN display) ---
ACCOUNT_TYPE_LABELS = {
    "asset": "Tài sản",
    "liability": "Nợ phải trả",
    "equity": "Vốn chủ sở hữu",
    "income": "Doanh thu",
    "expense": "Chi phí",
}

# --- COGS Audit Status Labels ---
COGS_STATUS_LABELS = {
    "ok": "đạt",
    "missing": "thiếu",
    "zero-cost": "giá vốn 0",
    "low": "thấp",
}

# --- Order Status Labels (map from DB status value -> VN display) ---
ORDER_STATUS_LABELS = {
    "new": "mới",
    "confirmed": "đã xác nhận",
    "in_progress": "đang thực hiện",
    "ready": "sẵn sàng",
    "delivered": "đã giao",
    "completed": "hoàn thành",
    "cancelled": "đã hủy",
}

# --- Empty / No-Data Messages ---
MSG_NO_JOURNAL_ENTRIES = "(không có bút toán trong khoảng)"
MSG_NO_JOURNAL_LINES_ACCOUNT = "(không có dòng sổ cái cho tài khoản này trong khoảng)"
MSG_NO_EXPENSE_ENTRIES = "(không có bút toán chi phí trong khoảng)"
MSG_NO_ORDERS = "(không có đơn hàng đã giao/hoàn thành trong khoảng)"
MSG_ALL_TIME = "Tất cả"

# --- Reconciliation Labels ---
LBL_RECONCILE_OK = "ĐẠT"
LBL_RECONCILE_MISMATCH = "KHÔNG KHỚP"
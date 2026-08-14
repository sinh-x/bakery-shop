/// Display mode for the order-breakdown matrix (DG-391 Phase 3 / FR2 / AC2).
///
/// Each mode selects which metric is rendered in each matrix cell:
/// - [OrderBreakdownMode.count] — order count only.
/// - [OrderBreakdownMode.countRevenue] — order count + revenue (VND). This
///   is the default.
/// - [OrderBreakdownMode.countRevenueShare] — order count + revenue +
///   revenue share (% of the period's total revenue across all cells).
enum OrderBreakdownMode {
  count,
  countRevenue,
  countRevenueShare,
}
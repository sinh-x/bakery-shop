export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Customer-domain labels (DG-206 Phase 2).
///
/// New customer-facing copy lives here, not in the monolithic `VN` class
/// (per §5 Label Organization). Consumers import this file and use
/// `CustomersLabels.*` for new labels or `VN.*` for legacy labels re-exported
/// above.
class CustomersLabels {
  /// Suffix label for the per-year order count shown on customer cards.
  /// Displayed as "$count $label" e.g. "12 đơn/năm".
  static const orderCountThisYearSuffix = 'đơn/năm';

  /// Tooltip for the phone count badge on customer list avatars.
  static const phoneCountBadgeTooltip = 'Số điện thoại';

  /// Fallback name when a customer has no name set.
  static const customerNoName = 'Không tên';
}
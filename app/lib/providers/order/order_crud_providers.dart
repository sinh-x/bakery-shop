// Barrel file — re-exports the order CRUD providers split into per-domain
// files (DG-308 Phase 4.2 / FR-FL-3). Existing consumers that import
// `order_crud_providers.dart` continue to work without changes.
export '../../data/providers/order/order_detail_notifier.dart';
export '../../data/providers/order/order_list_providers.dart';
export '../../data/providers/order/order_payment_transaction_providers.dart';
export '../../data/providers/order/order_photo_providers.dart';
export '../../data/providers/order/order_work_item_providers.dart';
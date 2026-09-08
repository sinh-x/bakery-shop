/// Typed read-only contract for `GET /api/orders/{ref}/inventory-audit`.
class OrderInventoryAuditPage {
  const OrderInventoryAuditPage({
    required this.items,
    required this.total,
    required this.hasMore,
    required this.limit,
    required this.offset,
  });

  final List<OrderInventoryAuditEntry> items;
  final int total;
  final bool hasMore;
  final int limit;
  final int offset;

  factory OrderInventoryAuditPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return OrderInventoryAuditPage(
      items: rawItems
          .map(
            (item) =>
                OrderInventoryAuditEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      limit: (json['limit'] as num?)?.toInt() ?? 100,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

class OrderInventoryAuditEntry {
  const OrderInventoryAuditEntry({
    required this.id,
    required this.operationId,
    required this.orderId,
    required this.orderRef,
    required this.trigger,
    required this.action,
    required this.actor,
    required this.createdAt,
    required this.outcome,
    required this.reasonCode,
    required this.item,
    required this.before,
    required this.after,
    required this.reconciliationSessionIds,
    required this.reconciliationLineIds,
    required this.reconciliationSaleRowIds,
    this.statusBefore,
    this.statusAfter,
    this.detail,
    this.requestedDelta,
    this.appliedDelta,
    this.stockMovementId,
    this.negativeMovementId,
    this.relatedEntryId,
    this.reconciliationSessionId,
  });

  final int id;
  final String operationId;
  final int orderId;
  final String orderRef;
  final String trigger;
  final String action;
  final String? statusBefore;
  final String? statusAfter;
  final OrderInventoryAuditActor actor;
  final DateTime createdAt;
  final String outcome;
  final String reasonCode;
  final String? detail;
  final OrderInventoryAuditItem item;
  final int? requestedDelta;
  final int? appliedDelta;
  final OrderInventorySnapshot before;
  final OrderInventorySnapshot after;
  final int? stockMovementId;
  final int? negativeMovementId;
  final int? relatedEntryId;
  final int? reconciliationSessionId;
  final List<int> reconciliationSessionIds;
  final List<int> reconciliationLineIds;
  final List<int> reconciliationSaleRowIds;

  factory OrderInventoryAuditEntry.fromJson(Map<String, dynamic> json) {
    return OrderInventoryAuditEntry(
      id: (json['id'] as num).toInt(),
      operationId: json['operationId'] as String,
      orderId: (json['orderId'] as num).toInt(),
      orderRef: json['orderRef'] as String,
      trigger: json['trigger'] as String,
      action: json['action'] as String,
      statusBefore: json['statusBefore'] as String?,
      statusAfter: json['statusAfter'] as String?,
      actor: OrderInventoryAuditActor.fromJson(
        json['actor'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      outcome: json['outcome'] as String,
      reasonCode: json['reasonCode'] as String,
      detail: json['detail'] as String?,
      item: OrderInventoryAuditItem.fromJson(
        json['item'] as Map<String, dynamic>,
      ),
      requestedDelta: (json['requestedDelta'] as num?)?.toInt(),
      appliedDelta: (json['appliedDelta'] as num?)?.toInt(),
      before: OrderInventorySnapshot.fromJson(
        json['before'] as Map<String, dynamic>,
      ),
      after: OrderInventorySnapshot.fromJson(
        json['after'] as Map<String, dynamic>,
      ),
      stockMovementId: (json['stockMovementId'] as num?)?.toInt(),
      negativeMovementId: (json['negativeMovementId'] as num?)?.toInt(),
      relatedEntryId: (json['relatedEntryId'] as num?)?.toInt(),
      reconciliationSessionId: (json['reconciliationSessionId'] as num?)
          ?.toInt(),
      reconciliationSessionIds: _intList(json['reconciliationSessionIds']),
      reconciliationLineIds: _intList(json['reconciliationLineIds']),
      reconciliationSaleRowIds: _intList(json['reconciliationSaleRowIds']),
    );
  }
}

class OrderInventoryAuditActor {
  const OrderInventoryAuditActor({
    required this.identifier,
    this.username,
    this.staffId,
    this.staffName,
    this.role,
  });

  final String identifier;
  final String? username;
  final int? staffId;
  final String? staffName;
  final String? role;

  String get displayName => staffName?.trim().isNotEmpty == true
      ? staffName!
      : username?.trim().isNotEmpty == true
      ? username!
      : identifier;

  factory OrderInventoryAuditActor.fromJson(Map<String, dynamic> json) {
    return OrderInventoryAuditActor(
      identifier: json['identifier'] as String,
      username: json['username'] as String?,
      staffId: (json['staffId'] as num?)?.toInt(),
      staffName: json['staffName'] as String?,
      role: json['role'] as String?,
    );
  }
}

class OrderInventoryAuditItem {
  const OrderInventoryAuditItem({
    this.orderItemId,
    this.productId,
    this.productCode,
    this.productName,
    this.isGift,
    this.isDisplay,
    this.source,
    this.requestedQuantity,
    this.priceChipId,
    this.priceChipLabel,
    this.useInventoryPresent,
    this.useInventoryValue,
    this.resolvedBucket,
    this.resolvedPriceChipId,
    this.resolvedPriceChipLabel,
    this.resolvedUnitPrice,
  });

  final int? orderItemId;
  final int? productId;
  final String? productCode;
  final String? productName;
  final bool? isGift;
  final bool? isDisplay;
  final String? source;
  final int? requestedQuantity;
  final int? priceChipId;
  final String? priceChipLabel;
  final bool? useInventoryPresent;
  final bool? useInventoryValue;
  final String? resolvedBucket;
  final int? resolvedPriceChipId;
  final String? resolvedPriceChipLabel;
  final int? resolvedUnitPrice;

  String? get chipLabel => resolvedPriceChipLabel ?? priceChipLabel;

  factory OrderInventoryAuditItem.fromJson(Map<String, dynamic> json) {
    return OrderInventoryAuditItem(
      orderItemId: (json['orderItemId'] as num?)?.toInt(),
      productId: (json['productId'] as num?)?.toInt(),
      productCode: json['productCode'] as String?,
      productName: json['productName'] as String?,
      isGift: json['isGift'] as bool?,
      isDisplay: json['isDisplay'] as bool?,
      source: json['source'] as String?,
      requestedQuantity: (json['requestedQuantity'] as num?)?.toInt(),
      priceChipId: (json['priceChipId'] as num?)?.toInt(),
      priceChipLabel: json['priceChipLabel'] as String?,
      useInventoryPresent: json['useInventoryPresent'] as bool?,
      useInventoryValue: json['useInventoryValue'] as bool?,
      resolvedBucket: json['resolvedBucket'] as String?,
      resolvedPriceChipId: (json['resolvedPriceChipId'] as num?)?.toInt(),
      resolvedPriceChipLabel: json['resolvedPriceChipLabel'] as String?,
      resolvedUnitPrice: (json['resolvedUnitPrice'] as num?)?.toInt(),
    );
  }
}

class OrderInventorySnapshot {
  const OrderInventorySnapshot({this.fifoAvailable, this.negative, this.net});

  final int? fifoAvailable;
  final int? negative;
  final int? net;

  factory OrderInventorySnapshot.fromJson(Map<String, dynamic> json) {
    return OrderInventorySnapshot(
      fifoAvailable: (json['fifoAvailable'] as num?)?.toInt(),
      negative: (json['negative'] as num?)?.toInt(),
      net: (json['net'] as num?)?.toInt(),
    );
  }
}

List<int> _intList(dynamic value) => value is List
    ? value.map((item) => (item as num).toInt()).toList(growable: false)
    : const <int>[];

import 'package:bakery_app/data/models/order_inventory_audit.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entryJson() => <String, dynamic>{
  'id': 42,
  'operationId': 'operation-1',
  'orderId': 17,
  'orderRef': 'ORD-017',
  'trigger': 'status_action',
  'action': 'inventory_deduct',
  'statusBefore': 'new',
  'statusAfter': 'confirmed',
  'actor': <String, dynamic>{
    'identifier': 'cashier',
    'username': 'cashier',
    'staffId': 3,
    'staffName': 'Thu ngân',
    'role': 'staff',
  },
  'createdAt': '2026-09-04T03:00:00Z',
  'outcome': 'applied',
  'reasonCode': 'eligible_display_item',
  'detail': null,
  'item': <String, dynamic>{
    'orderItemId': 91,
    'productId': 31,
    'productCode': 'TB-31',
    'productName': 'Bánh trưng bày',
    'isGift': false,
    'isDisplay': true,
    'source': 'Tại tiệm - POS',
    'requestedQuantity': 2,
    'priceChipId': 9,
    'priceChipLabel': 'Miếng lớn',
    'useInventoryPresent': true,
    'useInventoryValue': true,
    'resolvedBucket': 'price_chip',
    'resolvedPriceChipId': 9,
    'resolvedPriceChipLabel': 'Miếng lớn',
    'resolvedUnitPrice': 45000,
  },
  'requestedDelta': -2,
  'appliedDelta': -2,
  'before': <String, dynamic>{'fifoAvailable': 5, 'negative': 0, 'net': 5},
  'after': <String, dynamic>{'fifoAvailable': 3, 'negative': 0, 'net': 3},
  'stockMovementId': 701,
  'negativeMovementId': null,
  'relatedEntryId': null,
  'reconciliationSessionId': 12,
  'reconciliationSessionIds': <int>[12],
  'reconciliationLineIds': <int>[33],
  'reconciliationSaleRowIds': <int>[44],
};

void main() {
  test('parses camelCase audit envelope, snapshots, and identifiers', () {
    final page = OrderInventoryAuditPage.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[_entryJson()],
      'total': 1,
      'hasMore': false,
      'limit': 100,
      'offset': 0,
    });

    final entry = page.items.single;
    expect(page.total, 1);
    expect(page.limit, 100);
    expect(entry.operationId, 'operation-1');
    expect(entry.createdAt.isUtc, isTrue);
    expect(entry.actor.displayName, 'Thu ngân');
    expect(entry.item.chipLabel, 'Miếng lớn');
    expect(entry.before.net, 5);
    expect(entry.after.fifoAvailable, 3);
    expect(entry.reconciliationSessionIds, <int>[12]);
    expect(entry.reconciliationLineIds, <int>[33]);
    expect(entry.reconciliationSaleRowIds, <int>[44]);
  });

  test('parses an empty envelope and explicit nullable snapshots', () {
    final page = OrderInventoryAuditPage.fromJson(<String, dynamic>{
      'items': <dynamic>[],
      'total': 0,
      'hasMore': false,
      'limit': 100,
      'offset': 0,
    });
    final snapshot = OrderInventorySnapshot.fromJson(<String, dynamic>{
      'fifoAvailable': null,
      'negative': null,
      'net': null,
    });

    expect(page.items, isEmpty);
    expect(snapshot.net, isNull);
  });
}

import 'package:bakery_app/data/models/address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MissingLinkItem', () {
    test('fromJson parses deliveryAddress and orderCount', () {
      final item = MissingLinkItem.fromJson(const {
        'deliveryAddress': '12 Nguyễn Huệ, Q1',
        'orderCount': 7,
      });

      expect(item.deliveryAddress, '12 Nguyễn Huệ, Q1');
      expect(item.orderCount, 7);
    });

    test('toJson round-trips through fromJson (F1)', () {
      const original = MissingLinkItem(
        deliveryAddress: '45 Lê Lợi',
        orderCount: 3,
      );
      final json = original.toJson();
      expect(json, {
        'deliveryAddress': '45 Lê Lợi',
        'orderCount': 3,
      });
      final roundTripped = MissingLinkItem.fromJson(json);
      expect(roundTripped, original);
    });

    test('handles zero orderCount', () {
      final item = MissingLinkItem.fromJson(const {
        'deliveryAddress': 'Đường thần kê',
        'orderCount': 0,
      });
      expect(item.orderCount, 0);
    });

    test('equality keys on deliveryAddress + orderCount', () {
      const a = MissingLinkItem(deliveryAddress: 'X', orderCount: 1);
      const b = MissingLinkItem(deliveryAddress: 'X', orderCount: 1);
      const c = MissingLinkItem(deliveryAddress: 'X', orderCount: 2);
      const d = MissingLinkItem(deliveryAddress: 'Y', orderCount: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
    });
  });

  group('AddressAutocompleteResponse (F3 grouped shape)', () {
    test('fromJson parses both groups', () {
      final resp = AddressAutocompleteResponse.fromJson({
        'pastOrders': <Map<String, dynamic>>[
          {
            'id': 1,
            'displayAddress': '12 Nguyễn Huệ',
            'googleMapsUrl': 'https://maps.app.goo.gl/abc',
            'isCustomerAddress': true,
          },
        ],
        'library': <Map<String, dynamic>>[
          {
            'id': 9,
            'displayAddress': '45 Lê Lợi',
            'googleMapsUrl': null,
            'isCustomerAddress': false,
          },
        ],
      });

      expect(resp.pastOrders, hasLength(1));
      expect(resp.pastOrders.first.isCustomerAddress, isTrue);
      expect(resp.pastOrders.first.googleMapsUrl, isNotNull);
      expect(resp.library, hasLength(1));
      expect(resp.library.first.googleMapsUrl, isNull);
    });

    test('defaults to empty lists when keys absent', () {
      final resp = AddressAutocompleteResponse.fromJson(const <String, dynamic>{});
      expect(resp.pastOrders, isEmpty);
      expect(resp.library, isEmpty);
    });

    test('toJson produces map with pastOrders + library lists', () {
      const original = AddressAutocompleteResponse(
        pastOrders: <AddressSuggestion>[
          AddressSuggestion(
            id: 1,
            displayAddress: 'A',
            googleMapsUrl: 'u',
            isCustomerAddress: true,
          ),
        ],
        library: <AddressSuggestion>[
          AddressSuggestion(
            id: 2,
            displayAddress: 'B',
            googleMapsUrl: null,
            isCustomerAddress: false,
          ),
        ],
      );
      final json = original.toJson();
      expect(json['pastOrders'], isA<List>());
      expect(json['library'], isA<List>());
      expect(json['pastOrders'], hasLength(1));
      expect(json['library'], hasLength(1));
    });
  });

  group('AddressSuggestion (backward compatibility)', () {
    test('fromJson still parses flat shape', () {
      const s = AddressSuggestion(
        id: 5,
        displayAddress: 'C',
        googleMapsUrl: 'u2',
        isCustomerAddress: false,
      );
      final json = s.toJson();
      final parsed = AddressSuggestion.fromJson(json);
      expect(parsed, s);
    });

    test('googleMapsUrl is nullable (F3)', () {
      final parsed = AddressSuggestion.fromJson(const {
        'id': 7,
        'displayAddress': 'D',
      });
      expect(parsed.googleMapsUrl, isNull);
    });
  });

  // DG-388 CQ-3: cross-boundary contract test. The backend ``pastOrders``
  // entries are derived from the ``orders`` table (grouped by raw
  // ``delivery_address``) and omit ``id`` by construction. The Flutter
  // ``AddressSuggestion`` must parse this real backend shape through
  // ``AddressAutocompleteResponse.fromJson`` without throwing. Regression
  // guard for the Critical ``id`` mismatch found in the DG-388 review-auto.
  group('AddressAutocompleteResponse (backend pastOrders contract)', () {
    test('parses pastOrders entries that omit id (no throw)', () {
      // Mirrors the real backend `_autocomplete_past_orders` dict shape:
      // only `displayAddress` + `googleMapsUrl`, no `id` key.
      final resp = AddressAutocompleteResponse.fromJson({
        'pastOrders': <Map<String, dynamic>>[
          {'displayAddress': '12 Nguyễn Huệ, Q1', 'googleMapsUrl': 'https://maps.google.com/abc'},
          {'displayAddress': '45 Lê Lợi', 'googleMapsUrl': null},
        ],
        'library': <Map<String, dynamic>>[
          {
            'id': 9,
            'displayAddress': 'Thư viện địa chỉ',
            'googleMapsUrl': 'https://maps.google.com/lib',
            'isCustomerAddress': true,
          },
        ],
      });

      expect(resp.pastOrders, hasLength(2));
      expect(resp.pastOrders[0].id, isNull);
      expect(resp.pastOrders[0].displayAddress, '12 Nguyễn Huệ, Q1');
      expect(resp.pastOrders[0].googleMapsUrl, 'https://maps.google.com/abc');
      expect(resp.pastOrders[1].id, isNull);
      expect(resp.pastOrders[1].googleMapsUrl, isNull);
      // library entries still carry a non-null id.
      expect(resp.library, hasLength(1));
      expect(resp.library.first.id, 9);
      expect(resp.library.first.isCustomerAddress, isTrue);
    });

    test('AddressSuggestion parses a no-id pastOrders entry directly', () {
      final s = AddressSuggestion.fromJson(const {
        'displayAddress': '78 Trần Hưng Đạo',
        'googleMapsUrl': 'https://maps.google.com/x',
      });
      expect(s.id, isNull);
      expect(s.displayAddress, '78 Trần Hưng Đạo');
      expect(s.googleMapsUrl, 'https://maps.google.com/x');
    });
  });
}
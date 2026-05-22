import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnumAttribute.fromJson', () {
    test('parses backend payload mirroring nhan_banh', () {
      final json = {
        'attribute_type': 'nhan_banh',
        'label_vi': 'Nhân bánh',
        'default_option_id': 3,
        'options': <Map<String, dynamic>>[
          {
            'id': 1,
            'value_vi': 'Sầu riêng',
            'sort_order': 0,
            'active': 1,
            'is_default': false,
          },
          {
            'id': 2,
            'value_vi': 'Sô-cô-la',
            'sort_order': 1,
            'active': 1,
            'is_default': false,
          },
          {
            'id': 3,
            'value_vi': 'Việt quất',
            'sort_order': 2,
            'active': 1,
            'is_default': true,
          },
          {
            'id': 4,
            'value_vi': 'Chanh dây',
            'sort_order': 3,
            'active': 1,
            'is_default': false,
          },
          {
            'id': 5,
            'value_vi': 'Dâu',
            'sort_order': 4,
            'active': 1,
            'is_default': false,
          },
        ],
      };

      final ea = EnumAttribute.fromJson(json);

      expect(ea.attributeType, 'nhan_banh');
      expect(ea.labelVi, 'Nhân bánh');
      expect(ea.defaultOptionId, 3);
      expect(ea.options.length, 5);
      expect(ea.options[2].valueVi, 'Việt quất');
      expect(ea.options[2].isDefault, true);
      expect(ea.options[0].active, 1);
    });
  });

  group('Product.fromJson', () {
    test('returns empty enumAttributes when key missing', () {
      final json = {
        'id': 10,
        'name': 'Bánh kem dâu',
      };
      final p = Product.fromJson(json);
      expect(p.enumAttributes, isEmpty);
    });

    test('parses enum_attributes when present', () {
      final json = {
        'id': 11,
        'name': 'Bánh kem nhân',
        'enum_attributes': <Map<String, dynamic>>[
          {
            'attribute_type': 'nhan_banh',
            'label_vi': 'Nhân bánh',
            'default_option_id': 1,
            'options': <Map<String, dynamic>>[
              {
                'id': 1,
                'value_vi': 'Sầu riêng',
                'is_default': true,
              },
            ],
          },
        ],
      };
      final p = Product.fromJson(json);
      expect(p.enumAttributes.length, 1);
      expect(p.enumAttributes.first.attributeType, 'nhan_banh');
      expect(p.enumAttributes.first.options.first.valueVi, 'Sầu riêng');
    });
  });

  group('DraftOrderItem default population', () {
    Product makeProduct({List<EnumAttribute> enums = const []}) {
      return Product(
        id: 100,
        name: 'Bánh kem',
        enumAttributes: enums,
      );
    }

    test('populates attribute from is_default option', () {
      final product = makeProduct(enums: [
        const EnumAttribute(
          attributeType: 'nhan_banh',
          labelVi: 'Nhân bánh',
          defaultOptionId: 3,
          options: [
            EnumOption(id: 1, valueVi: 'Sầu riêng'),
            EnumOption(id: 3, valueVi: 'Việt quất', isDefault: true),
          ],
        ),
      ]);

      final item = DraftOrderItem(product: product);
      expect(item.attributes['nhan_banh'], 'Việt quất');
    });

    test('falls back to default_option_id when no is_default flag', () {
      final product = makeProduct(enums: [
        const EnumAttribute(
          attributeType: 'nhan_banh',
          labelVi: 'Nhân bánh',
          defaultOptionId: 2,
          options: [
            EnumOption(id: 1, valueVi: 'Sầu riêng'),
            EnumOption(id: 2, valueVi: 'Sô-cô-la'),
          ],
        ),
      ]);

      final item = DraftOrderItem(product: product);
      expect(item.attributes['nhan_banh'], 'Sô-cô-la');
    });

    test('attributes stays empty when product has no enum attributes', () {
      final product = makeProduct();
      final item = DraftOrderItem(product: product);
      expect(item.attributes, isEmpty);
    });

    test('caller-provided attributes win over enum defaults', () {
      final product = makeProduct(enums: [
        const EnumAttribute(
          attributeType: 'nhan_banh',
          labelVi: 'Nhân bánh',
          options: [
            EnumOption(id: 1, valueVi: 'Sầu riêng', isDefault: true),
          ],
        ),
      ]);

      final item = DraftOrderItem(
        product: product,
        attributes: {'nhan_banh': 'Sô-cô-la'},
      );
      expect(item.attributes['nhan_banh'], 'Sô-cô-la');
    });

    test('createExtraItem produces empty attributes', () {
      final extra = createExtraItem('Phí giao hàng', 30000);
      expect(extra.attributes, isEmpty);
      expect(extra.isExtra, true);
    });

    test('createCatalogExtraItem preserves product id with base price', () {
      const product = Product(
        id: 200,
        name: 'PK 1',
        category: 'phu_kien',
        basePrice: 25000,
      );

      final item = createCatalogExtraItem(product: product);

      expect(item.product.id, 200);
      expect(item.unitPrice, 25000);
      expect(item.priceChipId, isNull);
      expect(item.isExtra, true);
    });

    test('createCatalogExtraItem applies selected price chip', () {
      const product = Product(
        id: 201,
        name: 'PK 2',
        category: 'phu_kien',
        basePrice: 25000,
        priceChips: [
          PriceChip(id: 11, label: 'VIP', price: 30000, position: 0),
        ],
      );

      final item = createCatalogExtraItem(product: product, priceChipId: 11);

      expect(item.product.id, 201);
      expect(item.unitPrice, 30000);
      expect(item.priceChipId, 11);
    });

    test('createCatalogExtraItem keeps manual price and clears chip id', () {
      const product = Product(
        id: 202,
        name: 'PK 3',
        category: 'phu_kien',
        basePrice: 25000,
        priceChips: [
          PriceChip(id: 22, label: 'Lẻ', price: 28000, position: 0),
        ],
      );

      final item = createCatalogExtraItem(
        product: product,
        priceChipId: 22,
        customUnitPrice: 31500,
      );

      expect(item.product.id, 202);
      expect(item.unitPrice, 31500);
      expect(item.priceChipId, isNull);
    });

    test('trung bay item defaults useInventory to false', () {
      const trungBayProduct = Product(
        id: 101,
        name: 'Bánh trưng bày',
        attributes: {'trung_bay': 'true'},
      );

      final item = DraftOrderItem(product: trungBayProduct);

      expect(item.attributes['useInventory'], 'false');
    });

    test('trung bay item preserves explicit useInventory true', () {
      const trungBayProduct = Product(
        id: 101,
        name: 'Bánh trưng bày',
        attributes: {'trung_bay': 'true'},
      );

      final item = DraftOrderItem(
        product: trungBayProduct,
        attributes: {'useInventory': 'true'},
      );

      expect(item.attributes['useInventory'], 'true');
    });
  });
}

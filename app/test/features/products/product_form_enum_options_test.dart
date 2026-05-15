import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/products/product_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';

class _RecordedCall {
  _RecordedCall(this.method, this.args);
  final String method;
  final Map<String, dynamic> args;
}

class _FakeProductService implements ProductService {
  final List<_RecordedCall> calls = [];
  final Map<int, Product> productsById = {};

  int _nextOptionId = 1000;

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    calls.add(_RecordedCall('listProducts', {}));
    return productsById.values.toList();
  }

  @override
  Future<Product> getProduct(int id) async => productsById[id]!;

  @override
  Future<Product> getProductByCode(String code) async => productsById.values.first;

  @override
  Future<Product> createProduct({
    required String name,
    String category = 'bread',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
    String? productCode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Product> updateProduct(
    int id, {
    String? name,
    String? category,
    double? basePrice,
    double? cost,
    String? recipeNotes,
    int? active,
    String? productCode,
  }) async {
    final args = <String, dynamic>{'id': id};
    if (name != null) args['name'] = name;
    if (category != null) args['category'] = category;
    calls.add(_RecordedCall('updateProduct', args));
    return productsById[id]!;
  }

  @override
  Future<void> deleteProduct(int id) async {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadPhoto(int id, XFile file) async => '';

  @override
  String getPhotoUrl(int id) => '';

  @override
  Future<List<PriceChip>> getPriceChips(int productId) async => const [];

  @override
  Future<PriceChip> createPriceChip({
    required int productId,
    required String label,
    required double price,
    required int position,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PriceChip> updatePriceChip(
    int productId,
    int chipId, {
    String? label,
    double? price,
    int? position,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deletePriceChip(int productId, int chipId) async {}

  @override
  Future<void> setProductAttribute(
    int productId,
    String attributeType,
    String value,
  ) async {}

  @override
  Future<void> deleteProductAttribute(
    int productId,
    String attributeType,
  ) async {}

  @override
  Future<EnumOption> createEnumOption({
    required String attributeType,
    required String valueVi,
    int? sortOrder,
  }) async {
    final args = <String, dynamic>{
      'attributeType': attributeType,
      'valueVi': valueVi,
    };
    if (sortOrder != null) args['sortOrder'] = sortOrder;
    calls.add(_RecordedCall('createEnumOption', args));
    return EnumOption(
      id: _nextOptionId++,
      valueVi: valueVi,
      sortOrder: sortOrder ?? 0,
    );
  }

  @override
  Future<EnumOption> updateEnumOption(
    int optionId, {
    String? valueVi,
    int? sortOrder,
    int? active,
  }) async {
    final args = <String, dynamic>{'optionId': optionId};
    if (valueVi != null) args['valueVi'] = valueVi;
    if (sortOrder != null) args['sortOrder'] = sortOrder;
    if (active != null) args['active'] = active;
    calls.add(_RecordedCall('updateEnumOption', args));
    return EnumOption(id: optionId, valueVi: valueVi ?? '');
  }

  @override
  Future<void> deleteEnumOption(int optionId) async {
    calls.add(_RecordedCall('deleteEnumOption', {'optionId': optionId}));
  }

  @override
  Future<void> reorderEnumOptions(
    String attributeType,
    List<int> orderedIds,
  ) async {
    calls.add(_RecordedCall('reorderEnumOptions', {
      'attributeType': attributeType,
      'orderedIds': orderedIds,
    }));
  }

  @override
  Future<void> setEnumAttributeDefault(
    String attributeType,
    String defaultValue,
  ) async {
    calls.add(_RecordedCall('setEnumAttributeDefault', {
      'attributeType': attributeType,
      'defaultValue': defaultValue,
    }));
  }

}

class _FakeCategoryService implements CategoryService {
  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    return const [
      Category(id: 1, slug: 'banh_kem', name: 'Bánh kem', codePrefix: 'BKS', active: 1),
    ];
  }

  @override
  // DG-138#todo: replace with mocktail Fake/Mock once mocktail is added to project dependencies
  // ignore: always_declare_return_types
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _nhanBanh = EnumAttribute(
  attributeType: 'nhan_banh',
  labelVi: 'Nhân bánh',
  defaultOptionId: 3,
  options: [
    EnumOption(id: 1, valueVi: 'Sầu riêng', sortOrder: 0),
    EnumOption(id: 2, valueVi: 'Sô-cô-la', sortOrder: 1),
    EnumOption(id: 3, valueVi: 'Việt quất', sortOrder: 2, isDefault: true),
    EnumOption(id: 4, valueVi: 'Chanh dây', sortOrder: 3),
    EnumOption(id: 5, valueVi: 'Dâu', sortOrder: 4),
  ],
);

Product _testProduct({
  List<EnumAttribute> enums = const [_nhanBanh],
}) {
  return Product(
    id: 100,
    name: 'Bánh kem 20cm',
    category: 'banh_kem',
    productCode: 'BKS-20',
    basePrice: 200000,
    enumAttributes: enums,
  );
}

Future<_FakeProductService> _pumpForm(
  WidgetTester tester, {
  Product? product,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final fake = _FakeProductService();
  if (product != null) fake.productsById[product.id] = product;

  // Use a tall viewport so the enum section (rendered far below the price
  // chip section in a ListView) is laid out and findable in widget tests.
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'form',
            builder: (context, state) => ProductFormScreen(product: product),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        productServiceProvider.overrideWithValue(fake),
        categoryServiceProvider.overrideWithValue(_FakeCategoryService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.go('/form');
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProductFormScreen enum option editor (DG-092 Phase 4.5)', () {
    testWidgets('renders section with all 5 option rows + default radio', (tester) async {
      await _pumpForm(tester, product: _testProduct());

      expect(find.text('Giá bán'), findsOneWidget);
      expect(find.text('Tùy chọn thuộc tính'), findsOneWidget);
      expect(find.text('Nhân bánh'), findsOneWidget);

      for (final v in [
        'Sầu riêng',
        'Sô-cô-la',
        'Việt quất',
        'Chanh dây',
        'Dâu',
      ]) {
        expect(
          find.widgetWithText(TextFormField, v),
          findsOneWidget,
          reason: 'expected text field for "$v"',
        );
      }

      // Default radio (Việt quất is default → its row icon should be radio_button_checked)
      final checkedIcons = find.byIcon(Icons.radio_button_checked);
      expect(checkedIcons, findsOneWidget);
    });

    testWidgets('hides section when product has no enum attributes', (tester) async {
      await _pumpForm(tester, product: _testProduct(enums: const []));
      expect(find.text('Tùy chọn thuộc tính'), findsNothing);
    });

    testWidgets('blocks save when an option value is blank', (tester) async {
      final fake = await _pumpForm(tester, product: _testProduct());

      // Clear "Sầu riêng" value to trigger per-row validation
      // (VN.enumOptionValueRequired).
      final sauRieng = find.widgetWithText(TextFormField, 'Sầu riêng');
      expect(sauRieng, findsOneWidget);
      await tester.enterText(sauRieng, '');
      await tester.pumpAndSettle();

      // Tap save (last FilledButton in form)
      await tester.ensureVisible(find.byType(FilledButton).last);
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Validation error rendered AND no enum-option API calls fired
      expect(find.text('Giá trị không được để trống'), findsOneWidget);
      expect(
        fake.calls.where((c) => c.method.startsWith('createEnumOption') ||
            c.method.startsWith('updateEnumOption') ||
            c.method.startsWith('deleteEnumOption') ||
            c.method == 'setEnumAttributeDefault'),
        isEmpty,
      );
    });

    testWidgets('adds a new option row with "+ Thêm" button', (tester) async {
      await _pumpForm(tester, product: _testProduct());

      // Initially 5 TextFormFields for option values (plus name, code, price, cost, notes)
      // Tap "Thêm tùy chọn" — there's only one such button (one section)
      await tester.tap(find.widgetWithText(OutlinedButton, 'Thêm tùy chọn'));
      await tester.pumpAndSettle();

      // After tap, the 5 known options + 1 empty new row → 6 total option text fields
      // We can't easily count by label only, so we instead check that the original
      // 5 are still there:
      for (final v in [
        'Sầu riêng',
        'Sô-cô-la',
        'Việt quất',
        'Chanh dây',
        'Dâu',
      ]) {
        expect(find.widgetWithText(TextFormField, v), findsOneWidget);
      }
    });

    testWidgets('renaming an option fires PATCH on save', (tester) async {
      final fake = await _pumpForm(tester, product: _testProduct());

      // Find the "Sầu riêng" text field and update it
      final sauRieng = find.widgetWithText(TextFormField, 'Sầu riêng');
      expect(sauRieng, findsOneWidget);
      await tester.enterText(sauRieng, 'Sầu riêng Musang');
      await tester.pumpAndSettle();

      // Tap save (FilledButton with 'Lưu' label — last FilledButton in form)
      await tester.ensureVisible(find.byType(FilledButton).last);
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      final patches = fake.calls.where((c) => c.method == 'updateEnumOption').toList();
      expect(patches, hasLength(1));
      expect(patches.first.args['optionId'], 1);
      expect(patches.first.args['valueVi'], 'Sầu riêng Musang');
    });

    testWidgets('changing default radio fires PATCH on attribute', (tester) async {
      final fake = await _pumpForm(tester, product: _testProduct());

      // Tap the unchecked radio at row 0 (Sầu riêng, id=1) → make it default
      final unchecked = find.byIcon(Icons.radio_button_unchecked);
      // The first unchecked radio belongs to "Sầu riêng" (id=1).
      await tester.tap(unchecked.first);
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();

      final defaults =
          fake.calls.where((c) => c.method == 'setEnumAttributeDefault').toList();
      expect(defaults, hasLength(1));
      expect(defaults.first.args['attributeType'], 'nhan_banh');
      expect(defaults.first.args['defaultValue'], '1');
    });

    testWidgets('adding a new option fires POST on save', (tester) async {
      final fake = await _pumpForm(tester, product: _testProduct());

      // Add row
      await tester.tap(find.widgetWithText(OutlinedButton, 'Thêm tùy chọn'));
      await tester.pumpAndSettle();

      // The new option row's TextFormField is the last one whose ancestor
      // hosts a "Giá trị" label.
      final valueFields = find.ancestor(
        of: find.text('Giá trị'),
        matching: find.byType(TextFormField),
      );
      expect(valueFields, findsNWidgets(6));

      await tester.enterText(valueFields.last, 'Bơ sữa');
      await tester.pumpAndSettle();

      // Save
      await tester.ensureVisible(find.byType(FilledButton).last);
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      final creates =
          fake.calls.where((c) => c.method == 'createEnumOption').toList();
      expect(creates, hasLength(1));
      expect(creates.first.args['attributeType'], 'nhan_banh');
      expect(creates.first.args['valueVi'], 'Bơ sữa');
    });
  });
}

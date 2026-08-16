import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/catalog_service.dart';
import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/catalog_photo.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/paginated_response.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/products/product_form_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProductService implements ProductService {
  final List<Map<String, dynamic>> createCalls = [];
  final List<Map<String, dynamic>> updateCalls = [];

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async =>
      const [];

  @override
  Future<PaginatedResponse<Product>> listProductsPaginated({
    String? category,
    int active = 1,
    int limit = 50,
    int offset = 0,
  }) async =>
      PaginatedResponse<Product>(
        items: const [],
        total: 0,
        hasMore: false,
        limit: limit,
        offset: offset,
      );

  @override
  Future<Product> getProduct(int id) async => throw UnimplementedError();

  @override
  Future<Product> getProductByCode(String code) async => throw UnimplementedError();

  @override
  Future<Product> createProduct({
    required String name,
    String category = 'bread',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
    String? productCode,
  }) async {
    createCalls.add({
      'name': name,
      'category': category,
      'basePrice': basePrice,
      'cost': cost,
      'recipeNotes': recipeNotes,
      'productCode': productCode,
    });
    return Product(
      id: 1,
      name: name,
      category: category,
      basePrice: basePrice,
      cost: cost,
      recipeNotes: recipeNotes,
      productCode: productCode ?? '',
    );
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
    updateCalls.add({
      'id': id,
      'name': name,
      'category': category,
      'basePrice': basePrice,
      'cost': cost,
    });
    return Product(
      id: id,
      name: name ?? '',
      category: category ?? 'bread',
      basePrice: basePrice ?? 0,
      cost: cost ?? 0,
    );
  }

  @override
  Future<void> deleteProduct(int id) async {}

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<PriceChip> updatePriceChip(
    int productId,
    int chipId, {
    String? label,
    double? price,
    int? position,
  }) async =>
      throw UnimplementedError();

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<EnumOption> updateEnumOption(
    int optionId, {
    String? valueVi,
    int? sortOrder,
    int? active,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteEnumOption(int optionId) async {}

  @override
  Future<void> reorderEnumOptions(
    String attributeType,
    List<int> orderedIds,
  ) async {}

  @override
  Future<void> setEnumAttributeDefault(
    String attributeType,
    String defaultValue,
  ) async {}
}

class _FakeCategoryService implements CategoryService {
  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    return const [
      Category(id: 1, slug: 'banh_kem', name: 'Bánh kem', codePrefix: 'BKS', active: 1),
      Category(id: 2, slug: 'bread', name: 'Bánh mì', codePrefix: 'BMB', active: 1),
    ];
  }

  @override
  // ignore: always_declare_return_types
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeCatalogService implements CatalogService {
  @override
  Future<List<CatalogPhoto>> getCatalogPhotos(int productId) async => const [];

  @override
  // ignore: always_declare_return_types
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Product _testProduct() => const Product(
      id: 100,
      name: 'Bánh kem 20cm',
      category: 'banh_kem',
      productCode: 'BKS-20',
      basePrice: 200000,
      cost: 120000,
      recipeNotes: 'Ghi chú công thức',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpForm(WidgetTester tester, {Product? product}) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
          routes: [
            GoRoute(
              path: 'form',
              builder: (_, _) => ProductFormScreen(product: product),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          productServiceProvider.overrideWithValue(_FakeProductService()),
          categoryServiceProvider.overrideWithValue(_FakeCategoryService()),
          catalogServiceProvider.overrideWithValue(_FakeCatalogService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/form');
    await tester.pumpAndSettle();
  }

  testWidgets('create mode renders create-product title', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.createProduct), findsOneWidget);
  });

  testWidgets('edit mode renders edit-product title and prefilled fields',
      (tester) async {
    await pumpForm(tester, product: _testProduct());
    expect(find.text(VN.editProduct), findsOneWidget);
    expect(find.text('Bánh kem 20cm'), findsOneWidget);
  });

  testWidgets('renders product name field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productName), findsOneWidget);
  });

  testWidgets('renders product category field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productCategory), findsOneWidget);
  });

  testWidgets('renders product price field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productPrice), findsOneWidget);
  });

  testWidgets('renders product cost field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productCost), findsOneWidget);
  });

  testWidgets('renders product code field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productCode), findsOneWidget);
  });

  testWidgets('renders recipe notes field', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.productNotes), findsOneWidget);
  });

  testWidgets('renders price chips section', (tester) async {
    await pumpForm(tester);
    expect(find.text(VN.priceChips), findsOneWidget);
  });

  testWidgets('renders save button', (tester) async {
    await pumpForm(tester);
    // The form has a FilledButton to save.
    expect(find.byType(FilledButton), findsAtLeast(1));
  });

  testWidgets('create mode has empty name field', (tester) async {
    await pumpForm(tester);
    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, VN.productName),
    );
    expect(nameField.controller?.text, '');
  });

  testWidgets('edit mode prefills name field', (tester) async {
    await pumpForm(tester, product: _testProduct());
    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, VN.productName),
    );
    expect(nameField.controller?.text, 'Bánh kem 20cm');
  });

  testWidgets('edit mode prefills price field', (tester) async {
    await pumpForm(tester, product: _testProduct());
    final priceField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, VN.productPrice),
    );
    expect(priceField.controller?.text, '200000');
  });
}
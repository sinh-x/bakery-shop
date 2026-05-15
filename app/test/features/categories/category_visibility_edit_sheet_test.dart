import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/features/categories/category_management_screen.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCategoryService extends CategoryService {
  _FakeCategoryService(List<Category> categories)
    : _categories = List<Category>.from(categories),
      super(Dio());

  final List<Category> _categories;

  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    if (includeInactive) {
      return List<Category>.from(_categories);
    }
    return _categories.where((category) => category.active == 1).toList();
  }

  @override
  Future<Category> updateCategory(
    int id, {
    String? name,
    String? codePrefix,
    int? active,
    String? icon,
  }) async {
    final index = _categories.indexWhere((category) => category.id == id);
    final current = _categories[index];
    final updated = Category(
      id: current.id,
      slug: current.slug,
      name: name ?? current.name,
      codePrefix: codePrefix ?? current.codePrefix,
      active: active ?? current.active,
      icon: icon ?? current.icon,
      position: current.position,
    );
    _categories[index] = updated;
    return updated;
  }

  @override
  Future<Category> createCategory({
    required String name,
    required String slug,
    required String codePrefix,
    String icon = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> reorderCategories(List<int> ids) async {}
}

Future<void> _pumpScreen(WidgetTester tester, CategoryService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [categoryServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: CategoryManagementScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edit sheet can hide an active category', (tester) async {
    final service = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'banh_kem',
        name: 'Banh kem',
        codePrefix: 'BK',
        active: 1,
      ),
    ]);

    await _pumpScreen(tester, service);
    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();

    expect(find.text(VN.categoryVisibility), findsOneWidget);
    expect(find.text(VN.categoryVisible), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, VN.save);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text(VN.hiddenCategories), findsOneWidget);
    expect(find.text('Banh kem'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('edit sheet can restore a hidden category', (tester) async {
    final service = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'banh_kem',
        name: 'Banh kem',
        codePrefix: 'BK',
        active: 0,
      ),
    ]);

    await _pumpScreen(tester, service);
    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();

    expect(find.text(VN.categoryHiddenState), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, VN.save);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text(VN.hiddenCategories), findsNothing);
    expect(find.text('Banh kem'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);
  });
}

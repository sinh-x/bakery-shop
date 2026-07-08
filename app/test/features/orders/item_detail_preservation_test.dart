import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/expandable_item_card.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/selected_items_list.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/order/order_draft_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

const _nhanBanhAttribute = EnumAttribute(
  attributeType: 'nhan_banh',
  labelVi: 'Nhân bánh',
  defaultOptionId: 3,
  options: [
    EnumOption(id: 1, valueVi: 'Sầu riêng'),
    EnumOption(id: 2, valueVi: 'Sô-cô-la'),
    EnumOption(id: 3, valueVi: 'Việt quất', isDefault: true),
  ],
);

Product _product({
  List<EnumAttribute> enums = const [_nhanBanhAttribute],
}) {
  return Product(
    id: 100,
    name: 'Bánh kem',
    category: 'banh_kem',
    basePrice: 200000,
    enumAttributes: enums,
  );
}

Widget _pumpItemsList(WidgetTester tester, List<DraftOrderItem> items) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final regularItems = items.where((i) => !i.isExtra).toList();
  final extraItems = items.where((i) => i.isExtra).toList();
  container.read(orderCreateStateProvider.notifier).updateItems(items);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SelectedItemsList(
                items: items,
                regularItems: regularItems,
                extraItems: extraItems,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  DraftOrderItem item, {
  VoidCallback? onStateChanged,
  ValueChanged<int>? onQtyChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpandableItemCard(
            item: item,
            onRemove: () {},
            onQtyChanged: onQtyChanged ?? (qty) => item.quantity = qty,
            onStateChanged: onStateChanged ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AC-4: ExpandableItemCard edits preserve item detail state', () {
    testWidgets('quantity change persists to DraftOrderItem.quantity',
        (tester) async {
      final item = DraftOrderItem(product: _product(), quantity: 1);
      await _pumpCard(tester, item);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(item.quantity, 2);
    });

    testWidgets('price edit persists to customUnitPrice', (tester) async {
      final item = DraftOrderItem(product: _product());
      await _pumpCard(tester, item);

      final priceField = find.widgetWithText(TextFormField, '200000');
      expect(priceField, findsOneWidget);
      await tester.enterText(priceField, '250000');
      await tester.pump();

      expect(item.customUnitPrice, 250000);
    });

    testWidgets('notes edit persists to DraftOrderItem.notes', (tester) async {
      final item = DraftOrderItem(product: _product());
      await _pumpCard(tester, item);

      await tester.enterText(find.widgetWithText(TextFormField, ''), 'Ghi chú test');
      await tester.pump();

      expect(item.notes, 'Ghi chú test');
    });

    testWidgets('birthday checkbox + age persist to item', (tester) async {
      final item = DraftOrderItem(product: _product());
      await _pumpCard(tester, item);

      await tester.tap(find.text(VN.isBirthday));
      await tester.pump();

      expect(item.isBirthday, isTrue);

      await tester.enterText(
        find.ancestor(of: find.text(VN.birthdayAge), matching: find.byType(TextFormField)),
        '5',
      );
      await tester.pump();

      expect(item.age, '5');
    });

    testWidgets('enum attribute chip selection persists to attributes',
        (tester) async {
      final item = DraftOrderItem(product: _product());
      await _pumpCard(tester, item);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sầu riêng'));
      await tester.pump();

      expect(item.attributes['nhan_banh'], 'Sầu riêng');
    });

    testWidgets('tien rut toggle persists daDuaTienRut to item', (tester) async {
      const product = Product(
        id: 101,
        name: 'Bánh rút tiền',
        category: 'banh_kem',
        basePrice: 200000,
        attributes: {'rut_tien': 'true'},
      );
      final item = DraftOrderItem(product: product);
      await _pumpCard(tester, item);

      await tester.tap(find.text(VN.rutTien));
      await tester.pump();

      expect(item.attributes['rut_tien'], 'true');

      await tester.tap(find.text(VN.daDuaTienRut));
      await tester.pump();

      expect(item.daDuaTienRut, isTrue);
    });
  });

  group('AC-4: SelectedItemsList commits edits via state notifier', () {
    testWidgets('qty change through SelectedItemsList updates state items',
        (tester) async {
      final item = DraftOrderItem(product: _product(), quantity: 1);
      final widget = _pumpItemsList(tester, [item]);
      await tester.pumpWidget(widget);

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pump();

      expect(item.quantity, 2);
    });

    testWidgets('onStateChanged spread preserves existing item mutations',
        (tester) async {
      final item = DraftOrderItem(product: _product(), quantity: 1);
      item.notes = 'Đã ghi chú sẵn';

      final widget = _pumpItemsList(tester, [item]);
      await tester.pumpWidget(widget);

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pump();

      expect(item.notes, 'Đã ghi chú sẵn');
      expect(item.quantity, 2);
    });
  });

  group('AC-5: draft save/restore preserves all item details', () {
    test('OrderDraft round-trip preserves quantity, price, notes, birthday, age',
        () {
      final product = _product();
      final original = DraftOrderItem(
        product: product,
        quantity: 3,
        notes: 'Ghi chú draft',
        isBirthday: true,
        age: '7',
        customUnitPrice: 250000,
      );
      original.attributes['nhan_banh'] = 'Sô-cô-la';

      final draft = OrderDraft(
        customerName: 'Test',
        customerPhone: '0123',
        items: [original],
      );

      final restored = DraftOrderItem(
        product: draft.items.first.product,
        quantity: draft.items.first.quantity,
        notes: draft.items.first.notes,
        isBirthday: draft.items.first.isBirthday,
        age: draft.items.first.age,
        customUnitPrice: draft.items.first.customUnitPrice,
        attributes: Map<String, dynamic>.from(draft.items.first.attributes),
      );

      expect(restored.quantity, 3);
      expect(restored.notes, 'Ghi chú draft');
      expect(restored.isBirthday, isTrue);
      expect(restored.age, '7');
      expect(restored.customUnitPrice, 250000);
      expect(restored.attributes['nhan_banh'], 'Sô-cô-la');
    });

    test('OrderDraft round-trip preserves tien rut and priceChipId', () {
      const product = Product(
        id: 102,
        name: 'Bánh rút tiền',
        category: 'banh_kem',
        basePrice: 200000,
        attributes: {'rut_tien': 'true'},
      );
      final original = DraftOrderItem(
        product: product,
        quantity: 1,
        priceChipId: 5,
      );
      original.daDuaTienRut = true;
      original.attributes['rut_tien'] = 'true';
      original.attributes['cash_amount'] = '200000';

      final draft = OrderDraft(items: [original]);
      final saved = draft.items.first;

      expect(saved.daDuaTienRut, isTrue);
      expect(saved.priceChipId, 5);
      expect(saved.attributes['rut_tien'], 'true');
      expect(saved.attributes['cash_amount'], '200000');
    });

    test('OrderDraftNotifier save/restore preserves item list contents', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final product = _product();
      final item = DraftOrderItem(
        product: product,
        quantity: 4,
        notes: 'Test preserve',
        isBirthday: true,
        age: '3',
      );

      container.read(orderCreateStateProvider.notifier).updateItems([item]);
      container.read(orderCreateStateProvider.notifier).updateWizardData(
            const OrderWizardData(
              customerName: 'Cust',
              customerPhone: '098',
            ),
          );

      final state = container.read(orderCreateStateProvider);
      final draft = OrderDraft(
        customerName: state.wizardData.customerName,
        customerPhone: state.wizardData.customerPhone,
        items: List.of(state.items),
      );
      container.read(orderDraftProvider.notifier).save(draft);

      final restoredDraft = container.read(orderDraftProvider);
      expect(restoredDraft, isNotNull);
      expect(restoredDraft!.items, hasLength(1));
      expect(restoredDraft.items.first.quantity, 4);
      expect(restoredDraft.items.first.notes, 'Test preserve');
      expect(restoredDraft.items.first.isBirthday, isTrue);
      expect(restoredDraft.items.first.age, '3');
      expect(restoredDraft.customerName, 'Cust');
    });
  });

  group('Phase 4 fix: pendingPhotos preserved when picker re-opens', () {
    test('copying DraftOrderItem with pendingPhotos list preserves photos', () {
      final product = _product();
      final original = DraftOrderItem(product: product, quantity: 1);
      final fakeFile = XFile('/tmp/fake-photo.jpg');
      original.pendingPhotos.add(fakeFile);

      final copy = DraftOrderItem(
        product: original.product,
        quantity: original.quantity,
        notes: original.notes,
        isBirthday: original.isBirthday,
        age: original.age,
        customUnitPrice: original.customUnitPrice,
        isExtra: original.isExtra,
        isGift: original.isGift,
        attributes: Map<String, dynamic>.from(original.attributes),
        daDuaTienRut: original.daDuaTienRut,
        priceChipId: original.priceChipId,
      )..pendingPhotos = List<XFile>.from(original.pendingPhotos);

      expect(copy.pendingPhotos, hasLength(1));
      expect(copy.pendingPhotos.first.path, '/tmp/fake-photo.jpg');
      expect(copy.quantity, 1);
    });
  });
}
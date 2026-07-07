import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_photo_section.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

const _testRef = 'TEST-ORDER-1';

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  final List<OrderPhoto> _photos;
  _FakeOrderPhotosNotifier(this._photos) : super(_testRef);

  @override
  Future<List<OrderPhoto>> build() async => _photos;
}

void main() {
  testWidgets('OrderPhotoSection renders empty-state text when no photos',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderPhotosProvider(_testRef)
              .overrideWith(() => _FakeOrderPhotosNotifier(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: OrderPhotoSection(
              orderRef: _testRef,
              baseUrl: 'http://test.local',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrderPhotoSection), findsOneWidget);
    expect(find.text(VN.orderPhotos), findsOneWidget);
    expect(find.text(VN.noOrderPhotos), findsOneWidget);
  });

  testWidgets('OrderPhotoSection renders photo thumbnails when photos exist',
      (tester) async {
    final photos = [
      const OrderPhoto(
        id: 1,
        orderId: 100,
        photoHash: 'abc123',
        tags: 'mau-trang-tri',
        workItemId: null,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderPhotosProvider(_testRef)
              .overrideWith(() => _FakeOrderPhotosNotifier(photos)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: OrderPhotoSection(
              orderRef: _testRef,
              baseUrl: 'http://test.local',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrderPhotoSection), findsOneWidget);
    expect(find.text(VN.orderPhotos), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    expect(find.text('Màu trang trí'), findsOneWidget);
  });

  testWidgets('OrderPhotoSection orderLevelOnly hides work-item photos',
      (tester) async {
    final photos = [
      const OrderPhoto(
        id: 1,
        orderId: 100,
        photoHash: 'order1',
        workItemId: null,
      ),
      const OrderPhoto(
        id: 2,
        orderId: 100,
        photoHash: 'work1',
        workItemId: 5,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderPhotosProvider(_testRef)
              .overrideWith(() => _FakeOrderPhotosNotifier(photos)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: OrderPhotoSection(
              orderRef: _testRef,
              baseUrl: 'http://test.local',
              orderLevelOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.noOrderPhotos), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
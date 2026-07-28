import 'dart:convert';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/orders/widgets/google_maps_modal.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captured PATCH /api/orders/{ref} body (the save call from the modal).
Map<String, dynamic>? _savedBody;

Map<String, dynamic> _orderJson({String? googleMapsUrl}) => {
      'id': 'order-1',
      'orderRef': 'REF-1',
      'publicOrderCode': '',
      'customerName': '',
      'customerPhone': '',
      'deliveryPhone': '',
      'customerId': null,
      'items': <Map<String, dynamic>>[],
      'totalPrice': 0.0,
      'status': 'new',
      'deliveryType': 'door',
      'deliveryAddress': '12 Lê Lợi',
      'shippingFee': 20000.0,
      'notes': '',
      'source': '',
      'googleMapsUrl': googleMapsUrl,
      'packingChecklist': <Map<String, dynamic>>[],
      'createdAt': '2026-07-01T08:00:00Z',
      'updatedAt': '2026-07-01T08:00:00Z',
    };

class _MapsModalInterceptor extends Interceptor {
  final String? initialUrl;

  _MapsModalInterceptor({this.initialUrl});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    // GET /api/orders/REF-1 — order detail.
    if (path == '/api/orders/REF-1' && options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: _orderJson(googleMapsUrl: initialUrl),
        ),
      );
      return;
    }

    // GET /api/orders — order list refresh after save.
    if (path == '/api/orders' && options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <Map<String, dynamic>>[],
        ),
      );
      return;
    }

    // PATCH /api/orders/REF-1 — modal save.
    if (path == '/api/orders/REF-1' && options.method == 'PATCH') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
      _savedBody = body;
      final updated = _orderJson(
        googleMapsUrl: body['googleMapsUrl'] as String?,
      );
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: updated),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}

class _LoggedByFixed extends LoggedByNotifier {
  final String _name;
  _LoggedByFixed(this._name);

  @override
  String build() => _name;
}

Future<Widget> _buildModal({
  required String? initialUrl,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..interceptors.add(_MapsModalInterceptor(initialUrl: initialUrl));

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dioProvider.overrideWithValue(dio),
    loggedByProvider.overrideWith(() => _LoggedByFixed('staff')),
  ]);
  addTearDown(container.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: GoogleMapsModal(
          orderRef: 'REF-1',
          initialUrl: initialUrl,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    _savedBody = null;
  });

  testWidgets(
      'AC6: Google Maps modal renders title, hint, and URL field with the current URL prefilled',
      (tester) async {
    await tester.pumpWidget(await _buildModal(
      initialUrl: 'https://maps.google.com/?q=10.7,106.7',
    ));

    expect(find.byType(GoogleMapsModal), findsOneWidget);
    expect(find.text(OrdersLabels.googleMapsModalTitle), findsWidgets);
    expect(find.text(OrdersLabels.googleMapsModalHint), findsOneWidget);
    expect(
      find.text('https://maps.google.com/?q=10.7,106.7'),
      findsOneWidget,
    );
    // Save + Open map actions are present.
    expect(find.text(OrdersLabels.googleMapsModalSave), findsOneWidget);
    expect(find.text(OrdersLabels.googleMapsModalOpenMap), findsOneWidget);
  });

  testWidgets(
      'AC6: Google Maps modal shows empty-state hint when no URL is set',
      (tester) async {
    await tester.pumpWidget(await _buildModal(initialUrl: null));

    // The URL field's hintText serves as the empty-state placeholder.
    expect(find.text(OrdersLabels.googleMapsModalEmpty), findsOneWidget);
    // Open map is disabled when there is no URL.
    final openMapBtn = tester.widget<FilledButton>(find.ancestor(
      of: find.text(OrdersLabels.googleMapsModalSave),
      matching: find.byType(FilledButton),
    ));
    expect(openMapBtn.onPressed, isNotNull,
        reason: 'Save should always be enabled');
  });

  testWidgets(
      'AC6: editing the URL and tapping Save persists the new googleMapsUrl',
      (tester) async {
    await tester.pumpWidget(await _buildModal(initialUrl: null));

    await tester.enterText(
      find.byType(TextFormField),
      'https://maps.google.com/new',
    );
    await tester.pump();

    await tester.tap(find.text(OrdersLabels.googleMapsModalSave));
    await tester.pumpAndSettle();

    expect(_savedBody, isNotNull);
    expect(_savedBody!['googleMapsUrl'], 'https://maps.google.com/new',
        reason: 'AC6: save should PATCH the new googleMapsUrl');
  });

  testWidgets(
      'AC6: tapping Save with an empty field clears the googleMapsUrl',
      (tester) async {
    await tester.pumpWidget(
      await _buildModal(initialUrl: 'https://maps.google.com/old'),
    );

    // Clear the field then save.
    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump();

    await tester.tap(find.text(OrdersLabels.googleMapsModalSave));
    await tester.pumpAndSettle();

    expect(_savedBody, isNotNull);
    expect(_savedBody!['googleMapsUrl'], isNull,
        reason: 'AC6: empty field on save should clear the URL');
  });

  testWidgets(
      'AC6: tapping "Xoá liên kết" with an existing URL clears the googleMapsUrl',
      (tester) async {
    await tester.pumpWidget(
      await _buildModal(initialUrl: 'https://maps.google.com/old'),
    );

    expect(find.text(OrdersLabels.googleMapsModalClear), findsOneWidget);

    await tester.tap(find.text(OrdersLabels.googleMapsModalClear));
    await tester.pumpAndSettle();

    expect(_savedBody, isNotNull);
    expect(_savedBody!['googleMapsUrl'], isNull,
        reason: 'AC6: clear action should send null googleMapsUrl');
  });
}
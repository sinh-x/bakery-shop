import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentTransactionPhoto', () {
    test('parses all fields from JSON', () {
      final photo = PaymentTransactionPhoto.fromJson({
        'id': '55',
        'paymentTransactionId': '20',
        'photoId': '7',
        'photoHash': 'abc123',
        'createdAt': '2026-08-16T05:49:42Z',
      });

      expect(photo.id, '55');
      expect(photo.paymentTransactionId, '20');
      expect(photo.photoId, '7');
      expect(photo.photoHash, 'abc123');
      expect(photo.createdAt, '2026-08-16T05:49:42Z');
    });

    test('photoHash and createdAt default to null', () {
      final photo = PaymentTransactionPhoto.fromJson({
        'id': '56',
        'paymentTransactionId': '21',
        'photoId': '8',
      });

      expect(photo.photoHash, isNull);
      expect(photo.createdAt, isNull);
    });

    test('serializes back to JSON with camelCase keys', () {
      const photo = PaymentTransactionPhoto(
        id: '57',
        paymentTransactionId: '22',
        photoId: '9',
        photoHash: 'deadbeef',
        createdAt: '2026-08-16T05:49:42Z',
      );
      final json = photo.toJson();

      expect(json['id'], '57');
      expect(json['paymentTransactionId'], '22');
      expect(json['photoId'], '9');
      expect(json['photoHash'], 'deadbeef');
      expect(json['createdAt'], '2026-08-16T05:49:42Z');
    });
  });
}
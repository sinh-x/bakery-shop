import 'package:bakery_app/data/models/message_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageTemplate (DG-375 Phase 2)', () {
    test('fromJson parses all fields from backend API response', () {
      final json = <String, dynamic>{
        'id': 42,
        'scenario': 'confirm_order',
        'name': 'Xác nhận đơn — Pickup',
        'body': 'Dạ shop gửi xác nhận đơn bánh mã {public_order_code} ạ.',
        'is_system': true,
        'created_by_staff_id': null,
        'sort_order': 2,
        'active': true,
        'created_at': '2026-08-10T02:05:56Z',
        'updated_at': '2026-08-10T02:05:56Z',
      };

      final template = MessageTemplate.fromJson(json);

      expect(template.id, 42);
      expect(template.scenario, 'confirm_order');
      expect(template.name, 'Xác nhận đơn — Pickup');
      expect(template.body, contains('{public_order_code}'));
      expect(template.isSystem, isTrue);
      expect(template.createdByStaffId, isNull);
      expect(template.sortOrder, 2);
      expect(template.active, isTrue);
      expect(template.createdAt, isNotNull);
      expect(template.updatedAt, isNotNull);
    });

    test('fromJson applies defensive defaults for missing optional fields', () {
      final template = MessageTemplate.fromJson(<String, dynamic>{
        'id': 7,
        'scenario': 'ask_info',
        'name': 'Hỏi thông tin',
      });

      expect(template.id, 7);
      expect(template.scenario, 'ask_info');
      expect(template.name, 'Hỏi thông tin');
      expect(template.body, '');
      expect(template.isSystem, isFalse);
      expect(template.createdByStaffId, isNull);
      expect(template.sortOrder, 0);
      expect(template.active, isTrue);
      expect(template.createdAt, isNull);
      expect(template.updatedAt, isNull);
    });

    test('fromJson parses personal template with staff owner', () {
      final template = MessageTemplate.fromJson(<String, dynamic>{
        'id': 99,
        'scenario': 'follow_up',
        'name': 'Cảm ơn riêng',
        'body': 'Cảm ơn mình ạ!',
        'is_system': false,
        'created_by_staff_id': 5,
        'sort_order': 0,
        'active': true,
      });

      expect(template.isSystem, isFalse);
      expect(template.createdByStaffId, 5);
    });

    test('fromJson round-trips through toJson for create payload shape', () {
      final original = MessageTemplate.fromJson(<String, dynamic>{
        'id': 1,
        'scenario': 'ask_info',
        'name': 'Hỏi thông tin đặt bánh',
        'body': 'Body with {customer_name}',
        'is_system': true,
        'created_by_staff_id': null,
        'sort_order': 1,
        'active': true,
        'created_at': '2026-08-10T02:05:56Z',
        'updated_at': '2026-08-10T02:05:56Z',
      });
      final roundTripped = MessageTemplate.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.scenario, original.scenario);
      expect(roundTripped.name, original.name);
      expect(roundTripped.body, original.body);
      expect(roundTripped.isSystem, original.isSystem);
      expect(roundTripped.createdByStaffId, original.createdByStaffId);
      expect(roundTripped.sortOrder, original.sortOrder);
      expect(roundTripped.active, original.active);
    });

    test('copyWith preserves immutability and updates only specified fields', () {
      const original = MessageTemplate(
        id: 1,
        scenario: 'ask_info',
        name: 'Hỏi thông tin',
        body: 'Body',
        isSystem: false,
        sortOrder: 0,
        active: true,
      );
      final updated = original.copyWith(name: 'Hỏi thông tin mới', active: false);

      expect(updated.id, 1);
      expect(updated.scenario, 'ask_info');
      expect(updated.name, 'Hỏi thông tin mới');
      expect(updated.body, 'Body');
      expect(updated.isSystem, isFalse);
      expect(updated.active, isFalse);
      expect(original.name, 'Hỏi thông tin');
      expect(original.active, isTrue);
    });
  });
}
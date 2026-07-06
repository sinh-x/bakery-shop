// DG-202 TC-13 through TC-28: Z-suffix timestamp parsing/format tests for
// Flutter client models. Verifies parseApiDateTime produces DateTime with
// Z-suffix input, nullable timestamps handle null correctly, and String
// timestamp fields preserve the Z-suffix format.
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/journal_entry.dart';
import 'package:bakery_app/data/models/checklist_entry.dart';
import 'package:bakery_app/data/models/checklist_template.dart';
import 'package:bakery_app/data/models/account.dart';
import 'package:bakery_app/data/models/catalog_photo.dart';
import 'package:bakery_app/data/models/catalog_browse_photo.dart';
import 'package:bakery_app/data/models/event_photo.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/data/models/cake_queue_item.dart';

void main() {
  const zTs = '2026-06-30T05:30:00Z';

  group('PaymentTransaction (TC-13, TC-14)', () {
    test(
        'TC-13: createdAt parses Z-suffix input into DateTime via parseApiDateTime',
        () {
      final json = {
        'id': '1',
        'orderId': '10',
        'amount': 100000.0,
        'createdAt': zTs,
      };
      final txn = PaymentTransaction.fromJson(json);
      expect(txn.createdAt, isA<DateTime>());
      expect(txn.createdAt!.toUtc().toIso8601String(), contains('Z'));
      // The parsed instant should equal the submitted UTC instant.
      final parsed = DateTime.parse(zTs);
      expect(txn.createdAt!.toUtc(), parsed.toUtc());
    });

    test('TC-13: createdAt null handled correctly', () {
      final json = {
        'id': '2',
        'orderId': '10',
        'amount': 50000.0,
        'createdAt': null,
      };
      final txn = PaymentTransaction.fromJson(json);
      expect(txn.createdAt, isNull);
    });

    test(
        'TC-14: invalidatedAt parses nullable DateTime with Z-suffix input',
        () {
      final json = {
        'id': '3',
        'orderId': '10',
        'amount': 200000.0,
        'createdAt': zTs,
        'invalidatedAt': '2026-06-30T06:00:00Z',
        'invalidatedBy': 'sinh',
      };
      final txn = PaymentTransaction.fromJson(json);
      expect(txn.invalidatedAt, isA<DateTime>());
      expect(txn.invalidatedAt!.toUtc(), DateTime.parse('2026-06-30T06:00:00Z').toUtc());
    });

    test('TC-14: invalidatedAt null for valid transaction', () {
      final json = {
        'id': '4',
        'orderId': '10',
        'amount': 75000.0,
        'createdAt': zTs,
        'invalidatedAt': null,
      };
      final txn = PaymentTransaction.fromJson(json);
      expect(txn.invalidatedAt, isNull);
    });
  });

  group('JournalEntry (TC-15, TC-16, TC-17)', () {
    test(
        'TC-15: createdAt parses Z-suffix input into DateTime via parseApiDateTime',
        () {
      final json = {
        'id': '100',
        'description': 'Test entry',
        'sourceType': 'manual',
        'createdAt': zTs,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.createdAt, isA<DateTime>());
      expect(entry.createdAt!.toUtc(), DateTime.parse(zTs).toUtc());
    });

    test('TC-15: createdAt null handled correctly', () {
      final json = {
        'id': '101',
        'description': 'No date',
        'sourceType': 'manual',
        'createdAt': null,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.createdAt, isNull);
    });

    test('TC-16: lockedAt parses nullable DateTime with Z-suffix input', () {
      final json = {
        'id': '102',
        'description': 'Locked',
        'sourceType': 'manual',
        'lockedAt': '2026-06-30T07:00:00Z',
        'lockedBy': 'sinh',
        'createdAt': zTs,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.lockedAt, isA<DateTime>());
      expect(entry.lockedAt!.toUtc(),
          DateTime.parse('2026-06-30T07:00:00Z').toUtc());
    });

    test('TC-16: lockedAt null when not locked', () {
      final json = {
        'id': '103',
        'description': 'Unlocked',
        'sourceType': 'manual',
        'lockedAt': null,
        'createdAt': zTs,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.lockedAt, isNull);
    });

    test('TC-17: transactionDate is a String field (Z-suffix format)', () {
      final json = {
        'id': '104',
        'description': 'Tx date',
        'sourceType': 'manual',
        'transactionDate': '2026-06-30T05:30:00Z',
        'createdAt': zTs,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.transactionDate, isA<String>());
      expect(entry.transactionDate, '2026-06-30T05:30:00Z');
      expect(entry.transactionDate!.endsWith('Z'), isTrue);
    });

    test('TC-17: transactionDate null handled correctly', () {
      final json = {
        'id': '105',
        'description': 'No tx date',
        'sourceType': 'manual',
        'transactionDate': null,
        'createdAt': zTs,
        'lines': <Map<String, dynamic>>[],
      };
      final entry = JournalEntry.fromJson(json);
      expect(entry.transactionDate, isNull);
    });
  });

  group('ChecklistEntry (TC-18, TC-19)', () {
    test(
        'TC-18: createdAt parses Z-suffix input into DateTime via parseApiDateTime',
        () {
      final json = {
        'id': 1,
        'template_id': 10,
        'checklist_date': '2026-06-30',
        'completed': false,
        'completed_by': '',
        'completed_at': null,
        'created_at': zTs,
      };
      final entry = ChecklistEntry.fromJson(json);
      expect(entry.createdAt, isA<DateTime>());
      expect(entry.createdAt!.toUtc(), DateTime.parse(zTs).toUtc());
    });

    test('TC-18: createdAt null handled correctly', () {
      final json = {
        'id': 2,
        'template_id': 10,
        'checklist_date': '2026-06-30',
        'completed': false,
        'completed_by': '',
        'completed_at': null,
        'created_at': null,
      };
      final entry = ChecklistEntry.fromJson(json);
      expect(entry.createdAt, isNull);
    });

    test('TC-19: completedAt parses nullable DateTime with Z-suffix input',
        () {
      final json = {
        'id': 3,
        'template_id': 10,
        'checklist_date': '2026-06-30',
        'completed': true,
        'completed_by': 'Tân',
        'completed_at': '2026-06-30T08:00:00Z',
        'created_at': zTs,
      };
      final entry = ChecklistEntry.fromJson(json);
      expect(entry.completedAt, isA<DateTime>());
      expect(entry.completedAt!.toUtc(),
          DateTime.parse('2026-06-30T08:00:00Z').toUtc());
    });

    test('TC-19: completedAt null when not completed', () {
      final json = {
        'id': 4,
        'template_id': 10,
        'checklist_date': '2026-06-30',
        'completed': false,
        'completed_by': '',
        'completed_at': null,
        'created_at': zTs,
      };
      final entry = ChecklistEntry.fromJson(json);
      expect(entry.completedAt, isNull);
    });
  });

  group('ChecklistTemplate (TC-20)', () {
    test('TC-20: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': 5,
        'name': 'Bật lò',
        'period': 'opening',
        'sort_order': 1,
        'active': true,
        'created_at': zTs,
      };
      final tmpl = ChecklistTemplate.fromJson(json);
      expect(tmpl.createdAt, isA<String>());
      expect(tmpl.createdAt, zTs);
      expect(tmpl.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-20: createdAt null handled correctly', () {
      final json = {
        'id': 6,
        'name': 'No date',
        'period': 'closing',
        'sort_order': 0,
        'active': true,
        'created_at': null,
      };
      final tmpl = ChecklistTemplate.fromJson(json);
      expect(tmpl.createdAt, isNull);
    });
  });

  group('Account (TC-21)', () {
    test('TC-21: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': '1',
        'code': '1100',
        'name': 'Cash on Hand',
        'type': 'asset',
        'parentId': null,
        'isActive': true,
        'createdAt': zTs,
        'children': <Account>[],
      };
      final acct = Account.fromJson(json);
      expect(acct.createdAt, isA<String>());
      expect(acct.createdAt, zTs);
      expect(acct.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-21: createdAt null handled correctly', () {
      final json = {
        'id': '2',
        'code': '1200',
        'name': 'Bank',
        'type': 'asset',
        'isActive': true,
        'createdAt': null,
        'children': <Account>[],
      };
      final acct = Account.fromJson(json);
      expect(acct.createdAt, isNull);
    });
  });

  group('CatalogPhoto (TC-22)', () {
    test('TC-22: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': 1,
        'product_id': 10,
        'file_path': 'photos/abc.jpg',
        'caption': '',
        'tags': '',
        'position': 0,
        'created_at': zTs,
        'photo_hash': 'abc123',
      };
      final photo = CatalogPhoto.fromJson(json);
      expect(photo.createdAt, isA<String>());
      expect(photo.createdAt, zTs);
      expect(photo.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-22: createdAt null handled correctly', () {
      final json = {
        'id': 2,
        'product_id': 10,
        'file_path': 'photos/def.jpg',
        'created_at': null,
      };
      final photo = CatalogPhoto.fromJson(json);
      expect(photo.createdAt, isNull);
    });
  });

  group('CatalogBrowsePhoto (TC-23)', () {
    test('TC-23: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': 1,
        'product_id': 10,
        'file_path': 'photos/abc.jpg',
        'caption': '',
        'tags': '',
        'position': 0,
        'created_at': zTs,
        'photo_hash': 'abc123',
        'product_name': 'Bánh kem',
      };
      final photo = CatalogBrowsePhoto.fromJson(json);
      expect(photo.createdAt, isA<String>());
      expect(photo.createdAt, zTs);
      expect(photo.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-23: createdAt null handled correctly', () {
      final json = {
        'id': 2,
        'product_id': 10,
        'file_path': 'photos/def.jpg',
        'product_name': 'Bánh mì',
        'created_at': null,
      };
      final photo = CatalogBrowsePhoto.fromJson(json);
      expect(photo.createdAt, isNull);
    });
  });

  group('EventPhoto (TC-24)', () {
    test('TC-24: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': 1,
        'event_id': 10,
        'photo_id': 5,
        'photo_hash': 'abc123',
        'tags': '',
        'position': 0,
        'created_at': zTs,
      };
      final photo = EventPhoto.fromJson(json);
      expect(photo.createdAt, isA<String>());
      expect(photo.createdAt, zTs);
      expect(photo.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-24: createdAt null handled correctly', () {
      final json = {
        'id': 2,
        'event_id': 10,
        'photo_id': 5,
        'photo_hash': 'abc123',
        'created_at': null,
      };
      final photo = EventPhoto.fromJson(json);
      expect(photo.createdAt, isNull);
    });
  });

  group('OrderPhoto (TC-25)', () {
    test('TC-25: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': 1,
        'order_id': 10,
        'photo_hash': 'abc123',
        'tags': '',
        'position': 0,
        'work_item_id': null,
        'created_at': zTs,
      };
      final photo = OrderPhoto.fromJson(json);
      expect(photo.createdAt, isA<String>());
      expect(photo.createdAt, zTs);
      expect(photo.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-25: createdAt null handled correctly', () {
      final json = {
        'id': 2,
        'order_id': 10,
        'photo_hash': 'abc123',
        'created_at': null,
      };
      final photo = OrderPhoto.fromJson(json);
      expect(photo.createdAt, isNull);
    });
  });

  group('WorkItem (TC-26, TC-27)', () {
    test('TC-26: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': '1',
        'orderId': '10',
        'productId': 'P001',
        'productName': 'Bánh kem',
        'quantity': 1,
        'unitPrice': 200000.0,
        'notes': '',
        'status': 'pending',
        'createdAt': zTs,
        'updatedAt': '2026-06-30T06:00:00Z',
      };
      final item = WorkItem.fromJson(json);
      expect(item.createdAt, isA<String>());
      expect(item.createdAt, zTs);
      expect(item.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-26: createdAt null handled correctly', () {
      final json = {
        'id': '2',
        'orderId': '10',
        'productName': 'Bánh mì',
        'createdAt': null,
        'updatedAt': null,
      };
      final item = WorkItem.fromJson(json);
      expect(item.createdAt, isNull);
    });

    test('TC-27: updatedAt is a String field with Z-suffix format', () {
      final json = {
        'id': '3',
        'orderId': '10',
        'productName': 'Bánh bông lan',
        'createdAt': zTs,
        'updatedAt': '2026-06-30T06:30:00Z',
      };
      final item = WorkItem.fromJson(json);
      expect(item.updatedAt, isA<String>());
      expect(item.updatedAt, '2026-06-30T06:30:00Z');
      expect(item.updatedAt!.endsWith('Z'), isTrue);
    });

    test('TC-27: updatedAt null handled correctly', () {
      final json = {
        'id': '4',
        'orderId': '10',
        'productName': 'Bánh',
        'createdAt': zTs,
        'updatedAt': null,
      };
      final item = WorkItem.fromJson(json);
      expect(item.updatedAt, isNull);
    });
  });

  group('CakeQueueItem (TC-28)', () {
    test('TC-28: createdAt is a String field with Z-suffix format', () {
      final json = {
        'id': '1',
        'orderId': '10',
        'orderRef': 'ORD-001',
        'customerName': 'Nguyễn Văn A',
        'productId': 'P001',
        'productName': 'Bánh kem',
        'quantity': 1,
        'unitPrice': 200000.0,
        'notes': '',
        'position': 0,
        'status': 'pending',
        'isBirthday': false,
        'createdAt': zTs,
      };
      final item = CakeQueueItem.fromJson(json);
      expect(item.createdAt, isA<String>());
      expect(item.createdAt, zTs);
      expect(item.createdAt!.endsWith('Z'), isTrue);
    });

    test('TC-28: createdAt null handled correctly', () {
      final json = {
        'id': '2',
        'orderId': '10',
        'orderRef': 'ORD-002',
        'customerName': 'Trần B',
        'productId': '',
        'productName': 'Bánh mì',
        'quantity': 2,
        'unitPrice': 15000.0,
        'notes': '',
        'position': 0,
        'status': 'pending',
        'isBirthday': false,
        'createdAt': null,
      };
      final item = CakeQueueItem.fromJson(json);
      expect(item.createdAt, isNull);
    });
  });
}
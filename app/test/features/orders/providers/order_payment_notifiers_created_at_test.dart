import 'package:bakery_app/features/orders/providers/order_record_payment_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_edit_payment_notifier.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderRecordPaymentNotifier createdAt (DG-415 Phase 3 / FR1, FR7)', () {
    test('build() seeds createdAt to the current local time (FR1/AC1)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = DateTime.now();
      final state = container.read(orderRecordPaymentProvider);
      final after = DateTime.now();
      expect(state.createdAt, isNotNull);
      // Within the same wall-clock second as build().
      expect(
        state.createdAt!.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        state.createdAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('setCreatedDate replaces the date and keeps the time', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderRecordPaymentProvider.notifier);
      final initial = container.read(orderRecordPaymentProvider).createdAt!;
      notifier.setCreatedDate(DateTime(2024, 6, 15));
      final updated = container.read(orderRecordPaymentProvider).createdAt!;
      expect(updated.year, 2024);
      expect(updated.month, 6);
      expect(updated.day, 15);
      // Time component preserved.
      expect(updated.hour, initial.hour);
      expect(updated.minute, initial.minute);
    });

    test('setCreatedTime replaces the time and keeps the date', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderRecordPaymentProvider.notifier);
      final initial = container.read(orderRecordPaymentProvider).createdAt!;
      notifier.setCreatedTime(const TimeOfDay(hour: 8, minute: 30));
      final updated = container.read(orderRecordPaymentProvider).createdAt!;
      expect(updated.hour, 8);
      expect(updated.minute, 30);
      // Date component preserved.
      expect(updated.year, initial.year);
      expect(updated.month, initial.month);
      expect(updated.day, initial.day);
    });
  });

  group('OrderEditPaymentNotifier createdAt (DG-415 Phase 3 / FR2, AC3)', () {
    test('seed() pre-fills createdAt from the existing transaction (AC3)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderEditPaymentProvider.notifier);
      const existing = '2026-08-16T06:00:00Z';
      final existingDt = DateTime.parse(existing);
      notifier.seed(
        type: 'payment',
        method: 'transfer',
        paymentSource: 'TK Phượng VCB',
        createdAt: existingDt,
      );
      final state = container.read(orderEditPaymentProvider);
      expect(state.createdAt, existingDt);
    });

    test('setCreatedDate merges date into the seeded createdAt (FR2)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderEditPaymentProvider.notifier);
      notifier.seed(
        type: 'payment',
        method: 'cash',
        createdAt: DateTime(2026, 8, 16, 6, 0, 0),
      );
      notifier.setCreatedDate(DateTime(2025, 1, 10));
      final updated = container.read(orderEditPaymentProvider).createdAt!;
      expect(updated.year, 2025);
      expect(updated.month, 1);
      expect(updated.day, 10);
      // Seeded time preserved.
      expect(updated.hour, 6);
      expect(updated.minute, 0);
    });

    test('setCreatedTime merges time into the seeded createdAt (FR2)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderEditPaymentProvider.notifier);
      notifier.seed(
        type: 'payment',
        method: 'cash',
        createdAt: DateTime(2026, 8, 16, 6, 0, 0),
      );
      notifier.setCreatedTime(const TimeOfDay(hour: 18, minute: 45));
      final updated = container.read(orderEditPaymentProvider).createdAt!;
      expect(updated.hour, 18);
      expect(updated.minute, 45);
      // Seeded date preserved.
      expect(updated.year, 2026);
      expect(updated.month, 8);
      expect(updated.day, 16);
    });
  });
}
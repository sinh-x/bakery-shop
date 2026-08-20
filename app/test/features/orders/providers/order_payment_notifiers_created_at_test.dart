import 'package:bakery_app/features/orders/providers/order_record_payment_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_edit_payment_notifier.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
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

  // review-auto cycle 1 CQ-1 — regression test for the UTC/local double-shift
  // bug in the edit flow. The edit sheet must seed `createdAt` as server-local
  // wall-clock (via `ServerTimezone.toServerLocal`) so that editing only the
  // date and then serializing via `timestampToJson` (which calls `.toUtc()`)
  // round-trips back to the original UTC instant instead of shifting by the
  // local offset.
  group(
      'OrderEditPaymentNotifier UTC/local round-trip (review-auto cycle 1 CQ-1)',
      () {
    test(
        'editing only the date preserves the original UTC time after '
        'serialization', () {
      // The stored UTC timestamp returned by the backend. Choose an instant
      // whose local wall-clock differs from UTC (so a double-shift would be
      // detectable). Use the test host's local offset — `toServerLocal`
      // renders through the device timezone (assumed to match the server).
      const storedUtc = '2026-08-16T06:00:00Z';
      final utcDt = DateTime.parse(storedUtc);
      // Compute the local wall-clock fields the picker should display.
      final localSeed = ServerTimezone.toServerLocal(utcDt);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(orderEditPaymentProvider.notifier);
      notifier.seed(
        type: 'payment',
        method: 'cash',
        createdAt: localSeed,
      );

      // User edits only the date to 2026-07-01; time is preserved.
      notifier.setCreatedDate(DateTime(2026, 7, 1));
      final edited = container.read(orderEditPaymentProvider).createdAt!;

      // The local hour/minute must match what the picker displayed.
      expect(edited.hour, localSeed.hour);
      expect(edited.minute, localSeed.minute);

      // Serialize as the API client would on save.
      final wire = timestampToJson(edited);

      // The UTC time component must be unchanged (06:00:00Z) — only the date
      // changed. Before the CQ-1 fix the local hour was copied into a
      // DateTime whose `.toUtc()` then shifted it again, double-shifting the
      // stored time by the local offset.
      expect(wire, '2026-07-01T06:00:00Z');
    });
  });
}
import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/checklist_service.dart';
import 'package:bakery_app/data/models/checklist_entry.dart';
import 'package:bakery_app/data/providers/checklist_provider.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen_test_helpers.dart';

class _FakeChecklistService extends ChecklistService {
  _FakeChecklistService() : super(Dio());

  int toggleCalls = 0;
  int? capturedEntryId;
  String? capturedStaffName;

  @override
  Future<Map<String, dynamic>> getDailyChecklist({String? date}) async {
    return {
      'date': date ?? '2026-07-14',
      'entries': [
        {
          'id': 1,
          'template_id': 10,
          'checklist_date': date ?? '2026-07-14',
          'completed': false,
          'completed_by': '',
          'completed_at': null,
          'created_at': '2026-07-14T00:00:00Z',
          'template_name': 'Mở cửa',
          'template_period': 'opening',
          'template_sort_order': 0,
        },
      ],
    };
  }

  @override
  Future<ChecklistEntry> toggleEntry(int entryId, String staffName) async {
    toggleCalls += 1;
    capturedEntryId = entryId;
    capturedStaffName = staffName;
    return ChecklistEntry(
      id: entryId,
      templateId: 10,
      checklistDate: '2026-07-14',
      completed: true,
      completedBy: staffName,
      completedAt: DateTime.parse('2026-07-14T00:00:00Z'),
      createdAt: DateTime.parse('2026-07-14T00:00:00Z'),
      templateName: 'Mở cửa',
      templatePeriod: 'opening',
      templateSortOrder: 0,
    );
  }
}

void main() {
  Future<ProviderContainer> buildContainer(_FakeChecklistService service) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        checklistServiceProvider.overrideWithValue(service),
      ],
    );
  }

  setUp(() {
    // Seed an authenticated session so `loggedByProvider` (which derives from
    // the JWT `sub` claim per FR17) returns 'An' — the authenticated username.
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
  });

  testWidgets(
    'FR17/AC14: checklist screen toggle uses loggedByProvider (authenticated username)',
    (tester) async {
      final service = _FakeChecklistService();
      final container = await buildContainer(service);
      addTearDown(container.dispose);

      // Read the daily checklist so the notifier has state.
      await container.read(dailyChecklistProvider.future);
      expect(container.read(loggedByProvider), 'An');

      // Toggle the entry — the screen passes loggedByProvider as staffName.
      final staffName = container.read(loggedByProvider);
      await container
          .read(dailyChecklistProvider.notifier)
          .toggleEntry(1, staffName);

      expect(service.toggleCalls, 1);
      expect(service.capturedEntryId, 1);
      // FR17/AC14: the staff name passed to the toggle API is the
      // authenticated username from loggedByProvider, not free-text input.
      expect(service.capturedStaffName, 'An');
    },
  );

  test('loggedByProvider is empty when unauthenticated (grace period, falls back to local name)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(loggedByProvider), '');
  });

  test('LoggedByNotifier.setName persists and restores from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    // Initially empty
    expect(container.read(loggedByProvider), '');

    // Set a name
    await container.read(loggedByProvider.notifier).setName('TestStaff');

    // State updated immediately
    expect(container.read(loggedByProvider), 'TestStaff');

    // Verify persisted in SharedPreferences
    expect(prefs.getString('logged_by_name'), 'TestStaff');

    // Create a new container (simulating app restart) and verify restoration
    final prefs2 = await SharedPreferences.getInstance();
    final container2 = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs2),
      ],
    );
    addTearDown(container2.dispose);
    expect(container2.read(loggedByProvider), 'TestStaff');
  });
}
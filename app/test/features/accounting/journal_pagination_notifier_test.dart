import 'package:bakery_app/data/api/accounting_service.dart';
import 'package:bakery_app/data/models/journal_entry.dart';
import 'package:bakery_app/features/accounting/providers/journal_pagination_notifier.dart';
import 'package:bakery_app/providers/accounting_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [AccountingService] that records calls and returns canned pages.
///
/// Each entry in [pages] is returned in order for successive [listJournal]
/// calls. If [errorOnPage] is set, the call at that 0-based page index throws
/// instead of returning a page — used to exercise [JournalPaginationNotifier.loadMore]
/// error handling (DG-189 Phase 5.6-c2, M-3).
class _FakeAccountingService extends AccountingService {
  _FakeAccountingService(this.pages, {this.errorOnPage})
      : super(Dio());

  final List<JournalListResponse> pages;
  final int? errorOnPage;

  int callCount = 0;
  final List<Map<String, dynamic>> capturedCalls = [];

  @override
  Future<JournalListResponse> listJournal({
    String? since,
    String? until,
    int? accountId,
    String? sourceType,
    int? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    capturedCalls.add({
      'since': since,
      'until': until,
      'accountId': accountId,
      'sourceType': sourceType,
      'sourceId': sourceId,
      'limit': limit,
      'offset': offset,
    });
    final page = callCount;
    callCount += 1;
    if (errorOnPage == page) {
      throw Exception('boom on page $page');
    }
    if (page >= pages.length) {
      return JournalListResponse(
        total: pages.isEmpty ? 0 : pages.last.total,
        limit: limit,
        offset: offset,
        items: const <JournalEntry>[],
      );
    }
    return pages[page];
  }
}

JournalEntry _entry(String id) {
  return JournalEntry(id: id, description: 'entry $id');
}

ProviderContainer _container(_FakeAccountingService service) {
  return ProviderContainer(
    overrides: [accountingServiceProvider.overrideWithValue(service)],
  );
}

const _filter = JournalFilter(limit: 2, offset: 0);

void main() {
  test('initial build() populates state with first page', () async {
    final service = _FakeAccountingService([
      JournalListResponse(
        total: 5,
        limit: 2,
        offset: 0,
        items: [_entry('1'), _entry('2')],
      ),
    ]);
    final container = _container(service);
    addTearDown(container.dispose);

    await container.read(journalPaginationProvider(_filter).future);

    final state = container.read(journalPaginationProvider(_filter)).value!;
    expect(state.loaded.map((e) => e.id), ['1', '2']);
    expect(state.total, 5);
    expect(state.offset, 0);
    expect(state.isLoadingMore, isFalse);
    expect(state.loadMoreError, isNull);
    expect(state.hasMore, isTrue);
    expect(service.callCount, 1);
  });

  test('loadMore() appends the next page to loaded entries', () async {
    final service = _FakeAccountingService([
      JournalListResponse(
        total: 5,
        limit: 2,
        offset: 0,
        items: [_entry('1'), _entry('2')],
      ),
      JournalListResponse(
        total: 5,
        limit: 2,
        offset: 2,
        items: [_entry('3'), _entry('4')],
      ),
      JournalListResponse(
        total: 5,
        limit: 2,
        offset: 4,
        items: [_entry('5')],
      ),
    ]);
    final container = _container(service);
    addTearDown(container.dispose);

    await container.read(journalPaginationProvider(_filter).future);

    final notifier = container.read(
      journalPaginationProvider(_filter).notifier,
    );
    await notifier.loadMore();

    final state = container.read(journalPaginationProvider(_filter)).value!;
    expect(state.loaded.map((e) => e.id), ['1', '2', '3', '4']);
    expect(state.total, 5);
    expect(state.offset, 2);
    expect(state.isLoadingMore, isFalse);
    expect(state.hasMore, isTrue);

    await notifier.loadMore();

    final state2 = container.read(journalPaginationProvider(_filter)).value!;
    expect(state2.loaded.map((e) => e.id), ['1', '2', '3', '4', '5']);
    expect(state2.hasMore, isFalse);
    expect(service.callCount, 3);
  });

  test('loadMore() is a no-op when already loading more', () async {
    final service = _FakeAccountingService([
      JournalListResponse(
        total: 5,
        limit: 2,
        offset: 0,
        items: [_entry('1'), _entry('2')],
      ),
    ]);
    final container = _container(service);
    addTearDown(container.dispose);

    await container.read(journalPaginationProvider(_filter).future);

    final notifier = container.read(
      journalPaginationProvider(_filter).notifier,
    );
    // Manually mark as loading to simulate an in-flight request.
    final current = container.read(journalPaginationProvider(_filter)).value!;
    container.read(journalPaginationProvider(_filter).notifier).state =
        AsyncData(current.copyWith(isLoadingMore: true));

    await notifier.loadMore();

    // No additional API call should have happened.
    expect(service.callCount, 1);
    final state = container.read(journalPaginationProvider(_filter)).value!;
    expect(state.isLoadingMore, isTrue);
  });

  test('loadMore() is a no-op when no more pages remain', () async {
    final service = _FakeAccountingService([
      JournalListResponse(
        total: 2,
        limit: 2,
        offset: 0,
        items: [_entry('1'), _entry('2')],
      ),
    ]);
    final container = _container(service);
    addTearDown(container.dispose);

    await container.read(journalPaginationProvider(_filter).future);

    final stateBefore = container.read(journalPaginationProvider(_filter)).value!;
    expect(stateBefore.hasMore, isFalse);

    final notifier = container.read(
      journalPaginationProvider(_filter).notifier,
    );
    await notifier.loadMore();

    expect(service.callCount, 1);
    final stateAfter = container.read(journalPaginationProvider(_filter)).value!;
    expect(stateAfter.loaded.map((e) => e.id), ['1', '2']);
    expect(stateAfter.isLoadingMore, isFalse);
  });

  test(
    'loadMore() error preserves accumulated entries and surfaces loadMoreError',
    () async {
      final service = _FakeAccountingService(
        [
          JournalListResponse(
            total: 5,
            limit: 2,
            offset: 0,
            items: [_entry('1'), _entry('2')],
          ),
        ],
        errorOnPage: 1,
      );
      final container = _container(service);
      addTearDown(container.dispose);

      await container.read(journalPaginationProvider(_filter).future);

      final before = container.read(journalPaginationProvider(_filter)).value!;
      expect(before.loaded.map((e) => e.id), ['1', '2']);

      final notifier = container.read(
        journalPaginationProvider(_filter).notifier,
      );
      await notifier.loadMore();

      final after = container.read(journalPaginationProvider(_filter)).value!;
      // M-1: accumulated entries are preserved, not discarded.
      expect(after.loaded.map((e) => e.id), ['1', '2']);
      expect(after.isLoadingMore, isFalse);
      expect(after.loadMoreError, isNotNull);
      expect(after.hasMore, isTrue);
    },
  );
}
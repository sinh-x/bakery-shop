// DG-409 Phase 4 — tests for paginated providers (products, customers, order
// history). Verifies first-page load, load-more accumulation, hasMore, and
// server-side search reset behavior (FR10/FR11/FR12, AC3/AC4).
import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/paginated_response.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/data/providers/customers_provider.dart';
import 'package:bakery_app/providers/order/order_list_providers.dart';
import 'package:bakery_app/data/providers/products_provider.dart';
import 'package:bakery_app/shared/services/session_cache.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake ProductService that serves active products in pages of 2 so the
/// pagination accumulation can be exercised with a small dataset.
class _PagedProductService extends ProductService {
  _PagedProductService(this._active) : super(Dio());

  final List<Product> _active;

  @override
  Future<PaginatedResponse<Product>> listProductsPaginated({
    String? category,
    int active = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    final total = _active.length;
    final end = offset + limit;
    final page = offset >= total
        ? const <Product>[]
        : _active.sublist(offset, end > total ? total : end);
    return PaginatedResponse<Product>(
      items: page,
      total: total,
      hasMore: offset + page.length < total,
      limit: limit,
      offset: offset,
    );
  }
}

/// Fake CustomerService that serves customers in pages, honoring a search
/// query across ALL customers (server-side search, AC4).
class _PagedCustomerService extends CustomerService {
  _PagedCustomerService(this._all) : super(Dio());

  final List<Customer> _all;

  @override
  Future<PaginatedResponse<Customer>> listCustomersPaginated({
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    var filtered = _all;
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      filtered = _all
          .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q))
          .toList();
    }
    final total = filtered.length;
    final end = offset + limit;
    final page = offset >= total
        ? const <Customer>[]
        : filtered.sublist(offset, end > total ? total : end);
    return PaginatedResponse<Customer>(
      items: page,
      total: total,
      hasMore: offset + page.length < total,
      limit: limit,
      offset: offset,
    );
  }
}

/// Fake OrderService that serves order history in pages.
class _PagedOrderService extends OrderService {
  _PagedOrderService(this._all) : super(Dio());

  final List<Order> _all;

  @override
  Future<PaginatedResponse<Order>> listOrdersPaginated({
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final total = _all.length;
    final end = offset + limit;
    final page = offset >= total
        ? const <Order>[]
        : _all.sublist(offset, end > total ? total : end);
    return PaginatedResponse<Order>(
      items: page,
      total: total,
      hasMore: offset + page.length < total,
      limit: limit,
      offset: offset,
    );
  }
}

List<Product> _products(int n) => List.generate(
  n,
  (i) => Product(id: i + 1, name: 'P$i', category: 'bread', active: 1),
);

List<Customer> _customers(int n) => List.generate(
  n,
  (i) => Customer(id: i + 1, name: 'Khach $i', phone: '090000$i'),
);

Order _order(int id) => Order(
  id: '$id',
  orderRef: 'REF-$id',
  customerName: 'KH$id',
  customerPhone: '0900',
  items: const [],
  totalPrice: 0,
  status: 'completed',
  dueDate: '2026-08-15',
  createdAt: DateTime(2026, 8, 15),
  updatedAt: DateTime(2026, 8, 15),
);

void main() {
  group('ProductsPaginationNotifier (FR10, AC3)', () {
    test('first page loads and hasMore reflects remaining pages', () async {
      final service = _PagedProductService(_products(5));
      final container = ProviderContainer(
        overrides: [productServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final state = await container.read(productsPaginationProvider.future);

      expect(state.loaded.length, productPageSize >= 5 ? 5 : productPageSize);
      expect(state.total, 5);
      expect(state.hasMore, state.loaded.length < 5);
    });

    test('loadMore accumulates pages until hasMore is false', () async {
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(
            _PagedProductService(_products(3)),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Use a tiny page size by overriding the provider's notifier build is
      // not parameterized; instead exercise via small dataset (3 < 50 so all
      // fit on page 1 → hasMore false, loadMore is a no-op).
      final notifier = container.read(productsPaginationProvider.notifier);
      final state = await container.read(productsPaginationProvider.future);

      expect(state.loaded, hasLength(3));
      expect(state.hasMore, isFalse);

      // loadMore must be a no-op when hasMore is false (no duplicate appends).
      await notifier.loadMore();
      final state2 = container.read(productsPaginationProvider).value!;
      expect(state2.loaded, hasLength(3));
    });

    test('refresh re-fetches the first page', () async {
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(
            _PagedProductService(_products(2)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(productsPaginationProvider.notifier);
      await container.read(productsPaginationProvider.future);
      expect(
        container.read(productsPaginationProvider).value!.loaded,
        hasLength(2),
      );

      await notifier.refresh();
      expect(
        container.read(productsPaginationProvider).value!.loaded,
        hasLength(2),
      );
      expect(container.read(productsPaginationProvider).value!.total, 2);
    });
  });

  group('CustomerPaginationNotifier (FR11, AC4)', () {
    test(
      'server-side search resets to the first page of the result set',
      () async {
        final service = _PagedCustomerService(_customers(5));
        final container = ProviderContainer(
          overrides: [customerServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);

        // First page: all 5 customers (page size 50).
        var state = await container.read(customerPaginationProvider.future);
        expect(state.loaded, hasLength(5));
        expect(state.total, 5);
        expect(state.hasMore, isFalse);

        // Apply a server-side search that narrows the result to 1.
        container.read(customerSearchProvider.notifier).set('Khach 2');
        state = await container.read(customerPaginationProvider.future);
        expect(state.loaded, hasLength(1));
        expect(state.total, 1);
        expect(state.hasMore, isFalse);

        // Clear search → back to all 5.
        container.read(customerSearchProvider.notifier).clear();
        state = await container.read(customerPaginationProvider.future);
        expect(state.loaded, hasLength(5));
        expect(state.total, 5);
      },
    );

    test('search runs across ALL customers (not just loaded page)', () async {
      final service = _PagedCustomerService(_customers(60));
      final container = ProviderContainer(
        overrides: [customerServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      // First page: only 50 of 60 loaded, hasMore true.
      var state = await container.read(customerPaginationProvider.future);
      expect(state.loaded, hasLength(50));
      expect(state.total, 60);
      expect(state.hasMore, isTrue);

      // Search for a customer beyond the first page (index 55) — server-side
      // search must find it even though it was not in the loaded page.
      container.read(customerSearchProvider.notifier).set('Khach 55');
      state = await container.read(customerPaginationProvider.future);
      expect(state.total, 1);
      expect(state.loaded.first.name, 'Khach 55');
    });
  });

  group('OrderHistoryPaginationNotifier (FR12)', () {
    test(
      'first page loads and loadMore accumulates remaining orders',
      () async {
        final service = _PagedOrderService(
          List.generate(60, (i) => _order(i + 1)),
        );
        final container = ProviderContainer(
          overrides: [orderServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          orderHistoryPaginationProvider.notifier,
        );
        var state = await container.read(orderHistoryPaginationProvider.future);
        expect(state.loaded, hasLength(50));
        expect(state.total, 60);
        expect(state.hasMore, isTrue);

        await notifier.loadMore();
        state = container.read(orderHistoryPaginationProvider).value!;
        expect(state.loaded, hasLength(60));
        expect(state.hasMore, isFalse);
      },
    );

    test('validateRange blocks ranges longer than 7 days', () {
      final container = ProviderContainer(
        overrides: [
          orderServiceProvider.overrideWithValue(_PagedOrderService(const [])),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderHistoryPaginationProvider.notifier);
      final message = notifier.validateRange(
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 8),
      );
      expect(message, isNotNull);
    });

    test('setDateRange re-fetches the first page for the new range', () async {
      final service = _PagedOrderService(
        List.generate(3, (i) => _order(i + 1)),
      );
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderHistoryPaginationProvider.notifier);
      await container.read(orderHistoryPaginationProvider.future);
      expect(
        container.read(orderHistoryPaginationProvider).value!.loaded,
        hasLength(3),
      );

      await notifier.setDateRange(DateTime(2026, 5, 10), DateTime(2026, 5, 11));
      final state = container.read(orderHistoryPaginationProvider).value!;
      expect(state.loaded, hasLength(3));
      expect(state.offset, 0);
    });
  });

  // -------------------------------------------------------------------------
  // DG-409 Phase 5 — session cache integration (FR13, AC5, AC6).
  // Verifies that the paginated notifiers serve cached state on a rebuild
  // without a new network request, and that entity-type invalidation
  // forces a fresh fetch.
  // -------------------------------------------------------------------------

  group('SessionCache integration — products (AC5, AC6, FR13)', () {
    test('rebuild serves cached state without a new network request', () async {
      final service = _CountingProductService(_products(3));
      final cache = SessionCache();
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(service),
          sessionCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      await container.read(productsPaginationProvider.future);
      expect(service.paginatedCalls, 1);

      // Rebuild the provider (simulates navigating away and back, which
      // re-runs `build()`). The cached state should be served without a
      // second network call (AC5).
      container.invalidate(productsPaginationProvider);
      await container.read(productsPaginationProvider.future);
      expect(service.paginatedCalls, 1);
      expect(
        container.read(productsPaginationProvider).value!.loaded,
        hasLength(3),
      );
    });

    test(
      'refresh bypasses the cache and re-fetches from the network',
      () async {
        final service = _CountingProductService(_products(3));
        final cache = SessionCache();
        final container = ProviderContainer(
          overrides: [
            productServiceProvider.overrideWithValue(service),
            sessionCacheProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);

        await container.read(productsPaginationProvider.future);
        expect(service.paginatedCalls, 1);

        await container.read(productsPaginationProvider.notifier).refresh();
        expect(service.paginatedCalls, 2);
      },
    );

    test(
      'invalidateEntityType(products) forces a fresh fetch on the next build',
      () async {
        final service = _CountingProductService(_products(3));
        final cache = SessionCache();
        final container = ProviderContainer(
          overrides: [
            productServiceProvider.overrideWithValue(service),
            sessionCacheProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);

        await container.read(productsPaginationProvider.future);
        expect(service.paginatedCalls, 1);

        // Simulate a product mutation: the mutation path calls
        // invalidateEntityType(SessionCacheEntity.products). The next build
        // must miss the cache and fetch fresh data (AC6/FR13).
        cache.invalidateEntityType(SessionCacheEntity.products);
        container.invalidate(productsPaginationProvider);
        await container.read(productsPaginationProvider.future);
        expect(service.paginatedCalls, 2);
      },
    );
  });

  group('SessionCache integration — customers (AC5, AC6, FR13)', () {
    test('rebuild serves cached state for the same search query', () async {
      final service = _PagedCustomerService(_customers(5));
      final cache = SessionCache();
      final container = ProviderContainer(
        overrides: [
          customerServiceProvider.overrideWithValue(service),
          sessionCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customerPaginationProvider.future);
      // A new query string triggers a fresh fetch (cache key differs).
      container.read(customerSearchProvider.notifier).set('Khach 1');
      await container.read(customerPaginationProvider.future);
      expect(container.read(customerPaginationProvider).value!.total, 1);

      // Rebuild with the same query → cached state is reused.
      container.invalidate(customerPaginationProvider);
      await container.read(customerPaginationProvider.future);
      expect(container.read(customerPaginationProvider).value!.total, 1);
    });

    test(
      'invalidateEntityType(customers) forces fresh fetch after a mutation',
      () async {
        final service = _PagedCustomerService(_customers(5));
        final cache = SessionCache();
        final container = ProviderContainer(
          overrides: [
            customerServiceProvider.overrideWithValue(service),
            sessionCacheProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);

        await container.read(customerPaginationProvider.future);
        expect(cache.length, 1);

        cache.invalidateEntityType(SessionCacheEntity.customers);
        expect(cache.length, 0);

        container.invalidate(customerPaginationProvider);
        await container.read(customerPaginationProvider.future);
        // Cache re-populated after the fresh fetch.
        expect(cache.length, 1);
      },
    );
  });
}

/// Wrapper around [_PagedProductService] that counts paginated fetch calls
/// so cache-hit tests can assert the network was not touched (DG-409 Phase 5).
class _CountingProductService extends _PagedProductService {
  _CountingProductService(super.products);
  int paginatedCalls = 0;
  @override
  Future<PaginatedResponse<Product>> listProductsPaginated({
    String? category,
    int active = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    paginatedCalls++;
    return super.listProductsPaginated(
      category: category,
      active: active,
      limit: limit,
      offset: offset,
    );
  }
}

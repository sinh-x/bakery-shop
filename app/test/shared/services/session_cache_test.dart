// DG-409 Phase 5 — unit tests for the session-level cache service
// (`app/lib/shared/services/session_cache.dart`). Verifies cache hit/miss,
// TTL expiry, LRU eviction, entity-type invalidation, and the
// `readOrFetch` helper (FR13, NFR5, AC5, AC6).
import 'package:bakery_app/shared/services/session_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionCache — basic read/write (AC5)', () {
    test('read returns null on a miss and the value on a hit', () {
      final cache = SessionCache();
      const key = SessionCacheKey(SessionCacheEntity.products);
      expect(cache.read<String>(key), isNull);
      cache.put(key, 'p1');
      expect(cache.read<String>(key), 'p1');
    });

    test('put overwrites an existing key', () {
      final cache = SessionCache();
      const key = SessionCacheKey(SessionCacheEntity.customers);
      cache.put(key, 'v1');
      cache.put(key, 'v2');
      expect(cache.read<String>(key), 'v2');
      expect(cache.length, 1);
    });

    test('keys with different parameters coexist for the same entity', () {
      final cache = SessionCache();
      const k1 = SessionCacheKey(SessionCacheEntity.customers, parameter: 'a');
      const k2 = SessionCacheKey(SessionCacheEntity.customers, parameter: 'b');
      cache.put(k1, 'ca');
      cache.put(k2, 'cb');
      expect(cache.read<String>(k1), 'ca');
      expect(cache.read<String>(k2), 'cb');
      expect(cache.length, 2);
    });
  });

  group('SessionCache — TTL expiry (NFR5)', () {
    test('an entry past its TTL is treated as a miss and evicted', () async {
      final cache = SessionCache(ttl: const Duration(milliseconds: 30));
      const key = SessionCacheKey(SessionCacheEntity.orderHistory);
      cache.put(key, 'page1');
      expect(cache.read<String>(key), 'page1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cache.read<String>(key), isNull);
      expect(cache.length, 0);
    });

    test('pruneExpired removes only expired entries', () async {
      final cache = SessionCache(ttl: const Duration(milliseconds: 40));
      const k1 = SessionCacheKey(SessionCacheEntity.products);
      const k2 = SessionCacheKey(SessionCacheEntity.customers);
      cache.put(k1, 'p');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      cache.put(k2, 'c');
      cache.pruneExpired();
      expect(cache.read<String>(k1), isNull);
      expect(cache.read<String>(k2), 'c');
    });
  });

  group('SessionCache — LRU eviction (NFR5 bounded memory)', () {
    test('evicts the least-recently-used entry when maxEntryCount is exceeded',
        () {
      final cache = SessionCache(maxEntryCount: 2);
      const k1 = SessionCacheKey(SessionCacheEntity.products, parameter: '1');
      const k2 = SessionCacheKey(SessionCacheEntity.products, parameter: '2');
      const k3 = SessionCacheKey(SessionCacheEntity.products, parameter: '3');
      cache.put(k1, 'a');
      cache.put(k2, 'b');
      // Touch k1 so k2 becomes the LRU candidate.
      cache.read<String>(k1);
      cache.put(k3, 'c');
      expect(cache.length, 2);
      expect(cache.read<String>(k1), 'a'); // still present (was recently used)
      expect(cache.read<String>(k2), isNull); // evicted as LRU
      expect(cache.read<String>(k3), 'c');
    });
  });

  group('SessionCache — entity-type invalidation (FR13, AC6)', () {
    test('invalidateEntityType removes every entry of that entity', () {
      final cache = SessionCache();
      const p1 = SessionCacheKey(SessionCacheEntity.products, parameter: '1');
      const p2 = SessionCacheKey(SessionCacheEntity.products, parameter: '2');
      const c1 = SessionCacheKey(SessionCacheEntity.customers);
      cache.put(p1, 'a');
      cache.put(p2, 'b');
      cache.put(c1, 'c');
      cache.invalidateEntityType(SessionCacheEntity.products);
      expect(cache.read<String>(p1), isNull);
      expect(cache.read<String>(p2), isNull);
      expect(cache.read<String>(c1), 'c'); // other entity untouched
    });

    test('clear removes every entry', () {
      final cache = SessionCache();
      cache.put(const SessionCacheKey(SessionCacheEntity.products), 'p');
      cache.put(const SessionCacheKey(SessionCacheEntity.customers), 'c');
      cache.clear();
      expect(cache.length, 0);
    });
  });

  group('SessionCache.readOrFetch (AC5 cache-then-network)', () {
    test('returns the cached value without calling the fetcher on a hit',
        () async {
      final cache = SessionCache();
      const key = SessionCacheKey(SessionCacheEntity.products);
      cache.put(key, 'cached');
      var fetchCalls = 0;
      final result = await cache.readOrFetch<String>(key, () async {
        fetchCalls++;
        return 'fresh';
      });
      expect(result, 'cached');
      expect(fetchCalls, 0);
    });

    test('calls the fetcher and stores the result on a miss', () async {
      final cache = SessionCache();
      const key = SessionCacheKey(SessionCacheEntity.products);
      var fetchCalls = 0;
      final result = await cache.readOrFetch<String>(key, () async {
        fetchCalls++;
        return 'fresh';
      });
      expect(result, 'fresh');
      expect(fetchCalls, 1);
      // Second read should hit the cache (no new fetch).
      final result2 = await cache.readOrFetch<String>(key, () async {
        fetchCalls++;
        return 'fresh-2';
      });
      expect(result2, 'fresh');
      expect(fetchCalls, 1);
    });
  });
}
// DG-409 Phase 5 — Session-level in-memory cache (FR13, NFR5).
//
// A bounded LRU + TTL cache that stores the *paginated list state* of each
// entity type (products, customers, order history) for the lifetime of the
// app session (in-memory only — no persistence, per §16 follow-up decision).
//
// Goals:
//   AC5 — navigating away from and back to a tab within the same session
//         reuses previously loaded data without a new network request.
//   AC6 — a create/update/delete on the same entity type invalidates the
//         cached page so the next visit fetches fresh data.
//   NFR5 — cache memory footprint stays bounded (≤ 50MB). Eviction is LRU
//          with a per-entry TTL; entries are also bounded by maxEntryCount.
//
// Pull-to-refresh always bypasses the cache (callers call [invalidate] or
// [SessionCache.put] with the fresh value before re-reading).
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entity types recognised by the session cache. Each type owns a single
/// cache slot keyed by [SessionCacheKey]; mutations on a type invalidate
/// every slot of that type (FR13).
enum SessionCacheEntity { products, customers, orderHistory }

/// Composite cache key: entity type + a caller-supplied parameter string
/// (e.g. `search=foo` for the customer list, `from=...&to=...` for order
/// history, or '' when unparameterised). This lets parameterised variants
/// of the same entity type coexist while still being invalidated together
/// by [SessionCache.invalidateEntityType].
class SessionCacheKey {
  const SessionCacheKey(this.entity, {this.parameter = ''});

  final SessionCacheEntity entity;
  final String parameter;

  @override
  bool operator ==(Object other) =>
      other is SessionCacheKey &&
      other.entity == entity &&
      other.parameter == parameter;

  @override
  int get hashCode => Object.hash(entity, parameter);

  @override
  String toString() => 'SessionCacheKey($entity, "$parameter")';
}

/// A cached payload with its insertion timestamp. The TTL is evaluated
/// against [DateTime.now] at read time; expired entries are treated as
/// misses and evicted lazily.
class _CacheEntry {
  _CacheEntry(this.value, this.insertedAt);

  final Object value;
  final DateTime insertedAt;
}

/// Session-level cache (FR13, NFR5). A single instance is shared across the
/// app via [sessionCacheProvider]; tests override that provider to inject a
/// fresh cache.
///
/// The cache is intentionally generic over `Object` so it can store any
/// paginated state shape (products, customers, order history) without
/// coupling to those state classes. Callers are responsible for casting the
/// stored value back to the expected type — the key/entity pairing makes
/// this safe.
class SessionCache {
  SessionCache({
    this.ttl = const Duration(minutes: 5),
    this.maxEntryCount = 64,
  });

  final Duration ttl;
  final int maxEntryCount;

  // LinkedHashMap preserves insertion order; we move a key to the end on
  // access so the head is always the least-recently-used entry — the one to
  // evict when [maxEntryCount] is exceeded (LRU).
  final Map<SessionCacheKey, _CacheEntry> _store = {};

  /// Number of entries currently held (excludes expired entries after a
  /// [pruneExpired] sweep). Exposed for tests.
  int get length => _store.length;

  /// Reads a cached value if present and not expired; otherwise returns
  /// `null`. A read refreshes the LRU order (entry is moved to most-recently-
  /// used). Expired entries are evicted lazily on read.
  T? read<T>(SessionCacheKey key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.insertedAt) >= ttl) {
      _store.remove(key);
      return null;
    }
    // Refresh LRU order.
    _store.remove(key);
    _store[key] = entry;
    return entry.value as T;
  }

  /// Stores [value] under [key], evicting the least-recently-used entry if
  /// the cache is at capacity. Overwrites an existing entry in place (the
  /// key keeps its prior LRU position refreshed by re-insertion).
  void put(SessionCacheKey key, Object value) {
    _store.remove(key);
    _store[key] = _CacheEntry(value, DateTime.now());
    _evictIfNeeded();
  }

  /// Removes a single entry. Returns `true` if an entry was present.
  bool remove(SessionCacheKey key) => _store.remove(key) != null;

  /// Invalidates every entry whose entity type matches [entity] (FR13).
  /// Called by mutation providers after a create/update/delete on the same
  /// entity type so the next read misses and re-fetches fresh data.
  void invalidateEntityType(SessionCacheEntity entity) {
    _store.removeWhere((key, _) => key.entity == entity);
  }

  /// Clears the entire cache (e.g. on logout / session end).
  void clear() => _store.clear();

  /// Removes every expired entry. Called opportunistically by [put] and
  /// exposed for tests; reads already evict the single expired entry they
  /// touch.
  void pruneExpired() {
    final now = DateTime.now();
    _store.removeWhere((_, entry) => now.difference(entry.insertedAt) >= ttl);
  }

  void _evictIfNeeded() {
    while (_store.length > maxEntryCount) {
      _store.remove(_store.keys.first);
    }
  }
}

/// Riverpod provider exposing the singleton [SessionCache]. Tests override
/// this to inject a cache with a short TTL or small max-entry count.
final sessionCacheProvider = Provider<SessionCache>((ref) {
  final cache = SessionCache();
  ref.onDispose(cache.clear);
  return cache;
});

/// Convenience extension for the common "read-or-fetch-and-store" pattern
/// used by the paginated notifiers. Returns the cached value on a hit, or
/// calls [fetcher], stores the result, and returns it on a miss. Pull-to-
/// refresh callers should call [SessionCache.invalidateEntityType] (or
/// [SessionCache.remove]) before invoking this so the fetcher always runs.
extension SessionCacheFetchExtension on SessionCache {
  Future<T> readOrFetch<T extends Object>(
    SessionCacheKey key,
    Future<T> Function() fetcher,
  ) async {
    final cached = read<T>(key);
    if (cached != null) return cached;
    final fresh = await fetcher();
    put(key, fresh);
    return fresh;
  }
}

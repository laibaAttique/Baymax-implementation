import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the catalogue that is in use came from.
enum CatalogOrigin { server, cache, bundled }

class CatalogResult<T> {
  final List<T> items;
  final CatalogOrigin origin;
  final int? version;
  const CatalogResult(this.items, this.origin, this.version);
}

/// Fetches a reference catalogue (foods, exercises, …) from Cloud Firestore
/// with a cache-first strategy:
///
/// * Firestore keeps a copy on the device, so it works offline.
/// * One tiny read of `meta/<metaId>` tells us whether the server has a newer
///   `version`; the whole collection is only downloaded again when it changed.
///
/// Returns null when Firestore is unavailable and nothing is cached, in which
/// case the caller falls back to the copy bundled with the app.
class CatalogService {
  CatalogService._();

  static const _timeout = Duration(seconds: 8);

  @visibleForTesting
  static bool needsRefresh({
    required int? cachedVersion,
    required int? serverVersion,
    required bool cacheHasItems,
  }) {
    if (!cacheHasItems) return true;
    if (serverVersion == null) return false; // server unreachable: keep using the cache
    return cachedVersion != serverVersion;
  }

  static Future<CatalogResult<T>?> fetch<T>({
    required String collection,
    required String metaId,
    required T Function(String id, Map<String, dynamic> data) fromDoc,
  }) async {
    try {
      final fs = FirebaseFirestore.instance;

      final cachedVersion = await _version(fs, metaId, Source.cache);
      final serverVersion = await _version(fs, metaId, Source.server);
      final cached = await _items(fs, collection, Source.cache, fromDoc);

      if (!needsRefresh(
        cachedVersion: cachedVersion,
        serverVersion: serverVersion,
        cacheHasItems: cached.isNotEmpty,
      )) {
        return CatalogResult(cached, CatalogOrigin.cache, cachedVersion);
      }

      final fresh = await _items(fs, collection, Source.server, fromDoc);
      if (fresh.isEmpty) {
        return cached.isEmpty ? null : CatalogResult(cached, CatalogOrigin.cache, cachedVersion);
      }
      return CatalogResult(fresh, CatalogOrigin.server, serverVersion);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _version(FirebaseFirestore fs, String metaId, Source source) async {
    try {
      final doc = await fs.collection('meta').doc(metaId).get(GetOptions(source: source)).timeout(_timeout);
      return (doc.data()?['version'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<List<T>> _items<T>(
    FirebaseFirestore fs,
    String collection,
    Source source,
    T Function(String id, Map<String, dynamic> data) fromDoc,
  ) async {
    try {
      final snap = await fs.collection(collection).get(GetOptions(source: source)).timeout(_timeout);
      return [for (final d in snap.docs) fromDoc(d.id, d.data())];
    } catch (_) {
      return <T>[];
    }
  }
}

import 'dart:async';

import 'mini_app_manifest.dart';
import 'mini_app_store.dart';

/// Explicit user grants, separate from app-owned storage, code and archives.
class MiniAppPermissions {
  MiniAppPermissions(this.store) {
    _reconcile();
    store.addListener(_reconcile);
    _hostChanges = store.grantChanges.listen((id) {
      if (!_disposed) {
        _changes.add(id);
      }
    });
  }

  final MiniAppStore store;
  static Set<String> get knownCapabilities => MiniAppManifest.knownCapabilities;
  final Map<String, Set<String>> _cache = {};
  final Map<String, Set<String>> _declared = {};
  final Map<String, int> _cacheVersions = {};
  final Map<String, Future<void>> _loading = {};
  late final StreamSubscription<String> _hostChanges;
  final StreamController<String> _changes = StreamController.broadcast();
  bool _disposed = false;

  Stream<String> get changes => _changes.stream;
  int versionFor(String id) => store.grantVersionFor(id);

  static Set<String> declared(MiniApp app) => {
    ...app.permissions.where(knownCapabilities.contains),
    for (final action in app.actions) ...action.permissions,
  };

  Future<Set<String>> granted(String appId) async {
    await store.load();
    _require(appId);
    for (var attempt = 0; attempt < 8; attempt++) {
      if (_cache.containsKey(appId) &&
          _cacheVersions[appId] == versionFor(appId)) {
        break;
      }
      final loading = _loading[appId] ??= _load(appId);
      try {
        await loading;
      } finally {
        if (identical(_loading[appId], loading)) {
          _loading.remove(appId);
        }
      }
    }
    if (_cacheVersions[appId] != versionFor(appId)) {
      throw const MiniAppException(
        'permission_required',
        'Mini app grants are changing; try the action again.',
      );
    }
    final app = _require(appId);
    final effective = (_cache[appId] ?? <String>{}).intersection(declared(app));
    return Set.unmodifiable(effective);
  }

  Future<void> _load(String id) async {
    final version = versionFor(id);
    final record = await store.readHostData(id, 'grants.json');
    final raw = record['granted'];
    final granted = raw is List
        ? raw.whereType<String>().where(knownCapabilities.contains).toSet()
        : <String>{};
    _cache[id] = granted.intersection(declared(_require(id)));
    _cacheVersions[id] = version;
    // Prune stale declarations on read as well, including after process restart.
    if (granted.length != _cache[id]!.length) {
      await store.updateHostData(
        id,
        'grants.json',
        (map) => map['granted'] = _cache[id]!.toList()..sort(),
      );
    }
  }

  /// Called by explicit host UI gestures, never by an app or model executor.
  Future<void> setGranted(String appId, String capability, bool enabled) async {
    if (!knownCapabilities.contains(capability)) {
      throw const MiniAppException(
        'invalid_permissions',
        'Unknown mini app capability.',
      );
    }
    await store.load();
    final app = _require(appId);
    if (!declared(app).contains(capability)) {
      throw const MiniAppException(
        'undeclared_permission',
        'The app did not declare this capability.',
      );
    }
    await granted(appId);
    if (!identical(store.byId(appId), app)) {
      throw const MiniAppException(
        'app_changed',
        'The mini app changed while its grant was being edited.',
      );
    }
    // Read the live cache after the final await so independent UI toggles
    // cannot replace one another's changes with a captured old snapshot.
    final grants = _cache[appId]!.intersection(declared(app));
    if (enabled) {
      grants.add(capability);
    } else {
      grants.remove(capability);
    }
    _cache[appId] = grants;
    _bump(appId);
    _cacheVersions[appId] = versionFor(appId);
    await store.updateHostData(appId, 'grants.json', (map) {
      final current = map['granted'] is List
          ? (map['granted'] as List).whereType<String>().toSet()
          : <String>{};
      if (enabled) {
        current.add(capability);
      } else {
        current.remove(capability);
      }
      map['granted'] = current.intersection(declared(_require(appId))).toList()
        ..sort();
    });
    _cacheVersions.remove(appId);
  }

  void _reconcile() {
    if (_disposed) {
      return;
    }
    final apps = {for (final app in store.apps) app.id: app};
    for (final id in _declared.keys.toList()) {
      final app = apps[id];
      if (app == null) {
        _declared.remove(id);
        _cache.remove(id);
        _cacheVersions.remove(id);
        _loading.remove(id);
        _bump(id);
        continue;
      }
      final current = declared(app);
      final removed = _declared[id]!.difference(current);
      _declared[id] = current;
      if (removed.isEmpty) {
        continue;
      }
      _cache[id]?.removeAll(removed);
      _bump(id);
      if (_cache.containsKey(id)) {
        _cacheVersions[id] = versionFor(id);
      }
      // Enqueue this before a subsequent explicit grant so a rollback cannot
      // resurrect a capability dropped by an intermediate installed version.
      unawaited(
        store
            .updateHostData(id, 'grants.json', (map) {
              final raw = map['granted'];
              map['granted'] = raw is List
                  ? raw
                        .whereType<String>()
                        .where((v) => !removed.contains(v))
                        .toList()
                  : <String>[];
            })
            .catchError((Object _) {}),
      );
    }
    for (final app in apps.values) {
      _declared.putIfAbsent(app.id, () => declared(app));
    }
  }

  void _bump(String id) {
    store.invalidateGrants(id);
  }

  MiniApp _require(String id) {
    final app = store.byId(id);
    if (app == null) {
      throw MiniAppException('not_found', 'No mini app "$id".');
    }
    return app;
  }

  void dispose() {
    _disposed = true;
    store.removeListener(_reconcile);
    unawaited(_hostChanges.cancel());
    unawaited(_changes.close());
  }
}

import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../providers/settings_provider.dart';
import 'local_model_runtime.dart';

/// The fixed provider key/id for the built-in "Локальные модели · LiteRT"
/// provider. One `ProviderConfig` holds every installed/imported local
/// model, the same way any other provider holds its own model list.
const String kLocalModelProviderKey = 'litert-local';

/// One installed local model, derived from `ProviderConfig.models` /
/// `modelOverrides` for [kLocalModelProviderKey] -- there is no separate
/// database table; the provider config already persists via
/// [SettingsProvider] (included in backups) and is the single source of
/// truth.
class InstalledLocalModel {
  const InstalledLocalModel({
    required this.id,
    required this.displayName,
    required this.filePath,
    required this.sizeBytes,
    required this.backend,
    required this.sourceLabel,
    required this.installedAtMillis,
  });

  final String id;
  final String displayName;
  final String filePath;
  final int sizeBytes;

  /// "cpu" or "gpu" -- the backend this model was configured to try. The
  /// backend actually used for a given load can differ if GPU init fails
  /// and the engine falls back (see LiteRtEngineManager); this field is the
  /// user's preference, not a live status.
  final String backend;

  /// Human-readable origin: the imported file's own name, or (once the
  /// catalog exists) the catalog entry's name.
  final String sourceLabel;

  final int installedAtMillis;

  factory InstalledLocalModel.fromOverride(
    String id,
    Map<String, dynamic> override,
  ) {
    return InstalledLocalModel(
      id: id,
      displayName: (override['name'] ?? id).toString(),
      filePath: (override['localModelPath'] ?? '').toString(),
      sizeBytes: (override['localSizeBytes'] as num?)?.toInt() ?? 0,
      backend: (override['localBackend'] ?? 'cpu').toString(),
      sourceLabel: (override['localSourceLabel'] ?? '').toString(),
      installedAtMillis: (override['localInstalledAtMillis'] as num?)
              ?.toInt() ??
          0,
    );
  }
}

/// Thrown when an operation can't safely proceed. [code] is stable (not
/// user-facing text); the UI maps it to a localized message.
class LocalModelLibraryException implements Exception {
  const LocalModelLibraryException(this.code);
  final String code;
}

/// Reads/mutates [kLocalModelProviderKey]'s `ProviderConfig` on behalf of
/// the model-management UI and the import flow. Deliberately thin: all the
/// actual file I/O lives in `local_model_import.dart`, all the actual
/// engine lifecycle lives in `LocalModelRuntime` -- this class only keeps
/// the provider config (the list of installed models Moru's existing
/// model picker already reads) in sync with what's really on disk.
class LocalModelLibrary {
  const LocalModelLibrary();

  List<InstalledLocalModel> installedModels(SettingsProvider settings) {
    final cfg = settings.providerConfigs[kLocalModelProviderKey];
    if (cfg == null) return const [];
    return [
      for (final id in cfg.models)
        InstalledLocalModel.fromOverride(
          id,
          (cfg.modelOverrides[id] as Map?)?.cast<String, dynamic>() ?? {},
        ),
    ];
  }

  /// Registers a just-imported (or, later, just-downloaded) model file as
  /// an installed model, creating [kLocalModelProviderKey]'s provider
  /// config on first use. Does not touch the file itself -- call after
  /// `importLocalModelFile`/the catalog downloader has already produced a
  /// finished, verified file at [filePath].
  Future<InstalledLocalModel> registerInstalledModel(
    SettingsProvider settings, {
    required String filePath,
    required int sizeBytes,
    required String displayName,
    required String sourceLabel,
    String backend = 'cpu',
  }) async {
    final existing = settings.providerConfigs[kLocalModelProviderKey];
    final cfg =
        existing ??
        ProviderConfig(
          id: kLocalModelProviderKey,
          enabled: true,
          // Left empty on purpose: the providers list falls back to its own
          // localized name (l10n.localModelsProviderName) whenever cfg.name
          // is empty, so this stays correct across locales instead of
          // freezing the display name in one language at first-import time.
          name: '',
          apiKey: '',
          baseUrl: '',
          providerType: ProviderKind.local,
          models: const [],
          modelOverrides: const {},
        );

    final modelId = const Uuid().v4();
    final nextModels = [...cfg.models, modelId];
    final nextOverrides = Map<String, dynamic>.from(cfg.modelOverrides);
    nextOverrides[modelId] = {
      'name': displayName,
      'type': 'chat',
      'input': ['text'],
      'output': ['text'],
      'abilities': <String>[],
      'localModelPath': filePath,
      'localBackend': backend,
      'localSizeBytes': sizeBytes,
      'localSourceLabel': sourceLabel,
      'localInstalledAtMillis': DateTime.now().millisecondsSinceEpoch,
    };

    final updated = cfg.copyWith(
      enabled: true,
      models: nextModels,
      modelOverrides: nextOverrides,
    );
    await settings.setProviderConfig(kLocalModelProviderKey, updated);
    return InstalledLocalModel.fromOverride(
      modelId,
      nextOverrides[modelId] as Map<String, dynamic>,
    );
  }

  /// Removes [modelId] from the provider config (and every place that had
  /// it selected, via [SettingsProvider.deleteModels]) and deletes its
  /// weight file. Refuses (throws [LocalModelLibraryException] with code
  /// `model_in_use`) while that exact file is the one currently loaded in
  /// [LocalModelRuntime] -- the caller must unload it first. Never deletes
  /// a file that isn't actually this model's own private copy.
  Future<void> deleteModel(
    SettingsProvider settings,
    String modelId, {
    bool Function(String filePath)? isPathInUse,
  }) async {
    final cfg = settings.providerConfigs[kLocalModelProviderKey];
    final override = (cfg?.modelOverrides[modelId] as Map?)
        ?.cast<String, dynamic>();
    if (cfg == null || override == null) return;
    final filePath = (override['localModelPath'] ?? '').toString();

    final inUse =
        isPathInUse ??
        (path) => LocalModelRuntime.instance.loadedModelPath == path;
    if (filePath.isNotEmpty && inUse(filePath)) {
      throw const LocalModelLibraryException('model_in_use');
    }

    await settings.deleteModels(kLocalModelProviderKey, {modelId});

    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

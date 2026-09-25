import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../utils/app_directories.dart';

/// Limits, capabilities and prices of one model from models.dev.
/// Prices are US dollars per million tokens.
@immutable
class ModelCatalogEntry {
  const ModelCatalogEntry({
    this.contextTokens,
    this.outputTokens,
    this.inputPrice,
    this.outputPrice,
    this.cacheReadPrice,
    this.reasoning = false,
    this.toolCall = false,
    this.imageInput = false,
  });

  final int? contextTokens;
  final int? outputTokens;
  final double? inputPrice;
  final double? outputPrice;
  final double? cacheReadPrice;
  final bool reasoning;
  final bool toolCall;
  final bool imageInput;

  bool get hasPrice => inputPrice != null && outputPrice != null;

  /// Dollar cost of [input] prompt tokens ([cached] of them read from cache)
  /// and [output] completion tokens, or null without a price.
  double? cost({required int input, required int output, int cached = 0}) {
    if (!hasPrice) return null;
    final fromCache = cached.clamp(0, input);
    final cacheRate = cacheReadPrice ?? inputPrice!;
    return ((input - fromCache) * inputPrice! +
            fromCache * cacheRate +
            output * outputPrice!) /
        1000000;
  }

  factory ModelCatalogEntry.fromJson(Map<String, dynamic> json) =>
      ModelCatalogEntry(
        contextTokens: (json['c'] as num?)?.toInt(),
        outputTokens: (json['o'] as num?)?.toInt(),
        inputPrice: (json['pi'] as num?)?.toDouble(),
        outputPrice: (json['po'] as num?)?.toDouble(),
        cacheReadPrice: (json['pc'] as num?)?.toDouble(),
        reasoning: json['r'] == true,
        toolCall: json['t'] == true,
        imageInput: json['i'] == true,
      );

  Map<String, dynamic> toJson() => {
    if (contextTokens != null) 'c': contextTokens,
    if (outputTokens != null) 'o': outputTokens,
    if (inputPrice != null) 'pi': inputPrice,
    if (outputPrice != null) 'po': outputPrice,
    if (cacheReadPrice != null) 'pc': cacheReadPrice,
    if (reasoning) 'r': true,
    if (toolCall) 't': true,
    if (imageInput) 'i': true,
  };
}

/// The models.dev catalog, reduced to one entry per model id and kept in the
/// app's cache directory. Refreshed at most once a day; a failed download
/// keeps the previous copy.
class ModelCatalog extends ChangeNotifier {
  ModelCatalog({
    this._client,
    Future<File> Function()? cacheFile,
    DateTime Function()? now,
  }) : _cacheFile = cacheFile ?? _defaultCacheFile,
       _now = now ?? DateTime.now;

  static final ModelCatalog instance = ModelCatalog();

  static final Uri sourceUri = Uri.parse('https://models.dev/api.json');
  static const Duration maxAge = Duration(days: 1);

  /// Vendors whose own listing wins when resellers list the same id.
  static const List<String> firstPartyProviders = [
    'anthropic',
    'openai',
    'google',
    'deepseek',
    'xai',
    'mistral',
    'moonshotai',
    'zai',
    'alibaba',
    'minimax',
  ];

  final http.Client? _client;
  final Future<File> Function() _cacheFile;
  final DateTime Function() _now;

  Map<String, ModelCatalogEntry> _entries = const {};
  DateTime? _updatedAt;
  Future<void>? _starting;

  DateTime? get updatedAt => _updatedAt;
  int get length => _entries.length;

  static Future<File> _defaultCacheFile() async {
    final dir = await AppDirectories.getCacheDirectory();
    return File('${dir.path}/models_dev_index_v1.json');
  }

  /// Loads the cached copy, then downloads a new one when it is stale.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await _loadCache();
    final updated = _updatedAt;
    if (updated == null || _now().difference(updated) >= maxAge) {
      await refresh();
    }
  }

  Future<void> _loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      _apply(
        DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
        (data['models'] as Map).map(
          (key, value) => MapEntry(
            key as String,
            ModelCatalogEntry.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ModelCatalog] cache unreadable: $e');
    }
  }

  /// Downloads models.dev and replaces the cached index. Errors keep the
  /// current copy.
  Future<bool> refresh() async {
    try {
      final client = _client ?? http.Client();
      final http.Response response;
      try {
        response = await client
            .get(sourceUri)
            .timeout(const Duration(seconds: 30));
      } finally {
        if (_client == null) client.close();
      }
      if (response.statusCode != 200) return false;
      final body = response.body;
      final index = await Isolate.run(
        () => buildIndex(jsonDecode(body) as Map<String, dynamic>),
      );
      if (index.isEmpty) return false;
      final updatedAt = _now();
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'updatedAt': updatedAt.millisecondsSinceEpoch,
          'models': {
            for (final entry in index.entries) entry.key: entry.value.toJson(),
          },
        }),
      );
      _apply(updatedAt, index);
      return true;
    } catch (e) {
      debugPrint('[ModelCatalog] refresh failed: $e');
      return false;
    }
  }

  void _apply(DateTime updatedAt, Map<String, ModelCatalogEntry> entries) {
    _updatedAt = updatedAt;
    _entries = entries;
    notifyListeners();
  }

  /// The entry for an upstream model id such as `claude-sonnet-4-5`,
  /// `openai/gpt-4o` or `deepseek-chat:free`, or null when unknown.
  ModelCatalogEntry? lookup(String modelId) {
    if (_entries.isEmpty) return null;
    final key = normalizeId(modelId);
    return _entries[key] ??
        _entries[key.replaceFirst(RegExp(r'-(\d{8}|\d{4}-\d{2}-\d{2})$'), '')];
  }

  @visibleForTesting
  void debugSetEntries(Map<String, ModelCatalogEntry> entries) =>
      _apply(_now(), entries);

  /// Lowercase id without a vendor prefix or a `:variant` suffix.
  static String normalizeId(String modelId) {
    var id = modelId.trim().toLowerCase();
    final slash = id.lastIndexOf('/');
    if (slash >= 0) id = id.substring(slash + 1);
    final colon = id.indexOf(':');
    if (colon > 0) id = id.substring(0, colon);
    return id;
  }

  /// One entry per normalized id from the raw models.dev payload. First-party
  /// listings win; otherwise the first provider listing the id is kept.
  static Map<String, ModelCatalogEntry> buildIndex(Map<String, dynamic> raw) {
    final providers = [
      for (final id in firstPartyProviders)
        if (raw[id] is Map) raw[id] as Map,
      for (final entry in raw.entries)
        if (!firstPartyProviders.contains(entry.key) && entry.value is Map)
          entry.value as Map,
    ];
    final index = <String, ModelCatalogEntry>{};
    for (final provider in providers) {
      final models = provider['models'];
      if (models is! Map) continue;
      for (final entry in models.entries) {
        final model = entry.value;
        if (model is! Map) continue;
        final key = normalizeId('${model['id'] ?? entry.key}');
        if (key.isEmpty || index.containsKey(key)) continue;
        final limit = model['limit'] is Map ? model['limit'] as Map : const {};
        final cost = model['cost'] is Map ? model['cost'] as Map : const {};
        final modalities = model['modalities'] is Map
            ? model['modalities'] as Map
            : const {};
        final input = modalities['input'];
        int? positive(Object? value) =>
            value is num && value > 0 ? value.toInt() : null;
        double? price(Object? value) =>
            value is num && value >= 0 ? value.toDouble() : null;
        index[key] = ModelCatalogEntry(
          contextTokens: positive(limit['context']),
          outputTokens: positive(limit['output']),
          inputPrice: price(cost['input']),
          outputPrice: price(cost['output']),
          cacheReadPrice: price(cost['cache_read']),
          reasoning: model['reasoning'] == true,
          toolCall: model['tool_call'] == true,
          imageInput: input is List && input.contains('image'),
        );
      }
    }
    return index;
  }
}

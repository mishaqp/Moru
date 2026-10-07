import 'dart:convert';

import 'package:flutter/services.dart';

/// Browser-ready libraries packaged with Moru; no runtime CDN downloads.
class MiniAppAssets {
  MiniAppAssets({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  static const root = 'assets/mini_apps/runtime/';
  static const catalog = <String, Map<String, Object>>{
    'galacean': {'file': 'galacean-engine-1.6.13.min.js', 'version': '1.6.13'},
    'galacean-ui': {
      'file': 'galacean-engine-ui-1.6.13.min.js',
      'version': '1.6.13',
      'dependencies': <String>['galacean'],
    },
    'galacean-basis-js': {
      'file': 'basis-transcoder-1.60.js',
      'version': '1.60',
    },
    'galacean-basis-wasm': {
      'file': 'basis-transcoder-1.60.wasm',
      'version': '1.60',
    },
    'phaser': {'file': 'phaser-3.90.0.min.js', 'version': '3.90.0'},
    'chartjs': {'file': 'chart-4.5.1.umd.js', 'version': '4.5.1'},
    'sqljs': {'file': 'sql-wasm-1.14.2.js', 'version': '1.14.2'},
    'sqljs-wasm': {'file': 'sql-wasm-1.14.2.wasm', 'version': '1.14.2'},
    'ui': {'file': 'moru-ui-1.0.0.css', 'version': '1.0.0'},
  };

  static final bootstrapScript =
      'window.__moruAssetCatalog = ${jsonEncode(catalog)};';

  /// Exact lookup also rejects directories, encoded paths and query strings.
  Future<ByteData?> load(String filename) async {
    if (!catalog.values.any((entry) => entry['file'] == filename)) return null;
    return _bundle.load('$root$filename');
  }
}

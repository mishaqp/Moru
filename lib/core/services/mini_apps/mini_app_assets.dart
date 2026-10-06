import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One read-only copy in the APK, never copied into an app or its versions.
/// Versions, archive integrity, source URLs and notices live beside the files.
class MiniAppAssets {
  MiniAppAssets({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final shared = MiniAppAssets();
  static const assetDirectory = 'assets/mini_apps/runtime';
  static const libraryFiles = <String, String>{
    'galacean': 'galacean-engine-1.6.13.min.js',
    'galacean-ui': 'galacean-engine-ui-1.6.13.min.js',
    'galacean-physics-lite': 'galacean-engine-physics-lite-1.6.13.min.js',
    'phaser': 'phaser-3.90.0.min.js',
    'chart': 'chart-4.5.1.umd.js',
    'sqljs': 'sql-wasm-1.14.2.js',
    'sqljs-wasm': 'sql-wasm-1.14.2.wasm',
    'ui': 'moru-ui.css',
  };

  final AssetBundle _bundle;
  final _cache = <String, Future<ByteData>>{};

  /// Unknown names cannot turn into arbitrary AssetBundle paths.
  Future<ByteData?> read(String file) async {
    if (!libraryFiles.containsValue(file) &&
        file != 'LICENSES.txt' && file != 'third-party.json') {
      return null;
    }
    return _cache.putIfAbsent(file, () => _bundle.load('$assetDirectory/$file'));
  }

  static String get configuration =>
      'window.__moruLibraryFiles = ${jsonEncode(libraryFiles)};';
}

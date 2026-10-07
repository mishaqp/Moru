import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mini_apps/mini_app_assets.dart';

class _MemoryBundle extends CachingAssetBundle {
  final requested = <String>[];
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog pins compatible local browser runtimes', () {
    expect(MiniAppAssets.root, 'assets/mini_apps/runtime/');
    expect(
      MiniAppAssets.catalog.keys,
      unorderedEquals([
        'galacean',
        'galacean-ui',
        'galacean-basis-js',
        'galacean-basis-wasm',
        'phaser',
        'chartjs',
        'sqljs',
        'sqljs-wasm',
        'ui',
      ]),
    );
    expect(MiniAppAssets.catalog['galacean']?['version'], '1.6.13');
    expect(MiniAppAssets.catalog['galacean-ui']?['version'], '1.6.13');
    expect(MiniAppAssets.catalog['galacean-ui']?['dependencies'], ['galacean']);
    expect(MiniAppAssets.catalog['phaser']?['version'], '3.90.0');
    expect(MiniAppAssets.catalog['chartjs']?['version'], '4.5.1');
    expect(MiniAppAssets.catalog['sqljs']?['version'], '1.14.2');
    expect(MiniAppAssets.catalog['sqljs-wasm']?['version'], '1.14.2');
    for (final entry in MiniAppAssets.catalog.values) {
      expect(entry['file'], matches(r'^[a-zA-Z0-9_.-]+\.(js|css|wasm)$'));
      for (final dependency in entry['dependencies'] as List<String>? ?? []) {
        expect(MiniAppAssets.catalog, contains(dependency));
      }
    }
  });

  test('loads only exact catalog filenames through the asset bundle', () async {
    final bundle = _MemoryBundle();
    final assets = MiniAppAssets(bundle: bundle);
    for (final entry in MiniAppAssets.catalog.values) {
      final filename = entry['file'] as String;
      final data = await assets.load(filename);
      expect(data?.buffer.asUint8List(), [1, 2, 3, 4]);
      expect(bundle.requested.last, '${MiniAppAssets.root}$filename');
    }
    expect(bundle.requested.length, 9);
    bundle.requested.clear();
    for (final filename in [
      '',
      'missing.js',
      'galacean',
      'vendor-manifest.json',
      '../phaser-3.90.0.min.js',
      '/phaser-3.90.0.min.js',
      r'..\phaser-3.90.0.min.js',
      'phaser-3.90.0.min.js/extra',
      'phaser-3.90.0.min.js?download',
      'phaser-3.90.0.min.js#fragment',
      '%70haser-3.90.0.min.js',
      'phaser-3.90.0.min.js\u0000',
      '${MiniAppAssets.root}phaser-3.90.0.min.js',
    ]) {
      expect(await assets.load(filename), isNull, reason: filename);
    }
    expect(bundle.requested, isEmpty);
  });

  test('bootstrap exposes the same JSON catalog without a network address', () {
    const prefix = 'window.__moruAssetCatalog = ';
    expect(MiniAppAssets.bootstrapScript, startsWith(prefix));
    expect(MiniAppAssets.bootstrapScript, endsWith(';'));
    expect(
      jsonDecode(
        MiniAppAssets.bootstrapScript.substring(
          prefix.length,
          MiniAppAssets.bootstrapScript.length - 1,
        ),
      ),
      MiniAppAssets.catalog,
    );
    expect(MiniAppAssets.bootstrapScript, isNot(contains('https://')));
  });

  test('real Flutter package includes runtime bytes and WASM header', () async {
    final assets = MiniAppAssets();
    for (final entry in MiniAppAssets.catalog.values) {
      final filename = entry['file'] as String;
      final data = await assets.load(filename);
      expect(data, isNotNull, reason: filename);
      expect(data!.lengthInBytes, greaterThan(1024), reason: filename);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (filename.endsWith('.wasm')) {
        expect(bytes.take(8), [0, 97, 115, 109, 1, 0, 0, 0]);
      } else {
        expect(utf8.decode(bytes), isNotEmpty);
      }
    }
  });

  test(
    'bundled files match reproducible checksums, notices and size budget',
    () async {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  '${MiniAppAssets.root}vendor-manifest.json',
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['format'], 1);
      final files = manifest['files'] as Map<String, dynamic>;
      final directoryFiles = Directory(MiniAppAssets.root)
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name != 'vendor-manifest.json');
      expect(files.keys, unorderedEquals(directoryFiles));
      var rawBytes = (await rootBundle.load(
        '${MiniAppAssets.root}vendor-manifest.json',
      )).lengthInBytes;
      for (final entry in files.entries) {
        final metadata = entry.value as Map<String, dynamic>;
        final data = await rootBundle.load('${MiniAppAssets.root}${entry.key}');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        expect(bytes.length, metadata['bytes'], reason: entry.key);
        expect(
          sha256.convert(bytes).toString(),
          metadata['sha256'],
          reason: entry.key,
        );
        rawBytes += bytes.length;
      }
      for (final entry in MiniAppAssets.catalog.values) {
        expect(files, contains(entry['file']));
      }
      final packages = manifest['packages'] as List<dynamic>;
      expect(packages.length, 5);
      for (final package in packages.cast<Map<String, dynamic>>()) {
        expect(package['license'], 'MIT');
        expect(package['tarball'], startsWith('https://registry.npmjs.org/'));
        expect(package['integrity'], startsWith('sha512-'));
        expect(package['sha256'], matches(r'^[a-f0-9]{64}$'));
        final licenseFile = package['licenseFile'] as String;
        expect(files, contains(licenseFile));
        expect(
          await rootBundle.loadString('${MiniAppAssets.root}$licenseFile'),
          contains('Permission is hereby granted'),
        );
      }
      final notices = await rootBundle.loadString(
        '${MiniAppAssets.root}THIRD-PARTY-NOTICES.txt',
      );
      expect(notices, contains('SQLite'));
      expect(notices, contains('public domain'));
      expect(notices, contains('gl-matrix'));
      expect(notices, contains('Apache License'));
      expect(files, contains('LICENSE-basis-universal.txt'));
      expect(rawBytes, lessThan(8 * 1024 * 1024));
    },
  );

  test(
    'optional engine codecs stay local and Phaser excludes the legacy polyfill',
    () async {
      final engine = await rootBundle.loadString(
        '${MiniAppAssets.root}${MiniAppAssets.catalog['galacean']!['file']}',
      );
      expect(engine, contains('window.moru.assets.url("galacean-basis-js")'));
      expect(engine, contains('window.moru.assets.url("galacean-basis-wasm")'));
      expect(engine, isNot(contains('fetch("https://mdn.alipayobjects.com/')));
      final phaser = await rootBundle.loadString(
        '${MiniAppAssets.root}${MiniAppAssets.catalog['phaser']!['file']}',
      );
      expect(phaser, isNot(contains('_rvfcpolyfillmap')));
    },
  );

  test(
    'Moru CSS offers scoped accessible controls and synchronized tokens',
    () async {
      final filename = MiniAppAssets.catalog['ui']!['file'] as String;
      final css = await rootBundle.loadString('${MiniAppAssets.root}$filename');
      for (final token in [
        '--moru-bg',
        '--moru-surface',
        '--moru-text',
        '--moru-muted',
        '--moru-accent',
        '--moru-on-accent',
        '--moru-border',
        '.moru-app',
        '.moru-button',
        '.moru-card',
        '.moru-list',
        '.moru-field',
        '.moru-tabs',
        ':focus-visible',
        ':disabled',
        'prefers-reduced-motion',
        'data-moru-theme',
        'max(env(safe-area-inset-top, 0px), var(--moru-safe-top, 0px))',
      ]) {
        expect(css, contains(token), reason: token);
      }
      expect(css, contains('min-height: 44px'));
      expect(css, contains('#4d5c92'));
    },
  );
}

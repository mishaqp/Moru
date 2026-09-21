import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/local/local_model_library.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late Directory tempDir;
  const library = LocalModelLibrary();

  setUp(() async {
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    tempDir = await Directory.systemTemp.createTemp('litert_library_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> writeFakeModelFile(String name) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes([1, 2, 3, 4]);
    return file.path;
  }

  test(
    'registering a model creates the provider config on first use',
    () async {
      expect(settings.providerConfigs[kLocalModelProviderKey], isNull);

      final path = await writeFakeModelFile('a.litertlm');
      final installed = await library.registerInstalledModel(
        settings,
        filePath: path,
        sizeBytes: 4,
        displayName: 'Test Model',
        sourceLabel: 'a.litertlm',
      );

      final cfg = settings.providerConfigs[kLocalModelProviderKey];
      expect(cfg, isNotNull);
      expect(cfg!.providerType, ProviderKind.local);
      expect(cfg.enabled, isTrue);
      expect(cfg.models, [installed.id]);

      final list = library.installedModels(settings);
      expect(list, hasLength(1));
      expect(list.single.displayName, 'Test Model');
      expect(list.single.filePath, path);
      expect(list.single.sizeBytes, 4);
    },
  );

  test('registering a second model appends to the existing config', () async {
    await library.registerInstalledModel(
      settings,
      filePath: await writeFakeModelFile('a.litertlm'),
      sizeBytes: 4,
      displayName: 'A',
      sourceLabel: 'a.litertlm',
    );
    await library.registerInstalledModel(
      settings,
      filePath: await writeFakeModelFile('b.litertlm'),
      sizeBytes: 8,
      displayName: 'B',
      sourceLabel: 'b.litertlm',
    );

    final list = library.installedModels(settings);
    expect(list.map((m) => m.displayName).toSet(), {'A', 'B'});
  });

  test('reimporting identical weights preserves the model id', () async {
    final firstPath = await writeFakeModelFile('first.litertlm');
    final first = await library.registerInstalledModel(
      settings,
      filePath: firstPath,
      sizeBytes: 4,
      displayName: 'Qwen',
      sourceLabel: 'first.litertlm',
    );
    final secondPath = await writeFakeModelFile('second.litertlm');
    final second = await library.registerInstalledModel(
      settings,
      filePath: secondPath,
      sizeBytes: 4,
      displayName: 'Qwen reimported',
      sourceLabel: 'second.litertlm',
    );

    expect(second.id, first.id);
    expect(library.installedModels(settings), hasLength(1));
    expect(library.installedModels(settings).single.filePath, secondPath);
  });

  test('new model ids are stable for identical content', () async {
    final first = await library.registerInstalledModel(
      settings,
      filePath: await writeFakeModelFile('a.litertlm'),
      sizeBytes: 4,
      displayName: 'A',
      sourceLabel: 'a.litertlm',
    );

    expect(first.id, startsWith('litert-'));
    expect(first.id, hasLength(71));
  });

  test(
    'deleting a model removes it from the config and deletes its file',
    () async {
      final path = await writeFakeModelFile('a.litertlm');
      final installed = await library.registerInstalledModel(
        settings,
        filePath: path,
        sizeBytes: 4,
        displayName: 'A',
        sourceLabel: 'a.litertlm',
      );
      expect(File(path).existsSync(), isTrue);

      await library.deleteModel(settings, installed.id);

      expect(library.installedModels(settings), isEmpty);
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('deleting a model whose file path is reported in-use is refused, and '
      'the file survives', () async {
    final path = await writeFakeModelFile('a.litertlm');
    final installed = await library.registerInstalledModel(
      settings,
      filePath: path,
      sizeBytes: 4,
      displayName: 'A',
      sourceLabel: 'a.litertlm',
    );

    await expectLater(
      library.deleteModel(
        settings,
        installed.id,
        isPathInUse: (p) => p == path,
      ),
      throwsA(
        isA<LocalModelLibraryException>().having(
          (e) => e.code,
          'code',
          'model_in_use',
        ),
      ),
    );

    expect(File(path).existsSync(), isTrue);
    expect(library.installedModels(settings), hasLength(1));
  });

  test(
    'deleting a model whose file path is not in use proceeds normally',
    () async {
      final path = await writeFakeModelFile('a.litertlm');
      final installed = await library.registerInstalledModel(
        settings,
        filePath: path,
        sizeBytes: 4,
        displayName: 'A',
        sourceLabel: 'a.litertlm',
      );

      await library.deleteModel(
        settings,
        installed.id,
        isPathInUse: (_) => false,
      );

      expect(File(path).existsSync(), isFalse);
      expect(library.installedModels(settings), isEmpty);
    },
  );

  test('deleting an unknown model id is a harmless no-op', () async {
    await library.deleteModel(settings, 'does-not-exist');
    expect(library.installedModels(settings), isEmpty);
  });
}

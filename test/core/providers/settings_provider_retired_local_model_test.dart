import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../support/business_test_harness.dart';

class _AppPathProvider extends PathProviderPlatform {
  _AppPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRoot;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    appRoot = await Directory.systemTemp.createTemp('moru_retired_model_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _AppPathProvider(appRoot.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await appRoot.delete(recursive: true);
  });

  test(
    'retires LiteRT settings and managed files without touching other data',
    () async {
      final modelCopies = Directory('${appRoot.path}/litert_models');
      final speechModels = Directory('${appRoot.path}/asr_models');
      final workspaces = Directory('${appRoot.path}/workspaces');
      await modelCopies.create();
      await speechModels.create();
      await workspaces.create();
      await File('${modelCopies.path}/model.litertlm').writeAsString('copy');
      await File('${speechModels.path}/speech.bin').writeAsString('speech');
      await File('${workspaces.path}/notes.txt').writeAsString('keep');
      final local = ProviderConfig(
        id: 'litert-local',
        enabled: true,
        name: 'Local Models',
        apiKey: '',
        baseUrl: '',
        providerType: ProviderKind.local,
        models: const ['old-model'],
      );
      final remote = ProviderConfig(
        id: 'OpenAI',
        enabled: true,
        name: 'OpenAI',
        apiKey: 'test-key',
        baseUrl: 'https://example.test',
        models: const ['gpt-test'],
      );
      final harness = await createBusinessTestHarness(
        initial: {
          'provider_configs_v1': jsonEncode({
            'litert-local': local.toJson(),
            'OpenAI': remote.toJson(),
          }),
          'providers_order_v1': ['litert-local', 'OpenAI'],
          'pinned_models_v1': ['litert-local::old-model', 'OpenAI::gpt-test'],
          'selected_model_v1': 'litert-local::old-model',
          'title_model_v1': 'litert-local::old-model',
        },
      );

      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;

      // The stale-copy cleanup runs in the background so a slow or
      // unmocked path provider can never stall settings load; poll for it.
      for (
        var attempt = 0;
        await modelCopies.exists() && attempt < 100;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await modelCopies.exists(), isFalse);
      expect(await File('${speechModels.path}/speech.bin').exists(), isTrue);
      expect(await File('${workspaces.path}/notes.txt').exists(), isTrue);
      expect(settings.providerConfigs, isNot(contains('litert-local')));
      expect(settings.providerConfigs['OpenAI']?.models, ['gpt-test']);
      expect(settings.providersOrder, isNot(contains('litert-local')));
      expect(settings.pinnedModels, {'OpenAI::gpt-test'});
      expect(settings.currentModelProvider, isNull);
      expect(settings.titleModelProvider, isNull);
      expect(
        jsonDecode(harness.preferences.getString('provider_configs_v1')!),
        isNot(contains('litert-local')),
      );

      final restarted = SettingsProvider(harness.preferences);
      await restarted.loaded;
      expect(restarted.providerConfigs, isNot(contains('litert-local')));
      expect(restarted.providerConfigs['OpenAI']?.models, ['gpt-test']);
    },
  );

  test('cannot configure a retired on-device provider again', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    final config = ProviderConfig(
      id: 'legacy-copy',
      enabled: true,
      name: 'Old model',
      apiKey: '',
      baseUrl: '',
      providerType: ProviderKind.local,
    );

    await expectLater(
      settings.setProviderConfig('legacy-copy', config),
      throwsStateError,
    );
    expect(settings.providerConfigs, isNot(contains('legacy-copy')));
  });
}

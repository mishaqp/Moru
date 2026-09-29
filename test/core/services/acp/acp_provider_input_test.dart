import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_provider_input.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsProvider settings;

  setUp(() async {
    final harness = await createBusinessTestHarness();
    settings = SettingsProvider(harness.preferences);
    await settings.loaded;
  });

  tearDown(() => settings.dispose());

  test('image input enabled in model settings reaches OpenCode', () async {
    await settings.setProviderConfig(
      'custom',
      ProviderConfig(
        id: 'custom',
        enabled: true,
        name: 'Custom',
        apiKey: 'key',
        baseUrl: 'https://api.example.com/v1',
        providerType: ProviderKind.openai,
        modelOverrides: const {
          'local-model': {
            'apiModelId': 'upstream-model',
            'input': ['text', 'image'],
          },
        },
      ),
    );
    final input = acpProviderInputFor(settings, 'custom', 'local-model')!;
    expect(input.model, 'upstream-model');
    expect(input.imageInput, isTrue);
    final config = jsonDecode(AcpAgentSpec.openCodeConfig(input)) as Map;
    expect(config['provider']['moru']['models'], {
      'upstream-model': {
        'name': 'upstream-model',
        'attachment': true,
        'modalities': {
          'input': ['text', 'image'],
          'output': ['text'],
        },
      },
    });
  });

  test(
    'image input disabled in model settings overrides an inferred vision model',
    () async {
      await settings.setProviderConfig(
        'custom',
        ProviderConfig(
          id: 'custom',
          enabled: true,
          name: 'Custom',
          apiKey: 'key',
          baseUrl: 'https://api.example.com/v1',
          providerType: ProviderKind.openai,
          modelOverrides: const {
            'local-model': {
              'apiModelId': 'gpt-4o',
              'input': ['text'],
            },
          },
        ),
      );
      final input = acpProviderInputFor(settings, 'custom', 'local-model')!;
      expect(input.model, 'gpt-4o');
      expect(input.imageInput, isFalse);
    },
  );

  test('a model without overrides keeps inferred image input', () async {
    await settings.setProviderConfig(
      'custom',
      ProviderConfig(
        id: 'custom',
        enabled: true,
        name: 'Custom',
        apiKey: 'key',
        baseUrl: 'https://api.example.com/v1',
        providerType: ProviderKind.openai,
      ),
    );
    expect(
      acpProviderInputFor(settings, 'custom', 'gpt-4o')!.imageInput,
      isTrue,
    );
    expect(
      acpProviderInputFor(settings, 'custom', 'unknown-model')!.imageInput,
      isFalse,
    );
  });
}

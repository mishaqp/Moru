import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/mini_apps/mini_app_launcher.dart';

import '../../support/business_test_harness.dart';

void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsProvider(createBusinessTestPreferences());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  const withModel = Assistant(
    id: 'a',
    name: 'A',
    chatModelProvider: 'AssistantProvider',
    chatModelId: 'assistant-model',
  );
  const withoutModel = Assistant(id: 'b', name: 'B');

  test('the assistant model works without a default model', () {
    expect(settings.currentModelProvider, isNull);
    expect(MiniAppLauncher.askModelFor(settings, withModel), (
      provider: 'AssistantProvider',
      model: 'assistant-model',
    ));
  });

  test('the assistant model wins over the default model', () async {
    await settings.setCurrentModel('Default', 'default-model');
    expect(
      MiniAppLauncher.askModelFor(settings, withModel)?.model,
      'assistant-model',
    );
  });

  test('without an assistant model the default model is used', () async {
    await settings.setCurrentModel('Default', 'default-model');
    expect(MiniAppLauncher.askModelFor(settings, withoutModel), (
      provider: 'Default',
      model: 'default-model',
    ));
    expect(MiniAppLauncher.askModelFor(settings, null)?.model, 'default-model');
  });

  test('no model anywhere gives null', () {
    expect(MiniAppLauncher.askModelFor(settings, withoutModel), isNull);
  });
}

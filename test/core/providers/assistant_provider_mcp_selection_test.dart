import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initial asset path recovery does not await later MCP binding',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'assistants_v1': jsonEncode([
            {
              'id': 'a',
              'name': 'A',
              'avatar': 'kelivo-file:///avatars/pic.png',
              'mcpServerIds': ['live', 'dead'],
            },
          ]),
        },
      );
      SandboxPathResolver.debugSetDirs(docsDir: '/android-docs');
      addTearDown(() => SandboxPathResolver.debugSetDirs());
      final preferences = BusinessPreferences(harness.repository);
      final provider = AssistantProvider(preferences: preferences);
      addTearDown(provider.dispose);
      final ready = Completer<void>();
      addTearDown(() {
        if (!ready.isCompleted) ready.complete();
      });
      provider.bindMcpServers(
        liveMcpServerIds: () => null,
        mcpServersLoaded: ready.future,
      );
      var loaded = false;
      provider.loaded.then((_) => loaded = true);
      await preferences.load();
      await preferences.flushPendingWrites();
      await Future<void>.delayed(Duration.zero);
      expect(loaded, isTrue);
      expect(provider.getById('a')!.avatar, '/android-docs/avatars/pic.png');
      expect(provider.getById('a')!.mcpServerIds, ['live', 'dead']);
    },
  );

  test('dead ids are ignored on reads and pruned on the next save', () async {
    final raw = jsonEncode([
      {
        'id': 'a',
        'name': 'A',
        'mcpServerIds': ['live', 'dead'],
      },
      {
        'id': 'b',
        'name': 'B',
        'mcpServerIds': ['dead', 'disabled'],
      },
    ]);
    final harness = await createBusinessTestHarness(
      initial: {'assistants_v1': raw, 'current_assistant_id_v1': 'a'},
    );
    final provider = AssistantProvider(preferences: harness.preferences);
    addTearDown(provider.dispose);
    await provider.loaded;
    var live = <String>{'live', 'disabled'};
    provider.bindMcpServers(liveMcpServerIds: () => live);

    expect(provider.assistants.map((a) => a.mcpServerIds), [
      ['live'],
      ['disabled'],
    ]);
    expect(provider.currentAssistant!.mcpServerIds, ['live']);
    expect(provider.getById('a')!.mcpServerIds, ['live']);
    expect(harness.preferences.getString('assistants_v1'), raw);

    await provider.updateAssistant(
      provider.getById('a')!.copyWith(name: 'New'),
    );
    final saved =
        jsonDecode(harness.preferences.getString('assistants_v1')!) as List;
    expect(saved.map((a) => a['mcpServerIds']), [
      ['live'],
      ['disabled'],
    ]);

    live = {'disabled'};
    expect(provider.getById('a')!.mcpServerIds, isEmpty);
  });

  test(
    'save waits for live ids before pruning an initially unavailable list',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'assistants_v1': jsonEncode([
            {
              'id': 'a',
              'name': 'A',
              'mcpServerIds': ['live', 'dead'],
            },
          ]),
        },
      );
      final provider = AssistantProvider(preferences: harness.preferences);
      addTearDown(provider.dispose);
      await provider.loaded;
      final ready = Completer<void>();
      Set<String>? live;
      provider.bindMcpServers(
        liveMcpServerIds: () => live,
        mcpServersLoaded: ready.future,
      );
      expect(provider.getById('a')!.mcpServerIds, ['live', 'dead']);
      var saved = false;
      final saving = provider
          .updateAssistant(provider.getById('a')!.copyWith(name: 'New'))
          .then((_) => saved = true);
      await Future<void>.delayed(Duration.zero);
      expect(saved, isFalse);
      live = {'live'};
      ready.complete();
      await saving;
      expect(provider.getById('a')!.mcpServerIds, ['live']);
    },
  );

  test('explicit removal cleans every assistant and survives reload', () async {
    final harness = await createBusinessTestHarness(
      initial: {
        'assistants_v1': jsonEncode([
          {
            'id': 'a',
            'name': 'A',
            'mcpServerIds': ['removed', 'kept'],
          },
          {
            'id': 'b',
            'name': 'B',
            'mcpServerIds': ['removed'],
          },
        ]),
      },
    );
    final provider = AssistantProvider(preferences: harness.preferences);
    addTearDown(provider.dispose);
    await provider.removeMcpServerId('removed');
    final reloaded = AssistantProvider(preferences: harness.preferences);
    addTearDown(reloaded.dispose);
    await reloaded.loaded;
    expect(reloaded.assistants.map((a) => a.mcpServerIds), [
      ['kept'],
      <String>[],
    ]);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/api/chat_api_helpers.dart';
import 'package:Kelivo/core/services/api/providers/openai/responses_api.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-guide-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
  });
  tearDown(() async {
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
      jsonDecode(await MiniAppDataTool(store: store).execute(args))
          as Map<String, dynamic>;

  test('guide is available before an app or its store exists', () async {
    final unavailable = MiniAppStore(
      root: () async => throw StateError('The guide must not open the store.'),
    );
    addTearDown(unavailable.dispose);
    final result =
        jsonDecode(
              await MiniAppDataTool(
                store: unavailable,
              ).execute({'action': 'guide'}),
            )
            as Map<String, dynamic>;
    expect(result['ok'], isTrue);
    expect(result['guide'], isA<Map>());
  });

  test('tool schema offers guide, topic and example to providers', () {
    final definition = MiniAppDataTool.definition;
    final parameters =
        definition['function']['parameters'] as Map<String, dynamic>;
    final properties = parameters['properties'] as Map<String, dynamic>;
    expect(properties['action']['enum'], contains('guide'));
    expect(properties['topic']['type'], 'string');
    expect(
      properties['example']['enum'],
      containsAll(['tracker', 'chart', 'phaser', 'galacean', 'sqlite']),
    );
    expect(MiniAppDataTool.requiresApproval({'action': 'guide'}), isFalse);

    final openAi = toResponsesToolsFormat([definition]);
    expect(
      openAi.single['parameters']['properties']['example'],
      properties['example'],
    );
    final gemini = cleanSchemaForGemini(parameters, stringEnumOnly: true);
    expect(gemini['properties']['action']['enum'], contains('guide'));
    expect(gemini['properties']['topic']['type'], 'string');
    expect(
      gemini['properties']['example']['enum'],
      properties['example']['enum'],
    );
  });

  test(
    'default guide documents every public bridge method and events',
    () async {
      final result = await run({'action': 'guide'});
      expect(result['ok'], isTrue);
      final guide = result['guide'] as Map;
      final names = (guide['api'] as List).map(
        (entry) => (entry as Map)['name'],
      );
      expect(names.toSet(), {
        'moru.storage.get',
        'moru.storage.set',
        'moru.storage.remove',
        'moru.storage.keys',
        'moru.ai.ask',
        'moru.notify',
        'moru.reminders.set',
        'moru.reminders.remove',
        'moru.reminders.list',
        'moru.jobs.set',
        'moru.jobs.remove',
        'moru.jobs.list',
        'moru.fetch',
        'moru.server.fetch',
        'moru.server.url',
        'moru.calendar.list',
        'moru.calendar.add',
        'moru.vibrate',
        'moru.haptic',
        'moru.app.info',
        'moru.app.close',
        'moru.assets.url',
        'moru.assets.load',
      });
      // A newly exposed native bridge method must be added to the reference.
      for (final call in RegExp(
        r"call\('([^']+)'",
      ).allMatches(MiniAppStore.moruBridgeScript)) {
        expect(names, contains('moru.${call[1]}'));
      }
      for (final method in guide['api'] as List) {
        expect((method as Map)['signature'], isNotEmpty);
        expect(method['returns'], isNotEmpty);
      }
      final serialized = jsonEncode(guide);
      expect(serialized, contains('moru:storage'));
      expect(serialized, contains('moru:theme'));
      expect(serialized, contains('moru.theme'));
      expect(serialized, contains('500'));
      expect(serialized, contains('20 MiB'));
      expect(serialized, contains("base: './'"));
      expect(serialized, contains('publish_mini_app'));
      expect(serialized, contains('app_id'));
      expect(serialized, contains('files'));
      expect(
        serialized.length,
        lessThan(18000),
        reason: 'Default guide should fit in a tool response.',
      );
    },
  );

  test(
    'guide lists exact packaged library versions and all examples',
    () async {
      final guide = (await run({'action': 'guide'}))['guide'] as Map;
      final libraries = {
        for (final library in guide['libraries'] as List)
          (library as Map)['name']: library['version'],
      };
      expect(libraries, containsPair('galacean', '1.6.13'));
      expect(libraries, containsPair('galacean-ui', '1.6.13'));
      expect(libraries, containsPair('phaser', '3.90.0'));
      expect(libraries, containsPair('chartjs', '4.5.1'));
      expect(libraries, containsPair('sqljs', '1.14.2'));
      expect(libraries, containsPair('sqljs-wasm', '1.14.2'));
      expect(libraries, contains('ui'));
      expect((guide['examples'] as List).map((e) => (e as Map)['id']), [
        'tracker',
        'chart',
        'phaser',
        'galacean',
        'sqlite',
      ]);
    },
  );

  test(
    'topic selection is concise and nullable arguments keep the default',
    () async {
      final result = await run({'action': 'guide', 'topic': 'storage'});
      expect(result['ok'], isTrue);
      expect(result['guide']['topic'], 'storage');
      expect(result['guide']['api'], hasLength(4));
      expect(jsonEncode(result), contains('moru:storage'));
      expect(
        (await run({
          'action': 'guide',
          'topic': null,
          'example': null,
        }))['guide']['api'],
        hasLength(23),
      );
    },
  );

  test(
    'unknown examples, topics and invalid types are rejected safely',
    () async {
      for (final args in [
        {'example': '../runtime/phaser.min.js'},
        {'example': 'missing'},
        {
          'example': ['tracker'],
        },
        {'topic': 'missing'},
        {'topic': 7},
      ]) {
        final result = await run({'action': 'guide', ...args});
        expect(result['ok'], isFalse, reason: '$args');
        expect(result['error'], startsWith('invalid_'), reason: '$args');
        expect(store.apps, isEmpty);
      }
    },
  );

  for (final name in ['tracker', 'chart', 'phaser', 'galacean', 'sqlite']) {
    test(
      'guide returns complete installable $name files without runtime copies',
      () async {
        final result = await run({'action': 'guide', 'example': name});
        expect(result['ok'], isTrue);
        expect(result['example'], name);
        final manifest = result['manifest'] as Map<String, dynamic>;
        final files = Map<String, String>.from(result['files'] as Map);
        expect(jsonDecode(files[MiniAppStore.manifestFile]!), manifest);
        expect(files, contains(manifest['entry']));
        expect(files, contains('main.js'));
        expect(files, isNot(contains('moru.js')));
        final source = Directory(p.join(temp.path, name))..createSync();
        for (final entry in files.entries) {
          expect(entry.key, isNot(contains('..')));
          expect(entry.key, isNot(contains('runtime/')));
          final file = File(p.join(source.path, entry.key));
          await file.parent.create(recursive: true);
          await file.writeAsString(entry.value);
        }
        final installed = (await store.install(source)).app;
        expect(installed.name, manifest['name']);
        expect(
          installed.network,
          isEmpty,
          reason: 'Examples must run offline.',
        );
        expect(
          await File(installed.entryPath).readAsString(),
          contains('moru.js'),
        );
        expect(
          await File(p.join(installed.codeDirectory, 'main.js')).readAsString(),
          files['main.js'],
        );
        await store.storageSet(installed.id, 'sentinel', {'keep': true});
        await store.install(source);
        expect(await store.storageGet(installed.id, 'sentinel'), {
          'keep': true,
        });
      },
    );
  }
}

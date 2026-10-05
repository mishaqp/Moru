import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late MiniAppStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-manifest-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Map<String, dynamic> action({String name = 'save'}) => {
    'name': name,
    'description': 'Save a value',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'value': {
          'anyOf': [
            {'type': 'integer', 'minimum': 1},
            {'type': 'null'},
          ],
        },
      },
      'required': ['value'],
      'additionalProperties': false,
      r'$defs': {
        'unused': {'type': 'string', 'maxLength': 20},
      },
    },
    'permissions': <String>[],
    'danger': 'write',
    'executor': {
      'kind': 'state',
      'patch': {
        'saved': {r'$arg': 'value'},
      },
    },
  };

  Future<MiniApp> install(Map<String, dynamic> extra, {Object? screen}) async {
    final src = await temp.createTemp('source-');
    await File(
      p.join(src.path, MiniAppStore.manifestFile),
    ).writeAsString(jsonEncode({'id': 'panel', 'name': 'Panel', ...extra}));
    await File(p.join(src.path, 'index.html')).writeAsString('<p>legacy</p>');
    await File(p.join(src.path, 'screen.json')).writeAsString(
      jsonEncode(
        screen ??
            {
              'version': 1,
              'components': [
                {
                  'type': 'card',
                  'title': {'en': 'Panel', 'ru': 'Панель'},
                  'children': [
                    {'type': 'value', 'label': 'Value', 'bind': 'data.saved'},
                    {
                      'type': 'button',
                      'label': 'Save',
                      'action': 'save',
                      'args': {'value': 2},
                    },
                  ],
                },
              ],
            },
      ),
    );
    return (await store.install(src)).app;
  }

  test(
    'version two native entry and original action schemas survive reload',
    () async {
      final original = action();
      final app = await install({
        'formatVersion': 2,
        'ui': {'engine': 'native'},
        'actions': [original],
      });
      expect(app.entry, 'screen.json');
      expect(app.toJson()['formatVersion'], 2);
      expect(app.toJson()['ui'], {'engine': 'native', 'entry': 'screen.json'});
      expect((app.toJson()['actions'] as List).single, original);
      final reopened = MiniAppStore(
        root: () async => Directory(p.join(temp.path, 'apps')),
      );
      await reopened.load();
      expect(reopened.byId('panel')!.toJson()['actions'], [original]);
    },
  );

  test('legacy format remains web and does not invent actions', () async {
    final app = await install({});
    expect(app.entry, 'index.html');
    expect(app.toJson()['actions'], isNull);
  });

  test(
    'action argument roots reject scalar types and accept object references and compositions',
    () async {
      for (final schema in [
        {'type': 'string'},
        {'type': 'array'},
        {'type': 'number'},
        {'type': 'null'},
        {
          'type': ['object', 'null'],
        },
        {
          'anyOf': [
            {'type': 'object'},
            {'type': 'integer'},
          ],
        },
        {
          r'$defs': {
            'scalar': {'type': 'boolean'},
          },
          r'$ref': '#/\$defs/scalar',
        },
      ]) {
        await expectLater(
          install({
            'formatVersion': 2,
            'actions': [
              {...action(), 'inputSchema': schema},
            ],
          }),
          throwsA(isA<MiniAppException>()),
        );
      }
      final schema = {
        r'$defs': {
          'object': {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
          },
        },
        'allOf': [
          {r'$ref': '#/\$defs/object'},
        ],
      };
      final app = await install({
        'formatVersion': 2,
        'actions': [
          {...action(), 'inputSchema': schema},
        ],
      });
      expect((app.toJson()['actions'] as List).single['inputSchema'], schema);
    },
  );

  test(
    'unsafe regex assertions are rejected and useful linear patterns survive unchanged',
    () async {
      Map<String, dynamic> patterned(String pattern) => {
        ...action(),
        'inputSchema': {
          'type': 'object',
          'properties': {
            'value': {'type': 'string', 'pattern': pattern},
          },
          'required': ['value'],
          'additionalProperties': false,
        },
      };
      for (final pattern in [
        '^(a+)+\$',
        '^a+a+\$',
        'a+!',
        '^(a|aa)+\$',
        r'^(a)\1$',
        '^a?a?a?\$',
      ]) {
        await expectLater(
          install({
            'formatVersion': 2,
            'actions': [patterned(pattern)],
          }),
          throwsA(isA<MiniAppException>()),
        );
      }
      for (final pattern in [
        r'^[A-Z][a-z0-9_]*$',
        r'^[0-9]{5}$',
        r'^literal$',
        r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
      ]) {
        final original = patterned(pattern);
        final app = await install({
          'formatVersion': 2,
          'actions': [original],
        });
        expect(
          (app.toJson()['actions'] as List).single['inputSchema'],
          original['inputSchema'],
        );
      }
    },
  );

  test(
    'version two web screens cannot inherit a shell server; legacy servers stay valid',
    () async {
      await expectLater(
        install({
          'formatVersion': 2,
          'server': {'command': 'python3 server.py'},
        }),
        throwsA(isA<MiniAppException>()),
      );
      expect(
        (await install({
          'server': {'command': 'python3 server.py'},
        })).serverCommand,
        'python3 server.py',
      );
    },
  );

  test(
    'native volume slider accepts state-bound minimum and maximum',
    () async {
      final app = await install(
        {
          'formatVersion': 2,
          'ui': {'engine': 'native'},
          'actions': [action()],
        },
        screen: {
          'version': 1,
          'components': [
            {
              'type': 'slider',
              'bind': 'device.audio.volumes.music.value',
              'minBind': 'device.audio.volumes.music.min',
              'maxBind': 'device.audio.volumes.music.max',
              'action': 'save',
              'args': {
                'value': {r'$value': true},
              },
            },
          ],
        },
      );
      expect(app.entry, 'screen.json');
    },
  );

  test(
    'rejects duplicate actions, unsafe executors and weakened native policy',
    () async {
      final variants = [
        [action(), action()],
        [
          {
            ...action(),
            'executor': {'kind': 'shell', 'command': 'su'},
          },
        ],
        [
          {...action(), 'danger': 'read'},
        ],
        [
          {
            ...action(),
            'executor': {'kind': 'native', 'handler': 'device.unknown.get'},
          },
        ],
        [
          {
            ...action(),
            'permissions': ['device.screen.write'],
            'danger': 'read',
            'executor': {
              'kind': 'native',
              'handler': 'device.screen.brightness.set',
            },
          },
        ],
        [
          {
            ...action(),
            'inputSchema': {
              'type': 'object',
              'properties': {
                'x': {r'$ref': 'https://evil/schema'},
              },
            },
          },
        ],
      ];
      for (final actions in variants) {
        await expectLater(
          install({'formatVersion': 2, 'actions': actions}),
          throwsA(isA<MiniAppException>()),
        );
      }
    },
  );

  test(
    'native screen refuses executable content, unknown action and server',
    () async {
      for (final screen in [
        {
          'version': 1,
          'components': [
            {'type': 'webview', 'html': '<script/>'},
          ],
        },
        {
          'version': 1,
          'components': [
            {'type': 'button', 'action': 'missing'},
          ],
        },
        {
          'version': 1,
          'components': [
            {'type': 'text', 'text': 'Hi', 'script': 'evil'},
          ],
        },
      ]) {
        await expectLater(
          install({
            'formatVersion': 2,
            'ui': {'engine': 'native'},
            'actions': [action()],
          }, screen: screen),
          throwsA(isA<MiniAppException>()),
        );
      }
      await expectLater(
        install({
          'formatVersion': 2,
          'ui': {'engine': 'native'},
          'server': {'command': 'node a.js'},
          'actions': [action()],
        }),
        throwsA(isA<MiniAppException>()),
      );
    },
  );
}

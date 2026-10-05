import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_manifest.dart';
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
    'state expression opt in is a source boolean with an exact validation path',
    () {
      for (final invalid in [1, 'true', null]) {
        final raw = action();
        raw['executor'] = {
          'kind': 'state',
          'expressions': invalid,
          'patch': {'count': 1},
        };
        expect(
          () => MiniAppManifest.parse({
            'formatVersion': 2,
            'actions': [raw],
          }),
          throwsA(
            isA<MiniAppException>().having(
              (e) => e.message,
              'path',
              contains('manifest.actions[0].executor.expressions'),
            ),
          ),
        );
      }
      final raw = action();
      raw['executor'] = {
        'kind': 'state',
        'expressions': true,
        'patch': {
          'count': {r'$inc': 1},
        },
      };
      final app = MiniAppManifest.parse({
        'formatVersion': 2,
        'actions': [raw],
      });
      expect(app.actions.single.toJson(), raw);
    },
  );

  test(
    'common manifest diagnostics include the exact source field and accepted example',
    () {
      final cases = <(Map<String, dynamic>, String)>[
        ({'formatVersion': 'two'}, 'manifest.formatVersion'),
        ({'formatVersion': 2, 'ui': 'native'}, 'manifest.ui'),
        (
          {
            'formatVersion': 2,
            'ui': {'engine': 'other'},
          },
          'manifest.ui.engine',
        ),
        (
          {
            'formatVersion': 2,
            'actions': [action(), action()],
          },
          'manifest.actions[1].name',
        ),
      ];
      for (final (manifest, path) in cases) {
        expect(
          () => MiniAppManifest.parse(manifest),
          throwsA(
            isA<MiniAppException>()
                .having((e) => e.message, 'path', contains(path))
                .having((e) => e.message, 'example', contains('Example:')),
          ),
        );
      }
    },
  );

  test(
    'sequence references forward declared actions and preserves its transitive source policy',
    () async {
      final sequence = {
        ...action(name: 'start'),
        'permissions': ['device.screen.write'],
        'executor': {
          'kind': 'sequence',
          'steps': [
            {
              'action': 'bright',
              'arguments': {'value': 77},
              'onFailure': 'continue',
            },
            {
              'action': 'save',
              'arguments': {
                'value': {r'$arg': 'value'},
              },
            },
          ],
        },
      };
      final app = await install({
        'formatVersion': 2,
        'actions': [
          sequence,
          {
            ...action(name: 'bright'),
            'permissions': ['device.screen.write'],
            'executor': {
              'kind': 'native',
              'handler': 'device.screen.brightness.set',
            },
          },
          action(),
        ],
      });
      expect(app.actions.first.toJson(), sequence);
    },
  );

  test(
    'sequence errors name the exact step and reject cycles or weakened policy',
    () async {
      Map<String, dynamic> sequence(String name, String target) => {
        ...action(name: name),
        'executor': {
          'kind': 'sequence',
          'steps': [
            {
              'action': target,
              'arguments': {'value': 2},
            },
          ],
        },
      };
      for (final actions in [
        [sequence('start', 'missing'), action()],
        [sequence('start', 'other'), sequence('other', 'start')],
        [
          sequence('start', 'bright'),
          {
            ...action(name: 'bright'),
            'permissions': ['device.screen.write'],
            'executor': {
              'kind': 'native',
              'handler': 'device.screen.brightness.set',
            },
          },
        ],
        [
          {
            ...sequence('start', 'save'),
            'executor': {
              'kind': 'sequence',
              'steps': [
                {
                  'action': 'save',
                  'arguments': {'value': 2},
                  'onFailure': 'ignore',
                },
              ],
            },
          },
          action(),
        ],
      ]) {
        await expectLater(
          install({'formatVersion': 2, 'actions': actions}),
          throwsA(
            isA<MiniAppException>()
                .having(
                  (e) => e.message,
                  'path',
                  contains('manifest.actions[0].executor'),
                )
                .having((e) => e.message, 'example', contains('Example:')),
          ),
        );
      }
    },
  );

  test(
    'sequence depth and expanded invocations are bounded before installation',
    () async {
      Map<String, dynamic> chain(int index, int repetitions) => {
        ...action(name: 'chain$index'),
        'executor': {
          'kind': 'sequence',
          'steps': [
            for (var i = 0; i < repetitions; i++)
              {
                'action': index == 8 ? 'save' : 'chain${index + 1}',
                'arguments': {'value': 2},
              },
          ],
        },
      };
      await expectLater(
        install({
          'formatVersion': 2,
          'actions': [for (var i = 0; i <= 8; i++) chain(i, 1), action()],
        }),
        throwsA(isA<MiniAppException>()),
      );
      final leaf = action(name: 'chain5');
      await expectLater(
        install({
          'formatVersion': 2,
          'actions': [for (var i = 0; i < 5; i++) chain(i, 2), leaf],
        }),
        throwsA(isA<MiniAppException>()),
      );
    },
  );

  test(
    'native Focus timer progress and timestamp formats are accepted',
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
            {'type': 'timer', 'bind': 'data.endsAt'},
            {'type': 'timer', 'bind': 'data.startedAt', 'mode': 'elapsed'},
            {
              'type': 'progress',
              'bind': 'data.endsAt',
              'startBind': 'data.startedAt',
            },
            for (final format in ['date', 'time', 'datetime'])
              {'type': 'value', 'bind': 'data.startedAt', 'format': format},
          ],
        },
      );
      expect(app.entry, 'screen.json');
    },
  );

  test(
    'native screen errors identify nested timer and progress fields',
    () async {
      for (final component in [
        {'type': 'timer', 'bind': 'data.endsAt', 'mode': 'pause'},
        {'type': 'timer'},
        {'type': 'progress', 'bind': 'data.endsAt'},
        {'type': 'progress', 'bind': 'data.endsAt', 'startBind': 'unsafe/path'},
      ]) {
        await expectLater(
          install(
            {
              'formatVersion': 2,
              'ui': {'engine': 'native'},
              'actions': [action()],
            },
            screen: {
              'version': 1,
              'components': [
                {
                  'type': 'card',
                  'children': [component],
                },
              ],
            },
          ),
          throwsA(
            isA<MiniAppException>()
                .having(
                  (e) => e.message,
                  'path',
                  contains('screen.components[0].children[0]'),
                )
                .having((e) => e.message, 'example', contains('Example:')),
          ),
        );
      }
    },
  );

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

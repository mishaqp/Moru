import 'package:Kelivo/core/services/mini_apps/mini_app_expressions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 5, 12, 30);
  Map<String, dynamic> evaluate(
    Map<String, dynamic> patch, {
    Map<String, dynamic> data = const {},
    Map<String, dynamic> arguments = const {},
  }) => MiniAppExpressions.evaluatePatch(
    patch,
    data: data,
    arguments: arguments,
    now: now,
  );

  test(
    'Focus start stores deterministic timestamps and a local session day',
    () {
      expect(
        evaluate(
          {
            'startedAt': {r'$now': true},
            'endsAt': {
              r'$add': [
                {r'$now': true},
                {r'$arg': 'durationMs'},
              ],
            },
            'sessionDay': {r'$today': true},
            'running': true,
          },
          arguments: {'durationMs': 25 * 60000},
        ),
        {
          'startedAt': now.millisecondsSinceEpoch,
          'endsAt': now.millisecondsSinceEpoch + 25 * 60000,
          'sessionDay': '2026-10-05',
          'running': true,
        },
      );
    },
  );

  test(
    'increments use the original target path and missing counters start at zero',
    () {
      expect(
        evaluate(
          {
            'count': {r'$inc': 3},
            'oldCount': {r'$data': 'count'},
            'newCounter': {r'$inc': 2},
            'nested': {
              'count': {
                r'$dec': {r'$arg': 'amount'},
              },
            },
            'missing': {r'$data': 'missing.value'},
          },
          data: {
            'count': 4,
            'nested': {'count': 10},
          },
          arguments: {'amount': 2},
        ),
        {
          'count': 7,
          'oldCount': 4,
          'newCounter': 2,
          'nested': {'count': 8},
          'missing': null,
        },
      );
    },
  );

  test('Focus stop counts running sessions once and resets a previous day', () {
    final patch = <String, dynamic>{
      'sessionsToday': {
        r'$if': [
          {
            r'$eq': [
              {r'$data': 'running'},
              true,
            ],
          },
          {
            r'$if': [
              {
                r'$eq': [
                  {r'$data': 'sessionDay'},
                  {r'$today': true},
                ],
              },
              {r'$inc': 1},
              1,
            ],
          },
          {r'$data': 'sessionsToday'},
        ],
      },
      'sessionDay': {r'$today': true},
      'running': false,
    };
    expect(
      evaluate(
        patch,
        data: {'running': true, 'sessionsToday': 2, 'sessionDay': '2026-10-05'},
      )['sessionsToday'],
      3,
    );
    expect(
      evaluate(
        patch,
        data: {'running': true, 'sessionsToday': 9, 'sessionDay': '2026-10-04'},
      )['sessionsToday'],
      1,
    );
    expect(
      evaluate(
        patch,
        data: {'running': false, 'sessionsToday': 2},
      )['sessionsToday'],
      2,
    );
  });

  test('if is lazy and equality compares JSON objects and numeric values', () {
    expect(
      evaluate({
        'value': {
          r'$if': [
            true,
            4,
            {
              r'$add': [0, 'bad'],
            },
          ],
        },
      })['value'],
      4,
    );
    expect(
      evaluate({
        'equal': {
          r'$eq': [
            {
              'a': 1,
              'b': [2],
            },
            {
              'b': [2.0],
              'a': 1.0,
            },
          ],
        },
      })['equal'],
      true,
    );
    expect(
      () => evaluate({
        'value': {
          r'$if': [1, 2, 3],
        },
      }),
      throwsA(isA<MiniAppException>()),
    );
  });

  test(
    'invalid reserved expressions include the exact path and a usable example',
    () {
      for (final expression in [
        {r'$now': false},
        {r'$now': true, 'extra': 1},
        {r'$data': '../unsafe'},
        {
          r'$eq': [1],
        },
        {
          r'$if': [true, 1],
        },
      ]) {
        expect(
          () => MiniAppExpressions.validate(
            expression,
            path: 'manifest.actions[2].executor.patch.count',
          ),
          throwsA(
            isA<MiniAppException>()
                .having(
                  (e) => e.message,
                  'path',
                  contains('manifest.actions[2].executor.patch.count'),
                )
                .having((e) => e.message, 'example', contains('Example:')),
          ),
        );
      }
      for (final patch in [
        {
          'value': {r'$inc': 'bad'},
        },
        {
          'value': {
            r'$add': [1, 'bad'],
          },
        },
        {
          'value': {
            r'$add': [1e308, 1e308],
          },
        },
      ]) {
        expect(() => evaluate(patch), throwsA(isA<MiniAppException>()));
      }
      expect(
        () => evaluate(
          {
            'value': {r'$inc': 1},
          },
          data: {'value': 'bad'},
        ),
        throwsA(isA<MiniAppException>()),
      );
    },
  );

  test('legacy empty argument keys still resolve an exact source property', () {
    expect(
      evaluate(
        {
          'value': {r'$arg': ''},
        },
        arguments: {'': 4},
      )['value'],
      4,
    );
  });

  test(
    'legacy argument expansion keeps its data quota rather than new expression reference limits',
    () {
      final large = List.filled(16384, 0);
      final result = evaluate(
        {
          for (final key in ['a', 'b', 'c', 'd', 'e']) key: {r'$arg': 'value'},
        },
        arguments: {'value': large},
      );
      expect(result.values, everyElement(hasLength(16384)));
      Object? deep = 1;
      for (var i = 0; i < 25; i++) {
        deep = {'nested': deep};
      }
      expect(
        evaluate(
          {
            'value': {r'$arg': 'value'},
          },
          arguments: {'value': deep},
        )['value'],
        deep,
      );
    },
  );

  test(
    'legacy dollar keys and wide literal maps keep their original JSON meaning',
    () {
      final patch = <String, dynamic>{
        'custom': {r'$custom': true, 'other': 1},
        'wide': {for (var i = 0; i < 257; i++) 'k$i': i},
        'groups': {
          for (var i = 0; i < 5; i++)
            'group$i': {for (var j = 0; j < 220; j++) 'k$j': j},
        },
      };
      MiniAppExpressions.validate(patch);
      expect(evaluate(patch), patch);
      expect(
        evaluate(
          {
            'copied': {r'$arg': 'value'},
          },
          arguments: {'value': List.generate(1000, (i) => i)},
        )['copied'],
        hasLength(1000),
      );
    },
  );

  test(
    'evaluation returns detached JSON and rejects excessive expression trees',
    () {
      final argument = <String, dynamic>{
        'list': [1],
      };
      final result = evaluate(
        {
          'copied': {r'$arg': 'value'},
        },
        arguments: {'value': argument},
      );
      (result['copied']['list'] as List).add(2);
      expect(argument, {
        'list': [1],
      });
      Object? nested = 1;
      for (var i = 0; i < 25; i++) {
        nested = {'next': nested};
      }
      expect(
        () => MiniAppExpressions.validate(nested),
        throwsA(isA<MiniAppException>()),
      );
      expect(
        () => MiniAppExpressions.validate(List.filled(257, 1)),
        throwsA(isA<MiniAppException>()),
      );
    },
  );
}

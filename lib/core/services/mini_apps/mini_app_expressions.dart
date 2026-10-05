import 'dart:convert';

import 'mini_app_store.dart' show MiniAppException;

/// Bounded JSON expressions for declarative state patches. No code is executed.
class MiniAppExpressions {
  static const maxDepth = 20;
  static const maxNodes = 65536;
  static const maxOperators = 1024;
  static const maxBytes = 64 * 1024;
  static const _operators = {
    r'$arg',
    r'$data',
    r'$inc',
    r'$dec',
    r'$now',
    r'$today',
    r'$add',
    r'$eq',
    r'$if',
  };

  static void validate(Object? value, {String path = 'expression'}) {
    var count = 0;
    var operators = 0;
    void visit(Object? value, String location, int depth) {
      if (++count > maxNodes || depth > maxDepth) {
        _fail(
          location,
          'Expression exceeds depth $maxDepth or $maxNodes nodes.',
          r'{"count":{"$inc":1}}',
        );
      }
      if (value is Map) {
        if (value.keys.any((key) => key is! String)) {
          _fail(
            location,
            'Expression object needs string keys.',
            r'{"running":true}',
          );
        }
        final reserved = value.keys.where(_operators.contains).toList();
        if (reserved.isNotEmpty) {
          final operator = reserved.first as String;
          if (operator != r'$arg' && ++operators > maxOperators) {
            _fail(
              location,
              'Expression exceeds $maxOperators operator nodes.',
              r'{"count":{"$inc":1}}',
            );
          }
          if (value.length != 1 || !_operators.contains(operator)) {
            _fail(
              location,
              'Use one supported expression operator per object.',
              r'{"$add":[{"$now":true},1500000]}',
            );
          }
          final operand = value[operator];
          final operandPath = '$location.$operator';
          switch (operator) {
            case r'$arg':
              if (operand is! String || operand.length > 200) {
                _fail(
                  operandPath,
                  'Argument name must be an exact string key.',
                  r'{"$arg":"durationMs"}',
                );
              }
            case r'$data':
              if (operand is! String ||
                  operand.length > 200 ||
                  !RegExp(
                    r'^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*$',
                  ).hasMatch(operand)) {
                _fail(
                  operandPath,
                  'Use a dot path relative to app data.',
                  r'{"$data":"sessionsToday"}',
                );
              }
            case r'$now':
            case r'$today':
              if (operand != true) {
                _fail(
                  operandPath,
                  'The clock operand must be true.',
                  '{"$operator":true}',
                );
              }
            case r'$eq':
            case r'$if':
              final expected = operator == r'$eq' ? 2 : 3;
              if (operand is! List || operand.length != expected) {
                _fail(
                  operandPath,
                  'This operator needs exactly $expected operands.',
                  operator == r'$eq'
                      ? r'{"$eq":[{"$data":"running"},true]}'
                      : r'{"$if":[true,1,0]}',
                );
              }
              visit(operand, operandPath, depth + 1);
            case r'$add':
              if (operand is! List || operand.isEmpty) {
                _fail(
                  operandPath,
                  'Addition needs a nonempty numeric array.',
                  r'{"$add":[1,2]}',
                );
              }
              visit(operand, operandPath, depth + 1);
            case r'$inc':
            case r'$dec':
              visit(operand, operandPath, depth + 1);
          }
        } else {
          for (final entry in value.entries) {
            visit(entry.value, '$location.${entry.key}', depth + 1);
          }
        }
      } else if (value is List) {
        if (value.length > 256) {
          _fail(location, 'Expression arrays need at most 256 items.', '[1,2]');
        }
        for (var i = 0; i < value.length; i++) {
          visit(value[i], '$location[$i]', depth + 1);
        }
      } else if (value != null &&
              value is! String &&
              value is! bool &&
              value is! num ||
          value is num && !value.isFinite) {
        _fail(
          location,
          'Expressions contain finite JSON values only.',
          r'{"running":true}',
        );
      }
    }

    visit(value, path, 0);
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      _fail(path, 'Expression exceeds 64 KiB.', r'{"count":{"$inc":1}}');
    }
  }

  static Map<String, dynamic> evaluatePatch(
    Map<String, dynamic> patch, {
    required Map<String, dynamic> data,
    required Map<String, dynamic> arguments,
    required DateTime now,
  }) {
    validate(patch, path: 'patch');
    var budget = maxNodes;
    void consume(String path, int depth) {
      if (--budget < 0 || depth > maxDepth) {
        _fail(
          path,
          'Expression evaluation exceeds its bounded size.',
          r'{"count":{"$inc":1}}',
        );
      }
    }

    Object? copy(Object? value, String path, int depth) {
      consume(path, depth);
      if (value is Map) {
        if (value.keys.any((key) => key is! String)) {
          _fail(
            path,
            'Referenced object is too large or is not JSON.',
            r'{"$data":"count"}',
          );
        }
        return {
          for (final entry in value.entries)
            entry.key as String: copy(
              entry.value,
              '$path.${entry.key}',
              depth + 1,
            ),
        };
      }
      if (value is List) {
        return [
          for (var i = 0; i < value.length; i++)
            copy(value[i], '$path[$i]', depth + 1),
        ];
      }
      if (value != null &&
              value is! String &&
              value is! bool &&
              value is! num ||
          value is num && !value.isFinite ||
          value is String && utf8.encode(value).length > maxBytes) {
        _fail(
          path,
          'Referenced value must be bounded finite JSON.',
          r'{"$data":"count"}',
        );
      }
      return value;
    }

    num number(Object? value, String path) {
      if (value is! num || !value.isFinite) {
        _fail(
          path,
          'Numeric expression operand must be finite.',
          r'{"$add":[1,2]}',
        );
      }
      return value;
    }

    Object? evaluate(
      Object? value,
      List<String> target,
      String path,
      int depth,
    ) {
      consume(path, depth);
      if (value is Map) {
        if (value.length == 1 && _operators.contains(value.keys.single)) {
          final operator = value.keys.single as String;
          final operand = value[operator];
          switch (operator) {
            case r'$arg':
              if (!arguments.containsKey(operand)) {
                _fail(
                  '$path.$operator',
                  'Missing argument "$operand".',
                  r'{"$arg":"durationMs"}',
                );
              }
              // Existing $arg templates copy source arguments, whose own
              // 64 KiB bound is enforced before runtime execution. Do not apply
              // new data-reference limits to repeated/deep legacy expansion.
              try {
                final encoded = jsonEncode(arguments[operand]);
                if (utf8.encode(encoded).length > maxBytes) {
                  _fail(
                    path,
                    'Substituted argument exceeds 64 KiB.',
                    r'{"$arg":"durationMs"}',
                  );
                }
                return jsonDecode(encoded);
              } on JsonUnsupportedObjectError {
                _fail(
                  path,
                  'Substituted argument must contain JSON values.',
                  r'{"$arg":"durationMs"}',
                );
              }
            case r'$data':
              return copy(
                _at(data, (operand as String).split('.')),
                path,
                depth + 1,
              );
            case r'$now':
              return now.millisecondsSinceEpoch;
            case r'$today':
              final local = now.toLocal();
              return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
            case r'$inc':
            case r'$dec':
              final old = number(_at(data, target) ?? 0, path);
              final amount = number(
                evaluate(operand, target, '$path.$operator', depth + 1),
                '$path.$operator',
              );
              return number(
                operator == r'$inc' ? old + amount : old - amount,
                path,
              );
            case r'$add':
              num total = 0;
              final operands = operand as List;
              for (var i = 0; i < operands.length; i++) {
                total = number(
                  total +
                      number(
                        evaluate(
                          operands[i],
                          target,
                          '$path.$operator[$i]',
                          depth + 1,
                        ),
                        '$path.$operator[$i]',
                      ),
                  path,
                );
              }
              return total;
            case r'$eq':
              final operands = operand as List;
              return _equal(
                evaluate(operands[0], target, '$path.$operator[0]', depth + 1),
                evaluate(operands[1], target, '$path.$operator[1]', depth + 1),
              );
            case r'$if':
              final operands = operand as List;
              final condition = evaluate(
                operands[0],
                target,
                '$path.$operator[0]',
                depth + 1,
              );
              if (condition is! bool) {
                _fail(
                  '$path.$operator[0]',
                  'Conditional expression must evaluate to a boolean.',
                  r'{"$if":[{"$eq":[{"$data":"running"},true]},1,0]}',
                );
              }
              final selected = condition ? 1 : 2;
              return evaluate(
                operands[selected],
                target,
                '$path.$operator[$selected]',
                depth + 1,
              );
          }
        }
        return {
          for (final entry in value.entries)
            entry.key as String: evaluate(
              entry.value,
              [...target, entry.key as String],
              '$path.${entry.key}',
              depth + 1,
            ),
        };
      }
      if (value is List) {
        return [
          for (var i = 0; i < value.length; i++)
            evaluate(value[i], [...target, '$i'], '$path[$i]', depth + 1),
        ];
      }
      return value;
    }

    final result = evaluate(patch, const [], 'patch', 0);
    if (result is! Map<String, dynamic>) {
      _fail(
        'patch',
        'A patch must evaluate to an object.',
        r'{"count":{"$inc":1}}',
      );
    }
    return result;
  }

  static Object? _at(Map<String, dynamic> data, List<String> path) {
    Object? value = data;
    for (final part in path) {
      if (value is Map) {
        value = value[part];
      } else if (value is List) {
        final index = int.tryParse(part);
        value = index != null && index >= 0 && index < value.length
            ? value[index]
            : null;
      } else {
        return null;
      }
    }
    return value;
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every(
            (entry) =>
                b.containsKey(entry.key) && _equal(entry.value, b[entry.key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }

  static Never _fail(String path, String message, String example) =>
      throw MiniAppException(
        'invalid_expression',
        '$path: $message Example: $example',
      );
}

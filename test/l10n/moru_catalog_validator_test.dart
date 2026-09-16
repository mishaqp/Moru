import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Python is a CI test dependency, not an Android runtime dependency.
  test('RU catalog passes the source validator', () async {
    final result = await Process.run('python3', ['tool/check_moru_ru.py']);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Moru RU validation PASS:'));
  });

  test('RU validator regression tests are executed', () async {
    final result = await Process.run('python3', [
      'tool/test_check_moru_ru.py',
      '-v',
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, matches(RegExp(r'Ran [1-9][0-9]* tests? in ')));
  });
}

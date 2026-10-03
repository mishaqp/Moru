import 'dart:convert';

import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:Kelivo/core/services/logging/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic redaction removes whole header, URL and JSON secrets', () {
    const secret = 'unknown-secret-123456789';
    final samples = [
      'event: failed Authorization: Bearer $secret',
      'Authorization: Bearer $secret\nCookie: sid=$secret\nX-Api-Key: $secret',
      'https://alice:$secret@example.com/api?api_key=$secret&safe=ok',
      jsonEncode({'apiKey': secret, 'token': secret, 'Cookie': secret}),
      jsonEncode({'password': 'escaped"secret', 'refresh_token': secret}),
      'https://example.com/login?code=$secret&state=secret-state',
      'oauth_code=$secret\n/home/alice/Moru /Users/bob/Moru C:\\Users\\carol\\Moru',
    ];
    for (final sample in samples) {
      final redacted = LogRedactor.redactDiagnosticText(sample);
      expect(redacted, isNot(contains(secret)), reason: sample);
      expect(redacted, isNot(contains('789')), reason: sample);
      for (final private in [
        'alice',
        'bob',
        'carol',
        'escaped',
        'secret-state',
      ]) {
        expect(redacted, isNot(contains(private)), reason: sample);
      }
    }
    expect(
      LogRedactor.redactDiagnosticText(
        'https://example.com?api_key=$secret&safe=ok',
      ),
      contains('safe=ok'),
    );
  });

  test('known secrets use the ACP redactor before generic redaction', () {
    const secret = 'custom-launch-value';
    final known = AcpSecretRedactor([secret], protectAuthentication: true);
    final safe = LogRedactor.redactDiagnosticText(
      known.text('failed: $secret'),
    );
    expect(safe, isNot(contains(secret)));
  });

  test('technical journal excludes prints and exception message text', () {
    const chat = 'PRIVATE_CHAT_SENTINEL';
    FlutterLogger.logPrint(chat);
    FlutterLogger.log('request: $chat', tag: 'Unknown');
    FlutterLogger.log('failed: $chat', tag: 'HomeViewModel');
    FlutterLogger.log(
      'failed: $chat\n#0      $chat (package:Kelivo/main.dart:42:3)',
      tag: 'DecoderParseError',
    );
    FlutterLogger.recordTechnicalError(
      StateError(chat),
      StackTrace.fromString(
        '#0      run (package:Kelivo/main.dart:42:3)\n$chat',
      ),
    );
    final tail = FlutterLogger.technicalTail;
    expect(tail, contains('HomeViewModel'));
    expect(tail, contains('StateError'));
    expect(tail, contains('main.dart:42:3'));
    expect(tail, isNot(contains(chat)));
    expect(tail, isNot(contains('Unknown')));
  });

  test('technical journal bounds memory and retains the newest event', () {
    for (var i = 0; i < 1000; i++) {
      FlutterLogger.log('failed: $i', tag: 'HomeViewModel');
    }
    FlutterLogger.log('last', tag: 'ImageFallback');
    expect(
      utf8.encode(FlutterLogger.technicalTail).length,
      lessThanOrEqualTo(128 * 1024),
    );
    expect(
      FlutterLogger.technicalTail.trimRight(),
      endsWith('[ImageFallback]'),
    );
  });
}

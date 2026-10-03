import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_connection.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  const provider = AcpProviderInput(
    baseUrl: 'https://gateway.example/v1',
    apiKey: 'A28_API_KEY_SENTINEL',
    model: 'test-model',
    headers: {
      'Authorization': 'Bearer A28_AUTH_SENTINEL',
      'X-API-Key': 'A28_HEADER_KEY_SENTINEL',
      'X-Tenant': r'A28_TENANT_"quoted"\route:team',
      'X-Literal': '{file:/does-not-exist} {env:UNSET_SENTINEL}',
    },
  );

  for (final spec in AcpAgentSpec.builtIn) {
    test('${spec.id}: provider header values never enter saved configs', () {
      final launches = [
        spec.launch(provider),
        if (spec.webLaunch(provider, port: 43123) case final launch?) launch,
      ];
      for (final launch in launches) {
        for (final file in launch.files) {
          expect(file.content, isNot(contains(provider.apiKey)));
          for (final value in provider.headers.values) {
            expect(file.content, isNot(contains(value)));
            expect(file.content, isNot(contains(jsonEncode(value))));
          }
        }
        expect(launch.environment['MORU_AGENT_API_KEY'], provider.apiKey);
      }
    });
  }

  test('Codex maps each header to its exact environment value', () {
    final launch = AcpAgentSpec.byId('codex')!.launch(provider);
    expect(
      launch.files.single.content,
      contains('[model_providers.moru.env_http_headers]'),
    );
    expect(
      launch.files.single.content,
      isNot(contains('[model_providers.moru.http_headers]')),
    );
    var index = 0;
    for (final entry in provider.headers.entries) {
      final variable = 'MORU_AGENT_HEADER_${index++}';
      expect(launch.environment[variable], entry.value);
      expect(
        launch.files.single.content,
        contains('${jsonEncode(entry.key)} = ${jsonEncode(variable)}'),
      );
    }
  });

  test(
    'OpenCode env substitution restores escaped headers without injection',
    () {
      final launch = AcpAgentSpec.byId('opencode')!.launch(provider);
      final template = jsonDecode(launch.files.single.content) as Map;
      final templateHeaders =
          template['provider']['moru']['options']['headers'];
      var index = 0;
      for (final entry in provider.headers.entries) {
        final variable = 'MORU_AGENT_HEADER_${index++}_JSON';
        expect(templateHeaders[entry.key], '{env:$variable}');
        final escaped = jsonEncode(entry.value);
        expect(
          launch.environment[variable],
          escaped
              .substring(1, escaped.length - 1)
              .replaceAll('{', r'\u007b')
              .replaceAll('}', r'\u007d'),
        );
      }
      // OpenCode 1.18.34 substitutes env values into the full JSON text before
      // decoding it. Exercise that contract with quotes, slashes and colons.
      final resolved = launch.files.single.content.replaceAllMapped(
        RegExp(r'\{env:([^}]+)\}'),
        (match) => launch.environment[match[1]]!,
      );
      final config = jsonDecode(resolved) as Map;
      expect(resolved, isNot(contains('{file:')));
      expect(
        config['provider']['moru']['options']['headers'],
        provider.headers,
      );
      expect(config['share'], 'disabled');
      expect(config['provider']['moru']['options']['apiKey'], provider.apiKey);
    },
  );

  test(
    'Kimi receives all header values through its supported env variable',
    () {
      final launch = AcpAgentSpec.byId('kimi-code')!.launch(provider);
      expect(
        launch.environment['KIMI_CODE_CUSTOM_HEADERS'],
        provider.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      );
      expect(
        launch.files.single.content,
        isNot(contains('[providers.moru.custom_headers]')),
      );
    },
  );

  test(
    'Kimi retains User-Agent only in its process-owned temporary config',
    () {
      final input = AcpProviderInput(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        headers: {...provider.headers, 'User-Agent': 'A28_USER_AGENT_SENTINEL'},
      );
      for (final launch in [
        AcpAgentSpec.byId('kimi-code')!.launch(input),
        AcpAgentSpec.byId('kimi-code')!.webLaunch(input, port: 43123)!,
      ]) {
        expect(launch.files.single.temporary, isTrue);
        expect(
          launch.files.single.content,
          contains('"User-Agent" = "A28_USER_AGENT_SENTINEL"'),
        );
        for (final value in provider.headers.values) {
          expect(
            launch.files.single.content,
            isNot(contains(jsonEncode(value))),
          );
        }
        expect(launch.files.single.content, isNot(contains(provider.apiKey)));
      }
    },
  );

  test('OpenCode safely restores credentials containing quotes and braces', () {
    const key = r'credential"\{file:/not-a-config-secret}';
    final launch = AcpAgentSpec.byId('opencode')!.launch(
      AcpProviderInput(
        baseUrl: provider.baseUrl,
        apiKey: key,
        model: provider.model,
        headers: provider.headers,
      ),
    );
    final resolved = launch.files.single.content.replaceAllMapped(
      RegExp(r'\{env:([^}]+)\}'),
      (match) => launch.environment[match[1]]!,
    );
    expect(resolved, isNot(contains('{file:')));
    final config = jsonDecode(resolved) as Map;
    expect(config['provider']['moru']['options']['apiKey'], key);
    expect(launch.files.single.content, isNot(contains(key)));
  });

  for (final language in ['en', 'zh', 'ru']) {
    test('invalid header feedback is localized in $language', () {
      final l10n = lookupAppLocalizations(Locale(language));
      const error = AcpError(
        AcpError.invalidParams,
        'Invalid provider headers: invalid name or line break',
      );
      expect(classifyAcpFailure(error), AcpFailureKind.headers);
      final localized = localizeAcpError(error, l10n) as AcpError;
      expect(localized.message, l10n.agentsErrorHeaders);
      expect(localized.code, AcpError.invalidParams);
    });
  }

  test('DeepSeek resolves header expressions from the launch environment', () {
    final launch = AcpAgentSpec.byId('deepseek-harness')!.launch(provider);
    final patch = jsonDecode(launch.files.single.content) as List;
    final config = patch.first['config']['providers']['moru'] as Map;
    var index = 0;
    for (final entry in provider.headers.entries) {
      final variable = 'MORU_AGENT_HEADER_${index++}';
      expect(config['headers'][entry.key], {
        '__jsExpr': 'process.env.$variable',
      });
      expect(launch.environment[variable], entry.value);
    }
  });

  for (final id in ['claude-code', 'kimi-code']) {
    for (final header in [
      {'X-Test': 'first\nInjected: second'},
      {'X-Test': 'first\rInjected: second'},
      {'X-Test\nInjected': 'value'},
      {'X:Injected': 'value'},
      {'X-"quoted"': 'value'},
    ]) {
      test('$id rejects line breaks in env headers', () {
        expect(
          () => AcpAgentSpec.byId(id)!.launch(
            AcpProviderInput(
              baseUrl: provider.baseUrl,
              apiKey: provider.apiKey,
              model: provider.model,
              headers: header,
            ),
          ),
          throwsA(
            isA<AcpError>().having(
              (e) => e.code,
              'code',
              AcpError.invalidParams,
            ),
          ),
        );
      });
    }
  }
}

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';

void main() {
  test('new assistants use provider authentication', () {
    const assistant = Assistant(id: 'new', name: 'New');
    expect(assistant.toJson()['agentAuthMode'], 'provider');
  });

  test('old and unknown imported modes fall back to provider', () {
    for (final mode in [null, 'unknown', 123]) {
      final assistant = Assistant.fromJson({
        'id': 'old',
        'name': 'Old',
        'agentId': 'claude-code',
        if (mode != null) 'agentAuthMode': mode,
      });
      expect(assistant.toJson()['agentAuthMode'], 'provider');
      expect(assistant.agentId, 'claude-code');
    }
  });

  test('subscription mode survives export, import and unrelated copies', () {
    final assistant = Assistant.fromJson({
      'id': 'a',
      'name': 'A',
      'agentId': 'codex',
      'agentAuthMode': 'subscription',
      'chatModelProvider': 'openai',
      'chatModelId': 'gpt-5',
    });
    final exported = assistant.copyWith(name: 'Renamed').toJson();
    expect(exported['agentAuthMode'], 'subscription');
    final restored = Assistant.fromJson(exported);
    expect(restored.toJson()['agentAuthMode'], 'subscription');
    expect(restored.chatModelProvider, 'openai');
    expect(restored.chatModelId, 'gpt-5');
  });

  test('clearing the agent restores provider authentication', () {
    final assistant = Assistant.fromJson({
      'id': 'a',
      'name': 'A',
      'agentId': 'codex',
      'agentAuthMode': 'subscription',
      'chatModelProvider': 'openai',
      'chatModelId': 'gpt-5',
    });
    final cleared = assistant.copyWith(clearAgent: true);
    expect(cleared.agentId, isNull);
    expect(cleared.toJson()['agentAuthMode'], 'provider');
    expect(cleared.chatModelProvider, 'openai');
    expect(cleared.chatModelId, 'gpt-5');
  });

  test('agent session options survive export and reset with the agent', () {
    final assistant = Assistant.fromJson({
      'id': 'a',
      'name': 'A',
      'agentId': 'codex',
      'agentConfig': {'model': 'gpt-6-astra', 'bad': 1, 'effort': 'high'},
    });
    expect(assistant.agentConfig, {'model': 'gpt-6-astra', 'effort': 'high'});
    final restored = Assistant.fromJson(
      assistant.copyWith(name: 'Renamed').toJson(),
    );
    expect(restored.agentConfig, assistant.agentConfig);
    expect(restored.copyWith(agentId: 'codex').agentConfig, hasLength(2));
    expect(restored.copyWith(agentId: 'claude-code').agentConfig, isEmpty);
    expect(restored.copyWith(clearAgent: true).agentConfig, isEmpty);
    expect(
      const Assistant(id: 'n', name: 'N').toJson().containsKey('agentConfig'),
      isFalse,
    );
  });
}

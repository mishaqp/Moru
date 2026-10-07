import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/agent_auth_mode.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/services/api/chat_api_helpers.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/tool_call_argument_privacy.dart';
import 'package:Kelivo/features/home/services/assistant_manager_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';

const _savedSecret = 'ASSISTANT_SAVED_ARGUMENT_PRIVATE';
const _incomingSecret = 'ASSISTANT_INCOMING_ARGUMENT_PRIVATE';
const _shapeSecret = 'sk-ASSISTANT-SHAPED-ARGUMENT-PRIVATE';

Assistant _savedAssistant({String secret = _savedSecret}) => Assistant(
  id: 'assistant-live',
  name: 'Current',
  customHeaders: [
    {'name': 'Authorization', 'value': 'bearer $secret'},
  ],
);

Map<String, dynamic> _arguments() => {
  'action': 'update',
  'assistant_id': 'assistant-live',
  'settings': {
    'name': 'Renamed',
    'systemPrompt': 'Use $_savedSecret and $_incomingSecret privately.',
    'messageTemplate': '{{ message }} $_savedSecret',
    'customHeaders': [
      {'name': 'Authorization', 'value': 'Bearer $_incomingSecret'},
      {'name': 'X-Api-Key', 'value': _incomingSecret},
      {'name': 'X-Other', 'value': _shapeSecret},
      {'name': 'X-Context', 'value': '/workspace/context.json'},
    ],
    'presetMessages': [
      {'role': 'user', 'content': 'Private $_savedSecret'},
    ],
    'regexRules': [
      {
        'name': 'Private $_incomingSecret',
        'pattern': _savedSecret,
        'replacement': 'replacement',
        'scopes': ['assistant'],
      },
    ],
  },
  'clear': ['temperature'],
};

ToolCallHandler _handler(
  Future<dynamic> Function(String, Map<String, dynamic>, {String? toolCallId})
  execute, {
  required Iterable<Assistant> assistants,
}) {
  final retainedCredentials = <String>{};
  return ToolCallArgumentPrivacy.register(
    execute,
    (name, args) => name == AssistantManagerTool.toolName
        ? AssistantManagerTool.argumentsForModel(
            args,
            assistants: assistants,
            retainedCredentials: retainedCredentials,
          )
        : args,
  );
}

void _expectPrivate(Object? value) {
  final text = jsonEncode(value);
  for (final secret in [_savedSecret, _incomingSecret, _shapeSecret]) {
    expect(text, isNot(contains(secret)));
  }
}

void main() {
  test(
    'public history retains credential redaction after header rotation and removal',
    () {
      final saved = [_savedAssistant()];
      final arguments = _arguments();
      final original = jsonEncode(arguments);
      final handler = _handler(
        (name, args, {toolCallId}) async => 'ok',
        assistants: saved,
      );
      _expectPrivate(
        ToolCallArgumentPrivacy.argumentsForModel(
          handler,
          AssistantManagerTool.toolName,
          arguments,
        ),
      );

      saved[0] = _savedAssistant(secret: 'ASSISTANT_ROTATED_ARGUMENT_PRIVATE');
      final protocol = {
        'function': {
          'name': AssistantManagerTool.toolName,
          'arguments': jsonEncode(arguments),
        },
      };
      _expectPrivate(ToolCallArgumentPrivacy.protocolValue(handler, protocol));
      saved.clear();
      _expectPrivate(ToolCallArgumentPrivacy.protocolValue(handler, protocol));
      expect(jsonEncode(arguments), original);
    },
  );

  test(
    'credential-shaped header names are private while ordinary values stay visible',
    () {
      const nameSecret = 'sk-ASSISTANT-HEADER-NAME-PRIVATE';
      final arguments = {
        'action': 'update',
        'assistant_id': 'assistant-live',
        'settings': {
          'customHeaders': [
            {'name': nameSecret, 'value': '/workspace/context.json'},
          ],
          'systemPrompt': 'Private $nameSecret',
        },
      };
      final original = jsonEncode(arguments);
      final handler = _handler(
        (name, args, {toolCallId}) async => 'ok',
        assistants: [_savedAssistant()],
      );
      final public = ToolCallArgumentPrivacy.argumentsForModel(
        handler,
        AssistantManagerTool.toolName,
        arguments,
      );
      expect(jsonEncode(public), isNot(contains(nameSecret)));
      expect(
        public['settings']['customHeaders'][0]['value'],
        '/workspace/context.json',
      );
      expect(jsonEncode(arguments), original);
    },
  );

  test(
    'assistant public copies hide header secrets and preserve execution arguments',
    () async {
      final arguments = _arguments();
      final original = jsonEncode(arguments);
      Map<String, dynamic>? executed;
      final handler = _handler((name, args, {toolCallId}) async {
        executed = args;
        return 'ok';
      }, assistants: [_savedAssistant()]);
      final public = ToolCallArgumentPrivacy.argumentsForModel(
        handler,
        AssistantManagerTool.toolName,
        arguments,
      );
      _expectPrivate(public);
      expect(public['action'], 'update');
      expect(public['assistant_id'], 'assistant-live');
      expect(public['settings']['customHeaders'][0]['name'], 'Authorization');
      expect(
        public['settings']['customHeaders'][3]['value'],
        '/workspace/context.json',
      );
      expect(public['settings']['presetMessages'][0]['role'], 'user');
      expect(public['settings']['regexRules'][0]['scopes'], ['assistant']);
      expect(public['clear'], ['temperature']);
      expect(identical(public, arguments), isFalse);
      expect(identical(public['settings'], arguments['settings']), isFalse);
      expect(jsonEncode(arguments), original);

      await handler(
        AssistantManagerTool.toolName,
        arguments,
        toolCallId: 'call',
      );
      expect(identical(executed, arguments), isTrue);
      expect(jsonEncode(executed), original);
    },
  );

  test(
    'denied assistant approvals and provider history contain only public copies',
    () async {
      final arguments = _arguments();
      final original = jsonEncode(arguments);
      final handler = _handler(
        (name, args, {toolCallId}) async => 'ok',
        assistants: [_savedAssistant()],
      );
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final pending = approvals.requestApproval(
        toolCallId: 'denied',
        toolName: AssistantManagerTool.toolName,
        conversationId: 'chat',
        arguments: ToolCallArgumentPrivacy.argumentsForModel(
          handler,
          AssistantManagerTool.toolName,
          arguments,
        ),
      );
      _expectPrivate(approvals.pendingRequests.single.arguments);
      approvals.deny('denied', conversationId: 'chat');
      expect((await pending).approved, isFalse);

      final protocol = [
        {
          'type': 'tool_use',
          'name': AssistantManagerTool.toolName,
          'input': arguments,
        },
        {
          'functionCall': {
            'name': AssistantManagerTool.toolName,
            'args': arguments,
          },
        },
        {
          'function': {
            'name': AssistantManagerTool.toolName,
            'arguments': jsonEncode(arguments),
          },
        },
      ];
      _expectPrivate(ToolCallArgumentPrivacy.protocolValue(handler, protocol));
      final encoded = jsonEncode(arguments);
      final chunks = await ToolCallArgumentPrivacy.publishStream(
        Stream.fromIterable([
          const ToolCallStart(
            id: 'call',
            toolName: AssistantManagerTool.toolName,
          ),
          ToolCallDelta(
            id: 'call',
            inputDelta: encoded.substring(0, encoded.length ~/ 2),
          ),
          ToolCallDelta(
            id: 'call',
            inputDelta: encoded.substring(encoded.length ~/ 2),
          ),
          const ToolCallEnd('call'),
        ]),
        handler,
      ).toList();
      _expectPrivate(
        chunks
            .whereType<ToolCallDelta>()
            .map((chunk) => chunk.inputDelta)
            .join(),
      );
      expect(jsonEncode(arguments), original);
    },
  );

  test(
    'JSON-text settings are sanitized without changing their execution text',
    () {
      final settings = jsonEncode(_arguments()['settings']);
      final arguments = {
        'action': 'update',
        'assistant_id': 'assistant-live',
        'settings': settings,
      };
      final handler = _handler(
        (name, args, {toolCallId}) async => 'ok',
        assistants: [_savedAssistant()],
      );
      final public = ToolCallArgumentPrivacy.argumentsForModel(
        handler,
        AssistantManagerTool.toolName,
        arguments,
      );
      _expectPrivate(public);
      expect(public['settings'], isA<String>());
      expect(
        jsonDecode(public['settings'])['customHeaders'][3]['value'],
        '/workspace/context.json',
      );
      expect(arguments['settings'], settings);
    },
  );

  test(
    'credential words do not alter public argument controls and live ids',
    () {
      final saved = Assistant(
        id: 'update',
        name: 'Current',
        agentId: 'codex',
        agentAuthMode: AgentAuthMode.subscription,
        agentConfig: {'reasoning_effort': 'high'},
        customHeaders: [
          {'name': 'X-Api-Key', 'value': 'update'},
          {'name': 'X-Auth-Token', 'value': 'user'},
          {'name': 'X-Secret', 'value': 'high'},
        ],
      );
      final arguments = {
        'action': 'update',
        'assistant_id': 'update',
        'settings': {
          'agentId': 'codex',
          'agentAuthMode': 'subscription',
          'agentConfig': {'reasoning_effort': 'high'},
          'customHeaders': [
            {'name': 'X-Api-Key', 'value': 'update'},
          ],
          'presetMessages': [
            {'role': 'user', 'content': 'update user high'},
          ],
        },
        'clear': ['temperature'],
      };
      final handler = _handler(
        (name, args, {toolCallId}) async => 'ok',
        assistants: [saved],
      );
      final public = ToolCallArgumentPrivacy.argumentsForModel(
        handler,
        AssistantManagerTool.toolName,
        arguments,
      );
      expect(public['action'], 'update');
      expect(public['assistant_id'], 'update');
      expect(public['settings']['agentId'], 'codex');
      expect(public['settings']['agentAuthMode'], 'subscription');
      expect(public['settings']['agentConfig'], {'reasoning_effort': 'high'});
      expect(public['settings']['customHeaders'][0]['value'], isNot('update'));
      expect(public['settings']['presetMessages'][0]['role'], 'user');
      expect(
        public['settings']['presetMessages'][0]['content'],
        isNot(contains('high')),
      );
      expect(public['clear'], ['temperature']);
    },
  );
}

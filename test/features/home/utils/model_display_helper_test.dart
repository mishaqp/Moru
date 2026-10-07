import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/agent_auth_mode.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/features/home/utils/model_display_helper.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;

  setUp(() async {
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await settings.setCurrentModel('GlobalProvider', 'global-model');
  });

  Assistant assistantWithModel({String? providerKey, String? modelId}) =>
      Assistant(
        id: 'assistant',
        name: 'Assistant',
        chatModelProvider: providerKey,
        chatModelId: modelId,
      );

  Conversation conversationWithModel({String? providerKey, String? modelId}) =>
      Conversation(
        title: 'Chat',
        chatModelProvider: providerKey,
        chatModelId: modelId,
      );

  test('per-chat models default to off', () {
    expect(settings.perChatModelEnabled, isFalse);
  });

  test('falls back to the global default when nothing overrides it', () {
    final resolved = resolveChatModel(
      settings,
      conversation: conversationWithModel(),
      assistant: assistantWithModel(),
    );

    expect(resolved.providerKey, 'GlobalProvider');
    expect(resolved.modelId, 'global-model');
  });

  test('the assistant outranks the global default', () {
    final resolved = resolveChatModel(
      settings,
      conversation: conversationWithModel(),
      assistant: assistantWithModel(
        providerKey: 'AssistantProvider',
        modelId: 'assistant-model',
      ),
    );

    expect(resolved.providerKey, 'AssistantProvider');
    expect(resolved.modelId, 'assistant-model');
  });

  test('a retired on-device model pin falls back to the assistant', () async {
    await settings.setPerChatModelEnabled(true);
    final resolved = resolveChatModel(
      settings,
      conversation: conversationWithModel(
        providerKey: 'litert-local',
        modelId: 'old-model',
      ),
      assistant: assistantWithModel(
        providerKey: 'AssistantProvider',
        modelId: 'assistant-model',
      ),
    );

    expect(resolved.providerKey, 'AssistantProvider');
    expect(resolved.modelId, 'assistant-model');
  });

  test('a retired assistant model falls back to the global model', () {
    final resolved = resolveChatModel(
      settings,
      assistant: assistantWithModel(
        providerKey: 'litert-local',
        modelId: 'old-model',
      ),
    );

    expect(resolved.providerKey, 'GlobalProvider');
    expect(resolved.modelId, 'global-model');
  });

  test('the conversation outranks the assistant when enabled', () async {
    await settings.setPerChatModelEnabled(true);

    final resolved = resolveChatModel(
      settings,
      conversation: conversationWithModel(
        providerKey: 'ConversationProvider',
        modelId: 'conversation-model',
      ),
      assistant: assistantWithModel(
        providerKey: 'AssistantProvider',
        modelId: 'assistant-model',
      ),
    );

    expect(resolved.providerKey, 'ConversationProvider');
    expect(resolved.modelId, 'conversation-model');
  });

  test('a conversation without an override follows the assistant', () {
    final resolved = resolveChatModel(
      settings,
      conversation: conversationWithModel(),
      assistant: assistantWithModel(
        providerKey: 'AssistantProvider',
        modelId: 'assistant-model',
      ),
    );

    expect(resolved.providerKey, 'AssistantProvider');
  });

  test('a null conversation resolves as before this feature', () {
    final resolved = resolveChatModel(
      settings,
      assistant: assistantWithModel(
        providerKey: 'AssistantProvider',
        modelId: 'assistant-model',
      ),
    );

    expect(resolved.providerKey, 'AssistantProvider');
    expect(resolved.modelId, 'assistant-model');
  });

  test(
    'the conversation layer is skipped when per-chat models are off',
    () async {
      await settings.setPerChatModelEnabled(false);

      final resolved = resolveChatModel(
        settings,
        conversation: conversationWithModel(
          providerKey: 'ConversationProvider',
          modelId: 'conversation-model',
        ),
        assistant: assistantWithModel(
          providerKey: 'AssistantProvider',
          modelId: 'assistant-model',
        ),
      );

      expect(resolved.providerKey, 'AssistantProvider');
      expect(resolved.modelId, 'assistant-model');
    },
  );

  test('turning per-chat models back on restores the pin', () async {
    final conversation = conversationWithModel(
      providerKey: 'ConversationProvider',
      modelId: 'conversation-model',
    );
    final assistant = assistantWithModel(
      providerKey: 'AssistantProvider',
      modelId: 'assistant-model',
    );

    await settings.setPerChatModelEnabled(false);
    await settings.setPerChatModelEnabled(true);

    final resolved = resolveChatModel(
      settings,
      conversation: conversation,
      assistant: assistant,
    );

    expect(resolved.providerKey, 'ConversationProvider');
    expect(resolved.modelId, 'conversation-model');
  });

  test('getActiveModelIds and getModelDisplayInfo agree with it', () async {
    await settings.setPerChatModelEnabled(true);

    final conversation = conversationWithModel(
      providerKey: 'ConversationProvider',
      modelId: 'conversation-model',
    );
    final assistant = assistantWithModel(
      providerKey: 'AssistantProvider',
      modelId: 'assistant-model',
    );

    final ids = getActiveModelIds(
      settings,
      conversation: conversation,
      assistant: assistant,
    );
    final display = getModelDisplayInfo(
      settings,
      conversation: conversation,
      assistant: assistant,
    );

    expect(ids.providerKey, 'ConversationProvider');
    expect(ids.modelId, 'conversation-model');
    expect(display.providerKey, 'ConversationProvider');
    expect(display.modelId, 'conversation-model');
    expect(display.isConfigured, isTrue);
  });

  group('subscription chat source', () {
    for (final id in [AcpAgentSpec.claudeCodeId, AcpAgentSpec.codexId]) {
      test('$id works without any selected Moru provider or model', () async {
        await settings.resetCurrentModel();
        final assistant = Assistant(
          id: 'subscription',
          name: 'Subscription',
          agentId: id,
          agentAuthMode: AgentAuthMode.subscription,
        );
        final source = resolveChatModel(settings, assistant: assistant);
        expect(source, (providerKey: 'acp:$id', modelId: id));
        expect(getActiveModelIds(settings, assistant: assistant), source);
        expect(settings.currentModelProvider, isNull);
        expect(settings.currentModelId, isNull);
        expect(assistant.chatModelProvider, isNull);
        expect(assistant.chatModelId, isNull);
      });

      test('$id displays the official agent name without an API config', () {
        final assistant = Assistant(
          id: 'subscription',
          name: 'Subscription',
          agentId: id,
          agentAuthMode: AgentAuthMode.subscription,
        );
        final display = getModelDisplayInfo(settings, assistant: assistant);
        expect(display.providerKey, 'acp:$id');
        expect(display.modelId, id);
        expect(display.modelDisplay, AcpAgentSpec.byId(id)!.name);
        expect(display.providerName, AcpAgentSpec.byId(id)!.name);
        expect(display.isConfigured, isTrue);
        expect(display.getConfig(settings), isNull);
      });
    }

    test(
      'subscription bypasses pins while returning to provider restores them',
      () async {
        final assistant = Assistant(
          id: 'subscription',
          name: 'Subscription',
          agentId: AcpAgentSpec.codexId,
          agentAuthMode: AgentAuthMode.subscription,
          chatModelProvider: 'AssistantProvider',
          chatModelId: 'assistant-model',
        );
        final conversation = conversationWithModel(
          providerKey: 'ConversationProvider',
          modelId: 'conversation-model',
        );
        final originalAssistant = assistant.toJson();
        for (final perChatEnabled in [false, true]) {
          await settings.setPerChatModelEnabled(perChatEnabled);
          expect(
            resolveChatModel(
              settings,
              assistant: assistant,
              conversation: conversation,
            ),
            (providerKey: 'acp:codex', modelId: 'codex'),
          );
          expect(
            resolveChatModel(
              settings,
              assistant: assistant.copyWith(
                agentAuthMode: AgentAuthMode.provider,
              ),
              conversation: conversation,
            ),
            perChatEnabled
                ? (
                    providerKey: 'ConversationProvider',
                    modelId: 'conversation-model',
                  )
                : (
                    providerKey: 'AssistantProvider',
                    modelId: 'assistant-model',
                  ),
          );
          expect(assistant.toJson(), originalAssistant);
          expect(conversation.chatModelProvider, 'ConversationProvider');
          expect(conversation.chatModelId, 'conversation-model');
          expect(settings.currentModelProvider, 'GlobalProvider');
          expect(settings.currentModelId, 'global-model');
        }
      },
    );

    test(
      'old imported agent assistants keep provider model priority',
      () async {
        await settings.setPerChatModelEnabled(true);
        final assistant = Assistant.fromJson({
          'id': 'old',
          'name': 'Old',
          'agentId': 'codex',
          'chatModelProvider': 'AssistantProvider',
          'chatModelId': 'assistant-model',
        });
        expect(
          resolveChatModel(
            settings,
            assistant: assistant,
            conversation: conversationWithModel(
              providerKey: 'ConversationProvider',
              modelId: 'conversation-model',
            ),
          ),
          (providerKey: 'ConversationProvider', modelId: 'conversation-model'),
        );
      },
    );

    test('unsupported or absent agents do not become subscription sources', () {
      for (final id in [null, 'opencode', 'custom:mine', 'missing']) {
        expect(
          resolveChatModel(
            settings,
            assistant: Assistant(
              id: 'invalid',
              name: 'Invalid',
              agentId: id,
              agentAuthMode: AgentAuthMode.subscription,
            ),
          ),
          (providerKey: 'GlobalProvider', modelId: 'global-model'),
        );
      }
    });
  });
}

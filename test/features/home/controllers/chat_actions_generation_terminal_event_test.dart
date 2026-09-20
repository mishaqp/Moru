import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_terminal_event.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/business_test_harness.dart';

/// [failCompletion] mirrors `chat_actions_terminal_persist_test.dart`'s own
/// fake: when true, a `completed` write throws, so
/// `_finalizeStreamingCheckpoint`'s `committed` guard must stay false and
/// [ChatActions.generationTerminalEvents] must never fire for it.
class _FakeChatService extends ChatService {
  _FakeChatService({this.failCompletion = false});
  final bool failCompletion;

  @override
  Future<GenerationRun?> finalizeGenerationRunSilent({
    required ChatMessage message,
    required List<Map<String, dynamic>> toolEvents,
    required String? generationRunId,
    required GenerationRunState? expectedState,
    required int? expectedStateRevision,
    required GenerationRunState terminalState,
    int? checkpointSeq,
    String? errorCode,
  }) async {
    if (failCompletion && terminalState == GenerationRunState.completed) {
      throw StateError('persist failed');
    }
    return null;
  }
}

// Built directly (not through HomeViewModel, whose ChatActions always
// defaults to the real MobileBackgroundCoordinator.instance singleton and
// its unmocked platform channels) so each test gets an isolated, explicit
// MobileBackgroundCoordinator -- the same pattern
// chat_actions_terminal_persist_test.dart already uses.
ChatActions _actionsFor(
  BuildContext context,
  ChatService service,
  SettingsProvider settings,
  MobileBackgroundCoordinator background,
) {
  final chatController = ChatController(chatService: service);
  final streamController = StreamController(
    onStateChanged: () {},
    getSettingsProvider: () => settings,
    getCurrentConversationId: () => 'conversation-1',
  );
  final messageBuilder = MessageBuilderService(
    chatService: service,
    contextProvider: context,
  );
  final generationController = GenerationController(
    chatService: service,
    chatController: chatController,
    streamController: streamController,
    messageBuilderService: messageBuilder,
    contextProvider: context,
    onStateChanged: () {},
    getTitleForLocale: (_) => 'title',
  );
  final messageGeneration = MessageGenerationService(
    chatService: service,
    messageBuilderService: messageBuilder,
    generationController: generationController,
    streamController: streamController,
    contextProvider: context,
  );
  final viewModel = HomeViewModel(
    chatService: service,
    messageBuilderService: messageBuilder,
    messageGenerationService: messageGeneration,
    generationController: generationController,
    streamController: streamController,
    chatController: chatController,
    contextProvider: context,
    getTitleForLocale: (_) => 'title',
  );
  return ChatActions(
    chatService: service,
    chatController: chatController,
    streamController: streamController,
    generationController: generationController,
    messageGenerationService: messageGeneration,
    contextProvider: context,
    viewModel: viewModel,
    backgroundCoordinator: background,
  );
}

StreamingState _stateFor(
  SettingsProvider settings, {
  required String messageId,
  required String content,
}) => StreamingState(
  GenerationContext(
    assistantMessage: ChatMessage(
      id: messageId,
      role: 'assistant',
      content: '',
      conversationId: 'conversation-1',
      isStreaming: true,
    ),
    apiMessages: const [],
    userImagePaths: const [],
    allowImagesApiRouting: false,
    providerKey: 'test',
    modelId: 'test-model',
    assistant: null,
    settings: settings,
    config: ProviderConfig(
      id: 'test',
      enabled: true,
      name: 'Test',
      apiKey: '',
      baseUrl: '',
    ),
    toolDefs: const [],
    supportsReasoning: false,
    enableReasoning: false,
    streamOutput: true,
  ),
)..fullContentRaw = content;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  Future<ChatActions> pumpActions(
    WidgetTester tester,
    ChatService service,
    SettingsProvider settings, {
    required MobileBackgroundCoordinator background,
  }) async {
    late ChatActions actions;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatService>.value(value: service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              actions = _actionsFor(context, service, settings, background);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return actions;
  }

  testWidgets(
    'a successful finish emits a completed event carrying the real content',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'The final answer.',
      );
      await actions.debugFinishStreaming(state);

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.conversationId, 'conversation-1');
      expect(event.assistantMessageId, 'assistant-1');
      expect(event.terminalState, GenerationRunState.completed);
      expect(event.succeeded, isTrue);
      expect(event.cancelled, isFalse);
      expect(event.message.content, 'The final answer.');
      expect(event.errorCode, isNull);
    },
  );

  testWidgets(
    'a failed terminal write never emits: a listener would otherwise wait '
    'forever for a run that never actually finished',
    (tester) async {
      final service = _FakeChatService(failCompletion: true);
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'unwritten',
      );
      await expectLater(
        actions.debugFinishStreaming(state),
        throwsA(isA<StateError>()),
      );
      await tester.pump();

      expect(events, isEmpty);
    },
  );

  testWidgets(
    'a stream error emits a failed event with the error code, not the '
    'success path',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'Partial reply',
      );
      await actions.debugHandleStreamError(
        const ProviderOAuthException(
          ProviderOAuthFailure.loginRequired,
          providerId: 'account',
        ),
        state,
      );
      await tester.pump();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.terminalState, GenerationRunState.failed);
      expect(event.succeeded, isFalse);
      expect(event.cancelled, isFalse);
      expect(event.errorCode, 'oauth_login_required');
      expect(event.message.content, 'Partial reply');
    },
  );

  testWidgets('a manual cancel (Stop) emits a cancelled event', (tester) async {
    final service = _FakeChatService();
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.linux,
    );
    addTearDown(background.dispose);
    final actions = await pumpActions(
      tester,
      service,
      settings,
      background: background,
    );
    final events = <GenerationTerminalEvent>[];
    actions.generationTerminalEvents.listen(events.add);

    actions.debugTrackActiveMessage(
      ChatMessage(
        id: 'assistant-1',
        role: 'assistant',
        content: 'partial before stop',
        conversationId: 'conversation-1',
        isStreaming: true,
      ),
    );

    await actions.cancelStreamingById('conversation-1');
    await tester.pump();

    expect(events, hasLength(1));
    final event = events.single;
    expect(event.assistantMessageId, 'assistant-1');
    expect(event.terminalState, GenerationRunState.cancelled);
    expect(event.succeeded, isFalse);
    expect(event.cancelled, isTrue);
  });

  testWidgets(
    'a preparation failure before streaming ever started still emits',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      await actions.handleSendGenerationFailure(
        error: StateError('generation failed'),
        conversationId: 'conversation-1',
        assistantMessage: ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: '',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      );
      await tester.pump();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.terminalState, GenerationRunState.failed);
      expect(event.errorCode, 'preparation_failed');
    },
  );
}

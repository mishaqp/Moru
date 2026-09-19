import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/health_data_type.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/web_source.dart';
import 'package:Kelivo/features/home/services/browser_agent_actions.dart';
import 'package:Kelivo/features/home/services/health_data_selection.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assistant local tools', () {
    const localToolsAssistant = Assistant(
      id: 'a1',
      name: 'Assistant',
      localToolIds: [
        LocalToolNames.timeInfo,
        LocalToolNames.clipboard,
        LocalToolNames.textToSpeech,
        LocalToolNames.askUser,
      ],
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      DeviceLocalTools.debugResetIosCapabilities();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      DeviceLocalTools.debugResetIosCapabilities();
    });

    test('assistant defaults to no local tools', () {
      const assistant = Assistant(id: 'a1', name: 'Assistant');

      expect(assistant.localToolIds, isEmpty);
    });

    test('assistant defaults to web search disabled', () {
      const assistant = Assistant(id: 'a1', name: 'Assistant');

      expect(assistant.searchEnabled, isFalse);
    });

    test('assistant json keeps missing local tools disabled', () {
      final assistant = Assistant.fromJson(const {
        'id': 'a1',
        'name': 'Assistant',
      });

      expect(assistant.localToolIds, isEmpty);
    });

    test('assistant json keeps missing web search disabled', () {
      final assistant = Assistant.fromJson(const {
        'id': 'a1',
        'name': 'Assistant',
      });

      expect(assistant.searchEnabled, isFalse);
    });

    test('assistant json round trips enabled web search', () {
      const assistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        searchEnabled: true,
      );

      final decoded = Assistant.fromJson(assistant.toJson());

      expect(decoded.searchEnabled, isTrue);
    });

    test('assistant json round trips enabled local tools', () {
      const assistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        localToolIds: [LocalToolNames.timeInfo, LocalToolNames.clipboard],
      );

      final decoded = Assistant.fromJson(assistant.toJson());

      expect(decoded.localToolIds, const [
        LocalToolNames.timeInfo,
        LocalToolNames.clipboard,
      ]);
    });

    test(
      'builds enabled local tool definitions only when model supports tools',
      () {
        final disabled = LocalToolsService.buildToolDefinitions(
          assistant: const Assistant(id: 'a2', name: 'Assistant'),
          supportsTools: true,
        );
        final unsupported = LocalToolsService.buildToolDefinitions(
          assistant: localToolsAssistant,
          supportsTools: false,
        );
        final enabled = LocalToolsService.buildToolDefinitions(
          assistant: localToolsAssistant,
          supportsTools: true,
        );

        expect(disabled.map((tool) => tool['function']['name']), const [
          LocalToolNames.browserUse,
        ]);
        expect(unsupported, isEmpty);
        expect(enabled.map((tool) => tool['function']['name']), const [
          LocalToolNames.timeInfo,
          LocalToolNames.clipboard,
          LocalToolNames.textToSpeech,
          LocalToolNames.askUser,
          LocalToolNames.browserUse,
        ]);
        expect(enabled.first['function']['parameters']['properties'], isEmpty);
        expect(
          enabled[1]['function']['parameters']['properties']['action']['enum'],
          const ['read', 'write'],
        );
        final ttsParameters = enabled[2]['function']['parameters'];
        expect(ttsParameters['required'], const ['text']);
        expect(ttsParameters['properties']['text']['type'], 'string');
        final askUserParameters = enabled[3]['function']['parameters'];
        expect(askUserParameters['required'], const ['questions']);
        final questionSchema =
            askUserParameters['properties']['questions']['items'];
        expect(questionSchema['required'], const ['id', 'question']);
        expect(questionSchema['properties']['type']['enum'], const [
          'single',
          'multi',
        ]);
        expect(
          questionSchema['properties']['options']['items']['type'],
          'string',
        );
      },
    );

    test('shared browser schema exposes only the bounded browser actions', () {
      final definition = LocalToolsService.definitionFor(
        LocalToolNames.browserUse,
      );
      final function = definition['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;

      expect(function['name'], LocalToolNames.browserUse);
      expect((properties['action'] as Map<String, dynamic>)['enum'], const [
        'open',
        'observe',
        'click',
        'type',
        'submit',
        'press_key',
        'scroll',
        'back',
        'forward',
        'reload',
        'read',
        'wait_for',
        'eval_js',
        'close',
      ]);
      expect((properties['scope'] as Map<String, dynamic>)['enum'], const [
        'viewport',
        'document',
      ]);
      expect(
        (properties['max_text_chars'] as Map<String, dynamic>)['default'],
        3000,
      );
      expect(
        (properties['max_elements'] as Map<String, dynamic>)['default'],
        36,
      );
      expect(parameters['required'], const ['action']);
    });

    test(
      'BrowserAgentActions stays in sync with the schema enum and approval gate',
      () {
        final schemaActions = Set<String>.from(
          (LocalToolsService.definitionFor(
                LocalToolNames.browserUse,
              )['function']
              as Map<
                String,
                dynamic
              >)['parameters']['properties']['action']['enum'],
        );
        final catalogActions = BrowserAgentActions.all.map((a) => a.id).toSet();
        expect(catalogActions, schemaActions);

        for (final action in BrowserAgentActions.all) {
          expect(
            LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, {
              'action': action.id,
            }),
            action.requiresApproval,
            reason: action.id,
          );
        }
      },
    );

    test(
      'Android automatically exposes shared browser to every assistant',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        const assistant = Assistant(id: 'a1', name: 'Assistant');

        expect(
          LocalToolsService.isEnabledForAssistant(
            LocalToolNames.browserUse,
            assistant,
          ),
          isTrue,
        );
        expect(
          LocalToolsService.buildToolDefinitions(
            assistant: assistant,
            supportsTools: true,
          ).map((tool) => tool['function']['name']),
          contains(LocalToolNames.browserUse),
        );

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'invalid'},
          assistant,
        );
        expect(result, isNotNull);
        expect(jsonDecode(result!)['error'], 'invalid_action');
      },
    );

    test(
      'shared browser requires approval for state-changing actions only',
      () {
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'open',
          }),
          isFalse,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'observe',
          }),
          isFalse,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'click',
          }),
          isTrue,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'type',
          }),
          isTrue,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'submit',
          }),
          isTrue,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'press_key',
          }),
          isTrue,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'read',
          }),
          isFalse,
        );
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
            'action': 'wait_for',
          }),
          isFalse,
        );
      },
    );

    test(
      'shared browser submit without an element_id reports invalid_arguments',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'submit'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'invalid_arguments');
      },
    );

    test(
      'shared browser press_key without a key reports invalid_arguments',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'press_key'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'invalid_arguments');
      },
    );

    test(
      'shared browser wait_for without a selector reports invalid_arguments',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'wait_for'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'invalid_arguments');
      },
    );

    test('shared browser eval_js requires approval like click/type', () {
      expect(
        LocalToolNames.requiresApprovalFor(LocalToolNames.browserUse, const {
          'action': 'eval_js',
        }),
        isTrue,
      );
    });

    test(
      'shared browser eval_js blocks cookie access, eval/Function, and string timers',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        for (final code in [
          'document.cookie',
          'var c = document . cookie;',
          "eval('alert(1)')",
          "new Function('return 1')()",
          "setTimeout('alert(1)', 100)",
        ]) {
          final result = await LocalToolsService.tryHandleToolCall(
            LocalToolNames.browserUse,
            {'action': 'eval_js', 'code': code},
            assistant,
          );
          final decoded = jsonDecode(result!) as Map<String, dynamic>;
          expect(decoded['ok'], isFalse, reason: 'code: $code');
          expect(decoded['error'], 'blocked_pattern', reason: 'code: $code');
        }
      },
    );

    test(
      'shared browser eval_js without an open browser reports browser_not_open',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'eval_js', 'code': 'document.title'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'browser_not_open');
      },
    );

    test(
      'shared browser eval_js without code reports invalid_arguments',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'eval_js'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'invalid_arguments');
      },
    );

    test(
      'a browser_use action turned off in settings is rejected before it runs',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'eval_js', 'code': 'document.title'},
          assistant,
          disabledBrowserActions: const {'eval_js'},
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'action_disabled');
      },
    );

    test(
      'disabling one browser_use action leaves the others working',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'read'},
          assistant,
          disabledBrowserActions: const {'eval_js'},
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['error'], 'browser_not_open');
      },
    );

    tearDown(() {
      BrowserAgentSession.instance.currentActivity.value = null;
      BrowserAgentSession.instance.recentActivity.clear();
    });

    test(
      'browser_use actions record their activity even when the call fails',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'press_key', 'key': 'Enter'},
          assistant,
        );

        final activity = BrowserAgentSession.instance.currentActivity.value;
        expect(activity?.action, 'press_key');
        expect(activity?.detail, 'Enter');
        expect(BrowserAgentSession.instance.recentActivity, hasLength(1));
      },
    );

    test(
      'an open call records the target URL as its activity detail',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'open', 'url': 'https://example.com'},
          assistant,
        );

        final activity = BrowserAgentSession.instance.currentActivity.value;
        expect(activity?.action, 'open');
        expect(activity?.detail, 'https://example.com');
      },
    );

    test(
      'a disabled action never reaches BrowserAgentTool, so it records no activity',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'eval_js', 'code': 'document.title'},
          assistant,
          disabledBrowserActions: const {'eval_js'},
        );

        expect(BrowserAgentSession.instance.currentActivity.value, isNull);
      },
    );

    test(
      'shared browser read without an open browser reports browser_not_open',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          const {'action': 'read'},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'browser_not_open');
      },
    );

    test(
      'shared browser read reuses a cached source_id without reopening the page',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final source = WebSource(
          sourceId: WebSourceId.newId(),
          url: 'https://example.com/article',
          mode: WebSourceMode.text,
          title: 'Example article',
          text: 'Paragraph one.\n\nParagraph two, the important part.',
          storedAtMillis: DateTime.now().millisecondsSinceEpoch,
          origin: WebSourceOrigin.browser,
        );
        browserSourceCache.put(source);
        addTearDown(() => browserSourceCache.remove(source.sourceId));

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          {'action': 'read', 'source_id': source.sourceId},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['cached'], isTrue);
        expect(decoded['source_id'], source.sourceId);
        expect(decoded['text'], source.text);
      },
    );

    test(
      'shared browser read reports unknown_source_id for an unrecognized handle',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const assistant = Assistant(id: 'a1', name: 'Assistant');

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.browserUse,
          {'action': 'read', 'source_id': WebSourceId.newId()},
          assistant,
        );
        final decoded = jsonDecode(result!) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], 'unknown_source_id');
      },
    );

    test('text to speech call starts playback and returns success', () async {
      final spokenTexts = <String>[];

      final result = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.textToSpeech,
        const {'text': 'Read this aloud.'},
        localToolsAssistant,
        onSpeakText: (text) async {
          spokenTexts.add(text);
        },
      );

      expect(spokenTexts, const ['Read this aloud.']);
      expect(result, isNotNull);
      expect(jsonDecode(result!) as Map<String, dynamic>, {'success': true});
    });

    test('text to speech requires non-empty text', () async {
      expect(
        () => LocalToolsService.tryHandleToolCall(
          LocalToolNames.textToSpeech,
          const {},
          localToolsAssistant,
          onSpeakText: (_) async {},
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => LocalToolsService.tryHandleToolCall(
          LocalToolNames.textToSpeech,
          const {'text': '   '},
          localToolsAssistant,
          onSpeakText: (_) async {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'time info call returns local date, weekday, time, timezone fields',
      () async {
        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.timeInfo,
          const {},
          localToolsAssistant,
        );

        expect(result, isNotNull);
        final payload = jsonDecode(result!) as Map<String, dynamic>;
        expect(payload['year'], isA<int>());
        expect(payload['month'], isA<int>());
        expect(payload['day'], isA<int>());
        expect(payload['weekday'], isA<String>());
        expect(payload['weekday_en'], isA<String>());
        expect(payload['weekday_index'], inInclusiveRange(1, 7));
        expect(payload['date'], isA<String>());
        expect(payload['time'], isA<String>());
        expect(payload['datetime'], isA<String>());
        expect(payload['timezone'], isA<String>());
        expect(payload['utc_offset'], isA<String>());
        expect(payload['timestamp_ms'], isA<int>());
      },
    );

    test(
      'clipboard read returns plain text from the device clipboard',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.getData') {
                return const <String, dynamic>{'text': 'clipboard text'};
              }
              fail('Unexpected platform call: ${call.method}');
            });

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.clipboard,
          const {'action': 'read'},
          localToolsAssistant,
        );

        expect(result, isNotNull);
        expect(jsonDecode(result!) as Map<String, dynamic>, {
          'text': 'clipboard text',
        });
      },
    );

    test('clipboard write updates the device clipboard', () async {
      String? writtenText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              writtenText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            }
            fail('Unexpected platform call: ${call.method}');
          });

      final result = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.clipboard,
        const {'action': 'write', 'text': 'next clipboard'},
        localToolsAssistant,
      );

      expect(writtenText, 'next clipboard');
      expect(result, isNotNull);
      expect(jsonDecode(result!) as Map<String, dynamic>, {
        'success': true,
        'text': 'next clipboard',
      });
    });

    test('clipboard write requires text', () async {
      expect(
        () => LocalToolsService.tryHandleToolCall(
          LocalToolNames.clipboard,
          const {'action': 'write'},
          localToolsAssistant,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Android exposes location while other iOS tools stay gated', () {
      const iosAssistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        localToolIds: [
          LocalToolNames.currentLocation,
          LocalToolNames.weather,
          LocalToolNames.healthSummary,
          LocalToolNames.remindersQuery,
          LocalToolNames.remindersCreate,
          LocalToolNames.remindersComplete,
        ],
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ).map((tool) => tool['function']['name']),
        [LocalToolNames.browserUse, LocalToolNames.currentLocation],
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      DeviceLocalTools.debugSetWeatherKitAvailable(true);
      DeviceLocalTools.debugSetHealthDataAvailable(true);
      final enabled = LocalToolsService.buildToolDefinitions(
        assistant: iosAssistant,
        supportsTools: true,
      );
      expect(enabled.map((tool) => tool['function']['name']), [
        LocalToolNames.currentLocation,
        LocalToolNames.weather,
        LocalToolNames.healthSummary,
        LocalToolNames.remindersQuery,
        LocalToolNames.remindersCreate,
        LocalToolNames.remindersComplete,
      ]);
    });

    test('location is unavailable on desktop platforms', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          LocalToolsService.isAvailableOnThisPlatform(
            LocalToolNames.currentLocation,
          ),
          isFalse,
        );
      }
    });

    test(
      'Android location permissions and calls use the native channel',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        const channel = MethodChannel('app.device_tools');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          messenger.setMockMethodCallHandler(channel, null);
        });
        var granted = false;
        final calls = <String>[];
        const payload = '{"latitude":31.2,"longitude":121.5,"accuracy_m":100}';
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'hasLocationPermission':
              return granted;
            case 'requestLocationPermission':
              granted = true;
              return true;
            case 'getCurrentLocation':
              expect(jsonDecode(call.arguments as String), isEmpty);
              return payload;
            default:
              fail('Unexpected platform call: ${call.method}');
          }
        });

        expect(await DeviceLocalTools.hasLocationPermission(), isFalse);
        expect(await DeviceLocalTools.requestLocationPermission(), isTrue);
        expect(await DeviceLocalTools.hasLocationPermission(), isTrue);
        const assistant = Assistant(
          id: 'a1',
          name: 'Assistant',
          localToolIds: [LocalToolNames.currentLocation],
        );
        expect(
          await LocalToolsService.tryHandleToolCall(
            LocalToolNames.currentLocation,
            {},
            assistant,
          ),
          payload,
        );
        expect(calls, [
          'hasLocationPermission',
          'requestLocationPermission',
          'hasLocationPermission',
          'getCurrentLocation',
        ]);
        calls.clear();
        expect(
          await LocalToolsService.tryHandleToolCall(
            LocalToolNames.currentLocation,
            {},
            const Assistant(id: 'disabled', name: 'Disabled'),
          ),
          isNull,
        );
        expect(calls, isEmpty);
      },
    );

    test(
      'Android permanent denial reaches the UI and settings can open',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        const channel = MethodChannel('app.device_tools');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          messenger.setMockMethodCallHandler(channel, null);
        });
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'requestLocationPermission') {
            throw PlatformException(
              code: DeviceLocalTools.locationPermissionPermanentlyDenied,
            );
          }
          return null;
        });

        await expectLater(
          DeviceLocalTools.requestLocationPermission(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              DeviceLocalTools.locationPermissionPermanentlyDenied,
            ),
          ),
        );
        expect(calls, ['requestLocationPermission']);
        await DeviceLocalTools.openAppSettings();
        expect(calls, ['requestLocationPermission', 'openAppSettings']);
      },
    );

    test('Android location preserves native permission errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('app.device_tools');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestLocationPermission') return false;
        return '{"error":"NO_PERMISSION","message":"Location permission is not granted."}';
      });
      expect(await DeviceLocalTools.requestLocationPermission(), isFalse);
      final result = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.currentLocation,
        {},
        const Assistant(
          id: 'a1',
          name: 'Assistant',
          localToolIds: [LocalToolNames.currentLocation],
        ),
      );
      expect(jsonDecode(result!)['error'], 'NO_PERMISSION');
    });

    test('weather tool is hidden until WeatherKit is available', () {
      const iosAssistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        localToolIds: [LocalToolNames.weather],
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(DeviceLocalTools.weatherSupported, isFalse);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ),
        isEmpty,
      );

      DeviceLocalTools.debugSetWeatherKitAvailable(false);
      expect(DeviceLocalTools.weatherSupported, isFalse);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ),
        isEmpty,
      );

      DeviceLocalTools.debugSetWeatherKitAvailable(true);
      expect(DeviceLocalTools.weatherSupported, isTrue);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ).map((tool) => tool['function']['name']),
        [LocalToolNames.weather],
      );
    });

    test('health tool is hidden until HealthKit is available', () {
      const iosAssistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        localToolIds: [LocalToolNames.healthSummary],
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(DeviceLocalTools.healthSupported, isFalse);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ),
        isEmpty,
      );

      DeviceLocalTools.debugSetHealthDataAvailable(false);
      expect(DeviceLocalTools.healthSupported, isFalse);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ),
        isEmpty,
      );

      DeviceLocalTools.debugSetHealthDataAvailable(true);
      expect(DeviceLocalTools.healthSupported, isTrue);
      expect(
        LocalToolsService.buildToolDefinitions(
          assistant: iosAssistant,
          supportsTools: true,
        ).map((tool) => tool['function']['name']),
        [LocalToolNames.healthSummary],
      );
    });

    test(
      'prefetchIosCapabilities caches WeatherKit and HealthKit availability',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        const channel = MethodChannel('app.device_tools');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'isWeatherKitAvailable') return true;
              if (call.method == 'isHealthDataAvailable') return true;
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        expect(DeviceLocalTools.weatherSupported, isFalse);
        expect(DeviceLocalTools.healthSupported, isFalse);
        expect(await DeviceLocalTools.prefetchIosCapabilities(), isTrue);
        expect(DeviceLocalTools.weatherSupported, isTrue);
        expect(DeviceLocalTools.healthSupported, isTrue);
        expect(await DeviceLocalTools.prefetchIosCapabilities(), isTrue);
      },
    );

    test(
      'health tool call returns error when HealthKit is unavailable',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        DeviceLocalTools.debugSetHealthDataAvailable(false);

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.healthSummary,
          const {},
          const Assistant(
            id: 'a1',
            name: 'Assistant',
            localToolIds: [LocalToolNames.healthSummary],
          ),
        );

        expect(result, isNotNull);
        expect(jsonDecode(result!) as Map<String, dynamic>, {
          'error': 'unsupported_os',
          'message': 'Health data is not available on this device.',
        });
      },
    );

    test('health tool description lists only selected metrics', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      DeviceLocalTools.debugSetHealthDataAvailable(true);

      final tools = LocalToolsService.buildToolDefinitions(
        assistant: const Assistant(
          id: 'a1',
          name: 'Assistant',
          localToolIds: [LocalToolNames.healthSummary],
          healthDataTypeIds: [HealthDataTypeIds.steps, HealthDataTypeIds.sleep],
        ),
        supportsTools: true,
      );

      expect(tools, hasLength(1));
      final description = tools.first['function']['description'] as String;
      expect(description, contains('steps'));
      expect(description, contains('sleep stages over the past 24 hours'));
      expect(description, contains('In-bed time is not actual sleep'));
      expect(description, contains('including naps and daytime sleep'));
      expect(description, contains('Missing states are unavailable, not zero'));
      expect(description, isNot(contains('blood glucose')));
      expect(description, isNot(contains('body weight')));
    });

    test(
      'health tool call sends configured types and ignores model args',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        DeviceLocalTools.debugSetHealthDataAvailable(true);

        const channel = MethodChannel('app.device_tools');
        String? capturedArgs;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getHealthSummary') {
                capturedArgs = call.arguments as String?;
                return jsonEncode({'updated_at': 'now'});
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final result = await LocalToolsService.tryHandleToolCall(
          LocalToolNames.healthSummary,
          const {
            'types': [HealthDataTypeIds.bloodGlucose],
          },
          const Assistant(
            id: 'a1',
            name: 'Assistant',
            localToolIds: [LocalToolNames.healthSummary],
            healthDataTypeIds: [
              HealthDataTypeIds.steps,
              HealthDataTypeIds.sleep,
            ],
          ),
        );

        expect(jsonDecode(result!) as Map<String, dynamic>, {
          'updated_at': 'now',
        });
        expect(capturedArgs, isNotNull);
        final payload = jsonDecode(capturedArgs!) as Map<String, dynamic>;
        expect(payload['types'], [
          HealthDataTypeIds.steps,
          HealthDataTypeIds.sleep,
        ]);
        expect(
          payload['types'],
          isNot(contains(HealthDataTypeIds.bloodGlucose)),
        );
      },
    );

    test('menstrual flow reaches native code only when selected', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      DeviceLocalTools.debugSetHealthDataAvailable(true);
      const channel = MethodChannel('app.device_tools');
      final queriedTypes = <List<dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getHealthSummary') {
              final args =
                  jsonDecode(call.arguments as String) as Map<String, dynamic>;
              queriedTypes.add(args['types'] as List<dynamic>);
              return '{}';
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const assistant = Assistant(
        id: 'a1',
        name: 'Assistant',
        localToolIds: [LocalToolNames.healthSummary],
        healthDataTypeIds: [HealthDataTypeIds.steps],
      );
      await LocalToolsService.tryHandleToolCall(
        LocalToolNames.healthSummary,
        const {
          'types': [HealthDataTypeIds.menstrualFlow],
        },
        assistant,
      );
      final selected = assistant.copyWith(
        healthDataTypeIds: [HealthDataTypeIds.menstrualFlow],
      );
      await LocalToolsService.tryHandleToolCall(
        LocalToolNames.healthSummary,
        const {},
        selected,
      );
      expect(queriedTypes, [
        [HealthDataTypeIds.steps],
        [HealthDataTypeIds.menstrualFlow],
      ]);
      final tool = LocalToolsService.buildToolDefinitions(
        assistant: selected,
        supportsTools: true,
      ).single;
      final description = tool['function']['description'] as String;
      expect(description, contains('recorded menstrual flow'));
      expect(description, contains('not predictions'));
      expect(description, contains('90 days'));
    });

    test(
      'enableAll requests HealthKit once for every available type',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        DeviceLocalTools.debugSetHealthDataAvailable(true);

        const channel = MethodChannel('app.device_tools');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'requestHealthPermission') return true;
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        const before = Assistant(id: 'a1', name: 'Assistant');
        final next = HealthDataSelection.enableAll(
          before,
          availableIds: DeviceLocalTools.availableHealthTypeIds,
        );
        final types = HealthDataSelection.queryTypes(
          next,
          availableIds: DeviceLocalTools.availableHealthTypeIds,
        );
        expect(types, HealthDataTypeIds.all);
        expect(HealthDataSelection.isMasterEnabled(next), isTrue);

        await DeviceLocalTools.requestHealthPermission(types: types);

        final permissionCalls = calls
            .where((call) => call.method == 'requestHealthPermission')
            .toList();
        expect(permissionCalls, hasLength(1));
        final payload =
            jsonDecode(permissionCalls.single.arguments as String)
                as Map<String, dynamic>;
        expect(payload['types'], HealthDataTypeIds.all);
      },
    );

    test('disabled or unknown local tool calls are not handled', () async {
      expect(
        await LocalToolsService.tryHandleToolCall(
          LocalToolNames.timeInfo,
          const {},
          const Assistant(id: 'a1', name: 'Assistant'),
        ),
        isNull,
      );
      expect(
        await LocalToolsService.tryHandleToolCall(
          'unknown_local_tool',
          const {},
          localToolsAssistant,
        ),
        isNull,
      );
    });
  });
}

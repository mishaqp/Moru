import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/tool_schema_normalizer.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/acp_moru_tools.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

class _ActionChat extends ChangeNotifier implements ChatService {
  _ActionChat(this.conversation);
  final Conversation conversation;

  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingActionDevice extends MiniAppDeviceService {
  final entered = Completer<void>();
  final release = Completer<void>();
  ToolCallCancellation? owner;
  bool cancellationDelivered = false;
  int writes = 0;

  @override
  Future<Map<String, dynamic>> snapshot() async => {
    'screen': {'brightness': 100},
  };

  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    owner = ToolCallCancellation.current;
    owner?.cancelled.then((_) => cancellationDelivered = true);
    entered.complete();
    await release.future;
    if (owner?.isCancelled() == true) return {'status': 'denied'};
    writes++;
    return {'status': 'applied'};
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late AssistantProvider assistants;
  late SettingsProvider settings;
  late McpProvider mcp;
  late McpToolService mcpTools;
  late Assistant assistant;
  late String actionName;
  final schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'count': {'type': 'integer', 'minimum': 0, 'maximum': 10},
      'note': {'type': 'string'},
    },
    'required': ['count'],
    'additionalProperties': false,
  };

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moru-action-tools-');
    store = MiniAppStore(root: () async => Directory('${temp.path}/apps'));
    final source = Directory('${temp.path}/source')..createSync();
    File('${source.path}/moru-app.json').writeAsStringSync(
      jsonEncode({
        'id': 'counter',
        'name': 'Counter',
        'formatVersion': 2,
        'ui': {'engine': 'native', 'entry': 'screen.json'},
        'permissions': ['actions.ai'],
        'actions': [
          {
            'name': 'set_count',
            'description': 'Set the count',
            'inputSchema': schema,
            'permissions': <String>[],
            'danger': 'write',
            'executor': {
              'kind': 'state',
              'patch': {
                'count': {r'$arg': 'count'},
              },
            },
          },
        ],
      }),
    );
    File(
      '${source.path}/screen.json',
    ).writeAsStringSync(jsonEncode({'version': 1, 'components': <Object>[]}));
    await store.install(source);
    runtime = MiniAppRuntime(store: store);
    final preferences = createBusinessTestPreferences();
    assistants = AssistantProvider(preferences: preferences);
    settings = SettingsProvider(preferences);
    mcp = McpProvider(preferences: preferences);
    mcpTools = McpToolService();
    await Future.wait([assistants.loaded, settings.loaded]);
    final id = await assistants.addAssistant(name: 'Caller');
    assistant = assistants
        .getById(id)!
        .copyWith(localToolIds: [LocalToolNames.miniApps]);
    await assistants.updateAssistant(assistant);
    actionName = MiniAppRuntime.toolNameFor('counter', 'set_count');
  });

  tearDown(() async {
    runtime.dispose();
    for (final provider in [store, assistants, settings, mcp, mcpTools]) {
      provider.dispose();
    }
    await temp.delete(recursive: true);
  });

  Future<ToolHandlerService> service(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<McpProvider>.value(value: mcp),
          ChangeNotifierProvider<McpToolService>.value(value: mcpTools),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    return ToolHandlerService(
      contextProvider: tester.element(find.byType(SizedBox)),
      miniAppRuntime: runtime,
    );
  }

  Map<String, dynamic> decode(Object? result) => result is String
      ? jsonDecode(result) as Map<String, dynamic>
      : Map<String, dynamic>.from(result! as Map);

  Future<ToolApprovalRequest> nextApproval(ToolApprovalService approvals) {
    final result = Completer<ToolApprovalRequest>();
    void changed() {
      if (approvals.pendingRequests.isNotEmpty && !result.isCompleted) {
        result.complete(approvals.pendingRequests.single);
      }
    }

    approvals.addListener(changed);
    changed();
    return result.future.whenComplete(() => approvals.removeListener(changed));
  }

  testWidgets(
    'actions use source schemas and the existing assistant switch',
    (tester) async {
      final handler = await service(tester);
      List<Map<String, dynamic>> definitions(Assistant selected) =>
          handler.buildToolDefinitions(
            settings,
            selected,
            'provider',
            'model',
            false,
            isToolModel: (_, _) => true,
          );
      final declared = definitions(
        assistant,
      ).singleWhere((d) => d['function']['name'] == actionName);
      expect(declared['function']['parameters'], schema);
      for (final target in ToolSchemaTarget.values) {
        final converted = normalizeToolSchema(schema, target).parameters;
        expect(converted, isNotEmpty);
        expect(declared['function']['parameters'], schema);
      }
      expect(
        definitions(
          assistant.copyWith(localToolIds: const []),
        ).map((d) => d['function']['name']),
        isNot(contains(actionName)),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'ACP action allowlist drops disabled and replaced offered actions',
    (tester) async {
      await service(tester);
      final chats = _ActionChat(
        Conversation(id: 'chat', title: 'Chat', assistantId: assistant.id),
      );
      addTearDown(chats.dispose);
      final tools = AcpMoruTools.create(
        context: tester.element(find.byType(SizedBox)),
        assistant: assistant,
        chats: chats,
        assistants: assistants,
        settings: settings,
        conversationId: 'chat',
        providerKey: 'provider',
        modelId: 'model',
        workspace: null,
        approvals: null,
        miniAppRuntime: runtime,
      );
      expect(tools.miniAppActionNames!(), contains(actionName));
      await tester.runAsync(() async {
        await assistants.updateAssistant(
          assistant.copyWith(localToolIds: const []),
        );
        expect(tools.miniAppActionNames!(), isEmpty);
        await assistants.updateAssistant(assistant);
        expect(tools.miniAppActionNames!(), contains(actionName));
        await store.install(Directory('${temp.path}/source'));
        expect(tools.miniAppActionNames!(), isEmpty);
        expect(
          (await tools.execute(actionName, {
            'count': 1,
          }, toolCallId: 'stale-acp'))['isError'],
          true,
        );
        expect(await store.storageAll('counter'), isEmpty);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'full trust bypasses confirmation without granting app rights',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await settings.setToolAutoApproveAll(true);
        final call = handler.buildToolCallHandler(settings, assistant)!;
        final denied = decode(await call(actionName, {'count': 4}));
        expect(denied['status'], 'permission_required');
        expect(await store.storageGet('counter', 'count'), isNull);
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final result = decode(
          await call(actionName, {'count': 4, 'note': null}),
        );
        expect(result['status'], 'applied');
        expect(await store.storageGet('counter', 'count'), 4);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'offered actions cannot execute replacement app code',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await settings.setToolAutoApproveAll(true);
        final offered = handler.captureMiniAppToolRoutes();
        final definitions = handler.buildToolDefinitions(
          settings,
          assistant,
          'provider',
          'model',
          false,
          isToolModel: (_, _) => true,
          miniAppRouteSnapshot: offered,
        );
        expect(
          definitions.map((d) => d['function']['name']),
          contains(actionName),
        );
        final manifestFile = File('${temp.path}/source/moru-app.json');
        final manifest =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        manifest['actions'][0]['executor']['patch'] = {
          'other': {r'$arg': 'count'},
        };
        await manifestFile.writeAsString(jsonEncode(manifest));
        await store.install(Directory('${temp.path}/source'));
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          miniAppRouteSnapshot: offered,
        )!;
        expect(
          decode(await call(actionName, {'count': 4}))['status'],
          'denied',
        );
        expect(await store.storageAll('counter'), isEmpty);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final source in [
    MiniAppInvocationSource.chat,
    MiniAppInvocationSource.acp,
  ]) {
    testWidgets(
      'disabling assistant mini apps cancels pending native work from ${source.name}',
      (tester) async {
        late _PendingActionDevice device;
        await tester.runAsync(() async {
          final manifestFile = File('${temp.path}/source/moru-app.json');
          final manifest =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          manifest['permissions'] = ['actions.ai', 'device.screen.write'];
          manifest['actions'] = [
            {
              'name': 'brightness',
              'description': 'Set brightness',
              'inputSchema': MiniAppDeviceService.inputSchemaFor(
                'device.screen.brightness.set',
              ),
              'permissions': ['device.screen.write'],
              'danger': 'write',
              'executor': {
                'kind': 'native',
                'handler': 'device.screen.brightness.set',
              },
            },
          ];
          await manifestFile.writeAsString(jsonEncode(manifest));
          await store.install(Directory('${temp.path}/source'));
          await runtime.dispose();
          device = _PendingActionDevice();
          runtime = MiniAppRuntime(store: store, device: device);
          await runtime.permissions.setGranted('counter', 'actions.ai', true);
          await runtime.permissions.setGranted(
            'counter',
            'device.screen.write',
            true,
          );
          await settings.setToolAutoApproveAll(true);
        });
        final handler = await service(tester);
        late Future<Object?> pending;
        var cancelled = false;
        await tester.runAsync(() async {
          final call = handler.buildToolCallHandler(
            settings,
            assistant,
            miniAppSource: source,
          )!;
          pending = call(MiniAppRuntime.toolNameFor('counter', 'brightness'), {
            'value': 90,
          });
          await Future.any<void>([
            device.entered.future,
            pending.then(
              (result) => throw StateError('Native entry failed: $result'),
            ),
          ]).timeout(const Duration(seconds: 5));
          try {
            await assistants.updateAssistant(
              assistant.copyWith(localToolIds: const []),
            );
            await Future<void>.delayed(Duration.zero);
            expect(device.owner, isNotNull);
            cancelled = device.cancellationDelivered;
          } finally {
            device.release.complete();
          }
        });
        await tester.pump();
        final result = await tester.runAsync(() => pending);
        expect(decode(result)['status'], 'denied');
        expect(device.writes, 0);
        expect(cancelled, true);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'AI and button actions publish the same app state',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await settings.setToolAutoApproveAll(true);
        final changes = <Map<String, dynamic>>[];
        final sub = runtime.changes.listen((c) => changes.add(c.state));
        try {
          final call = handler.buildToolCallHandler(settings, assistant)!;
          expect(
            decode(await call(actionName, {'count': 7}))['status'],
            'applied',
          );
          final fromAi = await store.storageAll('counter');
          expect(
            (await runtime.execute(
              'counter',
              'set_count',
              {'count': 7},
              invocation: const MiniAppInvocation(
                source: MiniAppInvocationSource.button,
              ),
            ))['status'],
            'applied',
          );
          expect(await store.storageAll('counter'), fromAi);
          await Future<void>.delayed(Duration.zero);
          expect(changes.length, greaterThanOrEqualTo(2));
          expect(changes.every((s) => s['data']['count'] == 7), true);
          final state = decode(
            await MiniAppDataTool(
              store: store,
              runtime: runtime,
              invocation: const MiniAppInvocation(
                source: MiniAppInvocationSource.chat,
              ),
            ).execute({'action': 'state', 'app_id': 'counter'}),
          );
          expect(state['data']['count'], 7);
        } finally {
          await sub.cancel();
        }
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'AI state results stay bounded without truncating app data',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await settings.setToolAutoApproveAll(true);
        final large = 'x' * (MiniAppDataTool.maxReadChars + 100);
        await store.storageSet('counter', 'large', large);
        final tool = MiniAppDataTool(
          store: store,
          runtime: runtime,
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.chat,
          ),
        );
        final read = await tool.execute({
          'action': 'state',
          'app_id': 'counter',
        });
        expect(read.length, lessThan(MiniAppDataTool.maxReadChars));
        final snapshot = decode(read);
        expect(snapshot['data_omitted'], true);
        expect(snapshot['data_keys'], contains('large'));
        final call = handler.buildToolCallHandler(settings, assistant)!;
        final result = await call(actionName, {'count': 2});
        expect(
          (result! as String).length,
          lessThan(MiniAppDataTool.maxReadChars),
        );
        expect(decode(result)['state']['data_omitted'], true);
        expect((await runtime.state('counter'))['data']['large'], large);
        expect(await store.storageGet('counter', 'large'), large);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'revoking the assistant tool while approval waits stops mutation',
    (tester) async {
      final handler = await service(tester);
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          approvalService: approvals,
          conversationId: 'chat',
        )!;
        final pending = call(actionName, {
          'count': 8,
        }, toolCallId: 'change-count');
        final request = await nextApproval(approvals);
        expect(request.arguments['app_id'], 'counter');
        expect(request.requiresExplicitConsent, true);
        await assistants.updateAssistant(
          assistant.copyWith(localToolIds: const []),
        );
        approvals.approve('change-count', conversationId: 'chat');
        expect(decode(await pending)['status'], 'denied');
        expect(await store.storageGet('counter', 'count'), isNull);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'denial and unavailable confirmation leave data unchanged',
    (tester) async {
      final handler = await service(tester);
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final without = handler.buildToolCallHandler(settings, assistant)!;
        expect(
          decode(await without(actionName, {'count': 3}))['status'],
          'permission_required',
        );
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          approvalService: approvals,
          conversationId: 'chat',
        )!;
        final pending = call(actionName, {'count': 3}, toolCallId: 'denied');
        await nextApproval(approvals);
        approvals.deny('denied', conversationId: 'chat');
        expect(decode(await pending)['status'], 'denied');
        expect(await store.storageGet('counter', 'count'), isNull);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'ACP source uses the same confirmation and live grant checks',
    (tester) async {
      final handler = await service(tester);
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          approvalService: approvals,
          conversationId: 'chat',
          miniAppSource: MiniAppInvocationSource.acp,
        )!;
        final pending = call(actionName, {'count': 6}, toolCallId: 'acp');
        await nextApproval(approvals);
        await runtime.permissions.setGranted('counter', 'actions.ai', false);
        approvals.approve('acp', conversationId: 'chat');
        expect(decode(await pending)['status'], 'permission_required');
        expect(await store.storageGet('counter', 'count'), isNull);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

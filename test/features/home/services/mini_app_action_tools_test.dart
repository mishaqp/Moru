import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
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
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/acp_moru_tools.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/tool_schema_contract.dart';

class _ActionChat extends ChangeNotifier implements ChatService {
  _ActionChat(this.conversation);
  Conversation conversation;

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
  late int publication;
  late WorkspaceToolsService publisher;
  late WorkspaceToolContext publishContext;
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
    publication = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    store = MiniAppStore(
      root: () async => Directory('${temp.path}/apps'),
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(publication++, isUtc: true),
    );
    final session = Directory('${temp.path}/session')..createSync();
    final skills = Directory('${temp.path}/skills')..createSync();
    publishContext = WorkspaceToolContext(
      workspace: Workspace(
        id: 'workspace',
        name: 'Workspace',
        kind: WorkspaceKind.managed,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      binding: const WorkspaceBinding(workspaceId: 'workspace'),
      paths: WorkspacePaths.native(
        workspaceHostRoot: temp.path,
        sessionHostDir: session.path,
        skillsHostDir: skills.path,
      ),
      sessionDir: session,
      outputsDir: Directory('${session.path}/outputs')..createSync(),
    );
    publisher = WorkspaceToolsService(miniApps: store);
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

  Map<String, dynamic> decode(Object? result) =>
      result is String || result is ClientToolResult
      ? jsonDecode(
              result is String ? result : (result as ClientToolResult).content,
            )
            as Map<String, dynamic>
      : Map<String, dynamic>.from(result! as Map);

  Map<String, dynamic> decodeAcp(Map<String, Object?> result) =>
      decode((result['content'] as List).single['text']);

  Future<Map<String, dynamic>> publishSource() async {
    final result = decode(
      await publisher.handle(
        publishContext,
        WorkspaceToolsService.miniAppTool,
        {'path': '${temp.path}/source'},
        toolCallId: 'publish-replacement',
      ),
    );
    expect(result['ok'], true, reason: jsonEncode(result));
    return result;
  }

  Future<Map<String, dynamic>> publishReplacement() async {
    final file = File('${temp.path}/source/moru-app.json');
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    manifest['actions'][0]['inputSchema'] = {
      'type': 'object',
      'properties': {
        'amount': {'type': 'integer', 'minimum': 0, 'maximum': 5},
      },
      'required': ['amount'],
      'additionalProperties': false,
    };
    manifest['actions'][0]['executor']['patch'] = {
      'count': {r'$arg': 'amount'},
    };
    (manifest['actions'] as List).add({
      'name': 'set_new',
      'description': 'Set the count with the new action',
      'inputSchema': schema,
      'permissions': <String>[],
      'danger': 'write',
      'executor': {
        'kind': 'state',
        'patch': {
          'count': {r'$arg': 'count'},
        },
      },
    });
    await file.writeAsString(jsonEncode(manifest));
    return publishSource();
  }

  Map<String, dynamic> invokeArgs(
    String name,
    Map<String, dynamic> arguments, {
    String? version,
  }) => {
    'action': 'invoke',
    'app_id': 'counter',
    'action_name': name,
    'arguments': jsonEncode(arguments),
    'version':
        version ?? MiniAppRuntime.actionVersionOf(store.byId('counter')!),
  };

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

  test('mini_apps invoke keeps source schemas compatible with providers', () {
    final definition = MiniAppDataTool.definition;
    final source = jsonEncode(definition);
    final properties =
        definition['function']['parameters']['properties'] as Map;
    expect(properties['action']['enum'], contains('invoke'));
    expect(properties['action_name']['type'], 'string');
    expect(properties['arguments']['type'], 'string');
    for (final target in ToolSchemaTarget.values) {
      final converted = normalizeToolDefinition(definition, target);
      final function = converted['function'] as Map;
      final parameters = function['parameters'] as Map;
      assertToolSchemaForProvider(
        parameters,
        target,
        strict: function['strict'] == true,
        path: 'mini_apps',
      );
      // JSON text avoids free/empty object schemas in provider definitions.
      expect(parameters['properties']['arguments']['type'], 'string');
    }
    expect(jsonEncode(definition), source);
  });

  testWidgets(
    'mini_apps list discovers versions and source action policy without grants',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        final call = handler.buildToolCallHandler(settings, assistant)!;
        final listed = decode(await call('mini_apps', {'action': 'list'}));
        final app = (listed['apps'] as List).single as Map;
        expect(
          app['version'],
          MiniAppRuntime.actionVersionOf(store.byId('counter')!),
        );
        final action = (app['actions'] as List).single as Map;
        expect(action['inputSchema'], schema);
        expect(action['permissions'], isEmpty);
        expect(action['danger'], 'write');
        expect(await runtime.permissions.granted('counter'), isEmpty);
        expect(await store.storageAll('counter'), isEmpty);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'same chat handler invokes newly published actions and rejects stale schemas',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await settings.setToolAutoApproveAll(true);
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final offered = handler.captureMiniAppToolRoutes();
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          miniAppRouteSnapshot: offered,
        )!;
        final oldVersion = MiniAppRuntime.actionVersionOf(
          store.byId('counter')!,
        );
        await publishReplacement();
        final listed = decode(await call('mini_apps', {'action': 'list'}));
        final app = (listed['apps'] as List).single as Map;
        final version = app['version'] as String;
        expect(version, isNot(oldVersion));
        expect(
          (app['actions'] as List).map((a) => a['name']),
          contains('set_new'),
        );
        expect(
          decode(await call(actionName, {'count': 4}))['status'],
          'denied',
        );
        final stale = decode(
          await call(
            'mini_apps',
            invokeArgs('set_count', {'count': 4}, version: oldVersion),
          ),
        );
        expect(stale['ok'], false);
        expect(stale['error'], 'app_changed');
        final oldSchema = decode(
          await call(
            'mini_apps',
            invokeArgs('set_count', {'count': 4}, version: version),
          ),
        );
        expect(oldSchema['status'], 'failed');
        expect(oldSchema['code'], 'invalid_arguments');
        expect(await store.storageAll('counter'), isEmpty);
        expect(
          decode(
            await call(
              'mini_apps',
              invokeArgs('set_count', {'amount': 3}, version: version),
            ),
          )['status'],
          'applied',
        );
        final invoked = decode(
          await call(
            'mini_apps',
            invokeArgs('set_new', {'count': 8}, version: version),
          ),
        );
        expect(invoked['status'], 'applied');
        expect(await store.storageGet('counter', 'count'), 8);
        expect(
          offered.names,
          isNot(contains(MiniAppRuntime.toolNameFor('counter', 'set_new'))),
        );
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'same-timestamp publication cannot reuse an action invocation version',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await settings.setToolAutoApproveAll(true);
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final call = handler.buildToolCallHandler(settings, assistant)!;
        final original = store.byId('counter')!;
        final listed = decode(await call('mini_apps', {'action': 'list'}));
        final oldVersion = (listed['apps'] as List).single['version'] as String;
        publication = original.updatedAt.millisecondsSinceEpoch;
        final file = File('${temp.path}/source/moru-app.json');
        final manifest =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        manifest['actions'][0]['executor']['patch'] = {
          'other': {r'$arg': 'count'},
        };
        await file.writeAsString(jsonEncode(manifest));
        await publishSource();
        expect(
          MiniAppStore.versionOf(store.byId('counter')!),
          MiniAppStore.versionOf(original),
        );
        final stale = decode(
          await call(
            'mini_apps',
            invokeArgs('set_count', {'count': 4}, version: oldVersion),
          ),
        );
        expect(stale['ok'], false);
        expect(stale['error'], 'app_changed');
        expect(await store.storageAll('counter'), isEmpty);
        final current = decode(await call('mini_apps', {'action': 'list'}));
        final newVersion =
            (current['apps'] as List).single['version'] as String;
        expect(newVersion, isNot(oldVersion));
        expect(
          decode(
            await call(
              'mini_apps',
              invokeArgs('set_count', {'count': 4}, version: newVersion),
            ),
          )['status'],
          'applied',
        );
        expect(await store.storageAll('counter'), {'other': 4});
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'same reply invokes actions after rollback and returning to the newer version',
    (tester) async {
      final handler = await service(tester);
      await tester.runAsync(() async {
        await settings.setToolAutoApproveAll(true);
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        final call = handler.buildToolCallHandler(settings, assistant)!;
        final initial = MiniAppStore.versionOf(store.byId('counter')!);
        await publishReplacement();
        final newer = MiniAppStore.versionOf(store.byId('counter')!);
        for (final target in [initial, newer]) {
          final rolledBack = decode(
            await call('mini_apps', {
              'action': 'rollback',
              'app_id': 'counter',
              'version': target,
            }),
          );
          expect(rolledBack['ok'], true);
          expect(rolledBack['restored'], target);
          final currentVersion = MiniAppRuntime.actionVersionOf(
            store.byId('counter')!,
          );
          expect(rolledBack['version'], currentVersion);
          final listing = decode(await call('mini_apps', {'action': 'list'}));
          expect((listing['apps'] as List).single['version'], currentVersion);
          final result = decode(
            await call(
              'mini_apps',
              invokeArgs(target == initial ? 'set_count' : 'set_new', {
                'count': target == initial ? 2 : 7,
              }, version: currentVersion),
            ),
          );
          expect(result['status'], 'applied');
          expect(
            await store.storageGet('counter', 'count'),
            target == initial ? 2 : 7,
          );
          expect(
            decode(await call(actionName, {'count': 1}))['status'],
            'denied',
          );
        }
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('publish result exposes the current invocation version', () async {
    final published = await publishReplacement();
    expect(
      published['version'],
      MiniAppRuntime.actionVersionOf(store.byId('counter')!),
    );
  });

  test(
    'invoke validates required fields and only accepts an AI runtime',
    () async {
      await runtime.permissions.setGranted('counter', 'actions.ai', true);
      final tool = MiniAppDataTool(
        store: store,
        runtime: runtime,
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.chat,
          fullTrust: () => true,
        ),
      );
      final valid = invokeArgs('set_count', {'count': 4});
      for (final key in ['app_id', 'action_name', 'arguments', 'version']) {
        for (final invalid in [null, 4, '']) {
          final result = decode(await tool.execute({...valid, key: invalid}));
          expect(result['ok'], false, reason: '$key=$invalid');
        }
        final missing = Map<String, dynamic>.of(valid)..remove(key);
        expect(decode(await tool.execute(missing))['ok'], false, reason: key);
      }
      expect(await store.storageAll('counter'), isEmpty);
      for (final source in [
        MiniAppInvocationSource.button,
        MiniAppInvocationSource.background,
        MiniAppInvocationSource.wifi,
      ]) {
        final result = decode(
          await MiniAppDataTool(
            store: store,
            runtime: runtime,
            invocation: MiniAppInvocation(
              source: source,
              fullTrust: () => true,
            ),
          ).execute(valid),
        );
        expect(result['ok'], false, reason: source.name);
        expect(result['error'], 'invocation_denied');
      }
      for (final tool in [
        MiniAppDataTool(store: store, runtime: runtime),
        MiniAppDataTool(
          store: store,
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.chat,
          ),
        ),
      ]) {
        final result = decode(await tool.execute(valid));
        expect(result['ok'], false);
        expect(result['error'], 'permission_required');
      }
      expect(await store.storageAll('counter'), isEmpty);
    },
  );

  test(
    'invoke accepts only bounded JSON text that decodes to an object',
    () async {
      await runtime.permissions.setGranted('counter', 'actions.ai', true);
      final tool = MiniAppDataTool(
        store: store,
        runtime: runtime,
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.chat,
          fullTrust: () => true,
        ),
      );
      final valid = invokeArgs('set_count', {'count': 4});
      for (final invalid in [
        {'count': 4},
        '{',
        '[]',
        'null',
        '4',
        'true',
        jsonEncode('text'),
        ' ' * (64 * 1024 + 1),
        jsonEncode({'note': '中' * (64 * 1024 ~/ 3), 'count': 4}),
      ]) {
        final result = decode(
          await tool.execute({...valid, 'arguments': invalid}),
        );
        expect(result['ok'], false);
        expect(result['error'], 'invalid_arguments');
        expect(await store.storageAll('counter'), isEmpty);
      }
      final result = decode(await tool.execute(valid));
      expect(result['status'], 'applied');
      expect(await store.storageAll('counter'), {'count': 4});
    },
  );

  testWidgets(
    'root DND approval retains effective policy and selected host operations',
    (tester) async {
      final handler = await service(tester);
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      await tester.runAsync(() async {
        final file = File('${temp.path}/source/moru-app.json');
        final manifest =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        manifest['permissions'] = ['actions.ai', 'device.root.dnd'];
        manifest['actions'][0] = {
          'name': 'set_count',
          'description': 'Quiet preset',
          'inputSchema': {'type': 'object', 'additionalProperties': false},
          'permissions': ['device.audio.write'],
          'danger': 'write',
          'executor': {
            'kind': 'preset',
            'steps': [
              {
                'handler': 'device.audio.dnd.set',
                'args': {'mode': 'priority'},
              },
            ],
          },
        };
        await file.writeAsString(jsonEncode(manifest));
        await publishSource();
        for (final permission in [
          'actions.ai',
          'device.audio.write',
          'device.root.dnd',
        ]) {
          await runtime.permissions.setGranted('counter', permission, true);
        }
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          approvalService: approvals,
          conversationId: 'chat',
        )!;
        final invocation = call(
          'mini_apps',
          invokeArgs('set_count', {}),
          toolCallId: 'root-dnd',
        );
        final approval = await nextApproval(approvals);
        try {
          expect(approval.arguments['danger'], 'root');
          expect(
            approval.arguments['permissions'],
            contains('device.root.dnd'),
          );
          expect(approval.arguments['root_dnd_operations'], [
            {
              'handler': 'device.root.dnd.set',
              'args': {'mode': 'priority'},
            },
          ]);
        } finally {
          approvals.deny('root-dnd', conversationId: 'chat');
          expect(decode(await invocation)['status'], 'denied');
        }
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final executor in <String, Map<String, dynamic>>{
    'empty restore': {'kind': 'restore'},
    'state': {
      'kind': 'state',
      'patch': {'count': 1},
    },
    'expression': {
      'kind': 'state',
      'expressions': true,
      'patch': {'count': 1},
    },
  }.entries) {
    testWidgets(
      'approval operation provenance for ${executor.key}',
      (tester) async {
        final handler = await service(tester);
        final approvals = ToolApprovalService();
        addTearDown(approvals.dispose);
        await tester.runAsync(() async {
          final file = File('${temp.path}/source/moru-app.json');
          final manifest =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          manifest['permissions'] = ['actions.ai', 'device.root.dnd'];
          manifest['actions'][0] = {
            'name': 'set_count',
            'description': 'Input operation fixture',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'operations': {'type': 'array'},
              },
              'additionalProperties': false,
            },
            'permissions': ['device.root.dnd'],
            'danger': 'root',
            'executor': executor.value,
          };
          await file.writeAsString(jsonEncode(manifest));
          await publishSource();
          for (final permission in ['actions.ai', 'device.root.dnd']) {
            await runtime.permissions.setGranted('counter', permission, true);
          }
          final modelOperations = [
            {
              'handler': 'device.root.dnd.set',
              'args': {'mode': 'none'},
            },
          ];
          final call = handler.buildToolCallHandler(
            settings,
            assistant,
            approvalService: approvals,
            conversationId: 'chat',
          )!;
          final invocation = call(
            'mini_apps',
            invokeArgs('set_count', {'operations': modelOperations}),
            toolCallId: 'input-operations',
          );
          final approval = await nextApproval(approvals);
          try {
            expect(
              approval.arguments.containsKey('root_dnd_operations'),
              isFalse,
            );
            expect(
              approval.arguments['arguments']['operations'],
              executor.key == 'empty restore' ? isEmpty : modelOperations,
            );
          } finally {
            approvals.deny('input-operations', conversationId: 'chat');
            expect(decode(await invocation)['status'], 'denied');
          }
        });
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'invoke uses app grants and action confirmation even with full trust available',
    (tester) async {
      final handler = await service(tester);
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      await tester.runAsync(() async {
        await settings.setToolAutoApproveAll(true);
        final call = handler.buildToolCallHandler(
          settings,
          assistant,
          approvalService: approvals,
          conversationId: 'chat',
        )!;
        final args = invokeArgs('set_count', {'count': 6});
        expect(
          decode(await call('mini_apps', args))['status'],
          'permission_required',
        );
        expect(approvals.pendingRequests, isEmpty);
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await settings.setToolAutoApproveAll(false);
        final without = handler.buildToolCallHandler(settings, assistant)!;
        expect(
          decode(await without('mini_apps', args))['status'],
          'permission_required',
        );
        final denied = call('mini_apps', args, toolCallId: 'deny-invoke');
        final approval = await nextApproval(approvals);
        expect(approval.toolName, actionName);
        expect(approval.requiresExplicitConsent, true);
        expect(approval.arguments['action'], 'set_count');
        expect(approval.arguments['arguments'], {'count': 6});
        approvals.deny('deny-invoke', conversationId: 'chat');
        expect(decode(await denied)['status'], 'denied');
        expect(await store.storageAll('counter'), isEmpty);
        final approved = call('mini_apps', args, toolCallId: 'approve-invoke');
        await nextApproval(approvals);
        approvals.approve('approve-invoke', conversationId: 'chat');
        expect(decode(await approved)['status'], 'applied');
        expect(await store.storageGet('counter', 'count'), 6);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'existing ACP tools invoke newly published actions in the same turn with bounded results',
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
      await tester.runAsync(() async {
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await settings.setToolAutoApproveAll(true);
        final oldVersion = MiniAppRuntime.actionVersionOf(
          store.byId('counter')!,
        );
        await publishReplacement();
        final discovered = decodeAcp(
          await tools.execute('mini_apps', {
            'action': 'list',
          }, toolCallId: 'discover-new'),
        );
        final current =
            (discovered['apps'] as List).single['version'] as String;
        expect(tools.miniAppActionNames!(), isEmpty);
        expect(
          (await tools.execute(actionName, {
            'count': 1,
          }, toolCallId: 'stale-offered'))['isError'],
          true,
        );
        expect(
          (await tools.execute(
            'mini_apps',
            invokeArgs('set_new', {'count': 8}, version: oldVersion),
            toolCallId: 'stale-version',
          ))['isError'],
          true,
        );
        final large = 'x' * (MiniAppDataTool.maxReadChars + 100);
        await store.storageSet('counter', 'large', large);
        final result = await tools.execute(
          'mini_apps',
          invokeArgs('set_new', {'count': 8}, version: current),
          toolCallId: 'invoke-new',
        );
        expect(result['isError'], false, reason: jsonEncode(result));
        final action = decodeAcp(result);
        expect(action['status'], 'applied');
        expect(action['state']['data_omitted'], true);
        expect(action['state'].containsKey('data'), false);
        expect(
          jsonEncode(action).length,
          lessThan(MiniAppDataTool.maxReadChars),
        );
        expect(await store.storageGet('counter', 'count'), 8);
        expect(await store.storageGet('counter', 'large'), large);
        await runtime.permissions.setGranted('counter', 'actions.ai', false);
        expect(
          (await tools.execute(
            'mini_apps',
            invokeArgs('set_new', {'count': 1}),
            toolCallId: 'revoked',
          ))['isError'],
          true,
        );
        await assistants.updateAssistant(
          assistant.copyWith(localToolIds: const []),
        );
        expect(
          (await tools.execute(
            'mini_apps',
            invokeArgs('set_new', {'count': 1}),
            toolCallId: 'disabled',
          ))['isError'],
          true,
        );
        expect(await store.storageGet('counter', 'count'), 8);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final invalidation in [
    'grant revoked',
    'assistant disabled',
    'chat switched',
    'app replaced',
  ]) {
    testWidgets(
      'ACP invoke stops when $invalidation while action approval waits',
      (tester) async {
        await service(tester);
        final approvals = ToolApprovalService();
        addTearDown(approvals.dispose);
        final chats = _ActionChat(
          Conversation(id: 'chat', title: 'Chat', assistantId: assistant.id),
        );
        addTearDown(chats.dispose);
        final owner = ToolApprovalOwner(
          conversationId: 'chat',
          generationRunId: 'turn',
          assistantMessageId: 'reply',
          isActive: () => chats.conversation.assistantId == assistant.id,
        );
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
          approvals: approvals,
          approvalOwner: owner,
          miniAppRuntime: runtime,
        );
        await tester.runAsync(() async {
          await runtime.permissions.setGranted('counter', 'actions.ai', true);
          final pending = tools.execute(
            'mini_apps',
            invokeArgs('set_count', {'count': 7}),
            toolCallId: 'pending-invoke',
          );
          final request = await Future.any([
            nextApproval(approvals),
            pending.then(
              (value) => throw StateError('Approval was not requested: $value'),
            ),
          ]);
          expect(request.arguments['source'], 'acp');
          expect(request.requiresExplicitConsent, true);
          if (invalidation == 'grant revoked') {
            await runtime.permissions.setGranted(
              'counter',
              'actions.ai',
              false,
            );
          } else if (invalidation == 'assistant disabled') {
            await assistants.updateAssistant(
              assistant.copyWith(localToolIds: const []),
            );
          } else if (invalidation == 'chat switched') {
            chats.conversation = chats.conversation.copyWith(
              assistantId: 'other',
            );
          } else {
            await publishReplacement();
          }
          approvals.approve('pending-invoke', conversationId: 'chat');
          final result = await pending;
          expect(result['isError'], true, reason: jsonEncode(result));
          expect(
            decodeAcp(result)['status'],
            invalidation == 'grant revoked' ? 'permission_required' : 'denied',
          );
          expect(await store.storageAll('counter'), isEmpty);
        });
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
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
    'sequence expressions behave identically through button, chat and ACP',
    (tester) async {
      await tester.runAsync(() async {
        final file = File('${temp.path}/source/moru-app.json');
        final manifest =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        (manifest['actions'] as List).addAll([
          {
            'name': 'increment',
            'description': 'Increment saved count',
            'inputSchema': {
              'type': 'object',
              'properties': {},
              'additionalProperties': false,
            },
            'permissions': <String>[],
            'danger': 'write',
            'executor': {
              'kind': 'state',
              'expressions': true,
              'patch': {
                'count': {r'$inc': 1},
              },
            },
          },
          {
            'name': 'set_then_increment',
            'description': 'Set then increment',
            'inputSchema': schema,
            'permissions': <String>[],
            'danger': 'write',
            'executor': {
              'kind': 'sequence',
              'steps': [
                {
                  'action': 'set_count',
                  'arguments': {
                    'count': {r'$arg': 'count'},
                  },
                },
                {'action': 'increment', 'arguments': <String, dynamic>{}},
              ],
            },
          },
        ]);
        for (final name in ['fail_after_sequence', 'fail_nested']) {
          (manifest['actions'] as List).add({
            'name': name,
            'description': 'Report a nested partial failure',
            'inputSchema': schema,
            'permissions': <String>[],
            'danger': 'write',
            'executor': {
              'kind': 'sequence',
              'steps': name == 'fail_nested'
                  ? [
                      {
                        'action': 'fail_after_sequence',
                        'arguments': {
                          'count': {r'$arg': 'count'},
                        },
                      },
                    ]
                  : [
                      {
                        'action': 'set_then_increment',
                        'arguments': {
                          'count': {r'$arg': 'count'},
                        },
                      },
                      {
                        'action': 'set_count',
                        'arguments': {'count': 99},
                      },
                    ],
            },
          });
        }
        await file.writeAsString(jsonEncode(manifest));
        await store.install(Directory('${temp.path}/source'));
        await runtime.permissions.setGranted('counter', 'actions.ai', true);
        await store.storageSet('counter', 'large', 'x' * 21000);
        await settings.setToolAutoApproveAll(true);
      });
      final handler = await service(tester);
      final chats = _ActionChat(
        Conversation(id: 'chat', title: 'Chat', assistantId: assistant.id),
      );
      addTearDown(chats.dispose);
      final acp = AcpMoruTools.create(
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
      await tester.runAsync(() async {
        final button = await runtime.execute(
          'counter',
          'set_then_increment',
          {'count': 2},
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.button,
          ),
        );
        expect(button['status'], 'applied');
        expect((button['completedSteps'] as List).length, 2);
        expect(await store.storageGet('counter', 'count'), 3);
        final name = MiniAppRuntime.toolNameFor(
          'counter',
          'set_then_increment',
        );
        final chat = decode(
          await handler.buildToolCallHandler(settings, assistant)!(name, {
            'count': 5,
          }),
        );
        expect(chat['status'], 'applied');
        expect((chat['completedSteps'] as List).length, 2);
        for (final evidence in chat['completedSteps'] as List) {
          expect(evidence['result']['state']['data_omitted'], true);
          expect(evidence['result']['state'].containsKey('data'), false);
        }
        expect(await store.storageGet('counter', 'count'), 6);
        final result = await acp.execute(name, {
          'count': 8,
        }, toolCallId: 'sequence-acp');
        expect(result['isError'], false, reason: jsonEncode(result));
        final content = result['content'] as List;
        final decoded =
            jsonDecode((content.single as Map)['text'] as String) as Map;
        expect(decoded['status'], 'applied');
        expect((decoded['completedSteps'] as List).length, 2);
        for (final evidence in decoded['completedSteps'] as List) {
          expect(evidence['result']['state']['data_omitted'], true);
          expect(evidence['result']['state'].containsKey('data'), false);
        }
        expect(await store.storageGet('counter', 'count'), 9);
        final failedName = MiniAppRuntime.toolNameFor('counter', 'fail_nested');
        final failedChat = decode(
          await handler.buildToolCallHandler(settings, assistant)!(failedName, {
            'count': 8,
          }),
        );
        final failedAcp = await acp.execute(failedName, {
          'count': 8,
        }, toolCallId: 'nested-failure');
        expect(failedAcp['isError'], true);
        final failedAcpResult =
            jsonDecode((failedAcp['content'] as List).single['text'] as String)
                as Map;
        for (final failed in [failedChat, failedAcpResult]) {
          expect(failed['status'], 'failed');
          expect(failed['partial'], true);
          for (final evidence in [
            failed['failedStep'],
            ...failed['failedSteps'] as List,
          ]) {
            final child = evidence['result']['completedSteps'][0]['result'];
            for (final completed in child['completedSteps'] as List) {
              expect(completed['result']['state']['data_omitted'], true);
              expect(completed['result']['state'].containsKey('data'), false);
            }
          }
          expect(
            jsonEncode(failed).length,
            lessThan(MiniAppDataTool.maxReadChars),
          );
        }
        expect(await store.storageGet('counter', 'large'), 'x' * 21000);
        await runtime.permissions.setGranted('counter', 'actions.ai', false);
        expect(
          decode(
            await handler.buildToolCallHandler(settings, assistant)!(name, {
              'count': 1,
            }),
          )['status'],
          'permission_required',
        );
        expect(
          (await acp.execute(name, {
            'count': 1,
          }, toolCallId: 'revoked-sequence'))['isError'],
          true,
        );
        expect(await store.storageGet('counter', 'count'), 9);
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

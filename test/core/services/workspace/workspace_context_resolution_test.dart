import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';

import '../../../support/fake_workspace_runtime.dart';

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Chats extends ChatService {
  _Chats(this.conversation);

  final Conversation conversation;

  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;
}

class _StatusRuntime extends FakeWorkspaceRuntime {
  _StatusRuntime({this.result, this.error});

  final RuntimeStatus? result;
  final Object? error;
  int statusCalls = 0;

  @override
  Future<RuntimeStatus> status() async {
    statusCalls++;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform previousPathProvider;
  late AppDatabase database;
  late WorkspaceProvider workspaces;
  late _Chats chats;
  late WorkspaceRuntimeProvider runtimes;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('moru_context_resolution_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProvider(root.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    database = AppDatabase(NativeDatabase.memory());
    workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
    await workspaces.loaded;
    final workspace = await workspaces.create(
      name: 'Project',
      kind: WorkspaceKind.linked,
      hostPath: root.path,
    );
    chats = _Chats(
      Conversation(
        id: 'conversation',
        title: 'Test',
        extras: WorkspaceBinding(workspaceId: workspace.id).applyTo({}),
      ),
    );
    runtimes = WorkspaceRuntimeProvider();
  });

  tearDown(() async {
    runtimes.dispose();
    chats.dispose();
    workspaces.dispose();
    await database.close();
    debugDefaultTargetPlatformOverride = null;
    PathProviderPlatform.instance = previousPathProvider;
    await root.delete(recursive: true);
  });

  Future<WorkspaceToolContext?> resolve() => WorkspaceToolsService.resolve(
    conversationId: chats.conversation.id,
    workspaceProvider: workspaces,
    runtimeProvider: runtimes,
    chatService: chats,
  );

  test('a failed registered runtime probe closes workspace tools', () async {
    final runtime = _StatusRuntime(
      error: PlatformException(
        code: 'probe_failed',
        message: 'runtime stopped',
      ),
    );
    runtimes.register(runtime);

    final context = await resolve();

    expect(runtime.statusCalls, 1);
    expect(context, isNull);
    expect(Directory('${root.path}/sessions').existsSync(), isFalse);
  });

  test('a successful sandbox probe retains guest paths and policy', () async {
    const status = RuntimeStatus(ready: true, engine: 'proot', sandboxed: true);
    runtimes.register(_StatusRuntime(result: status));

    final context = (await resolve())!;

    expect(context.runtimeStatus, same(status));
    expect(context.runtimeRegistered, isTrue);
    expect(context.paths.sandboxed, isTrue);
    expect(context.paths.modelRoot, '/workspace');
    expect(
      () => context.paths.resolve('/etc/passwd', cwd: context.cwd),
      throwsA(isA<PathResolutionException>()),
    );
  });

  test('an explicit native status keeps the runtime declared policy', () async {
    const status = RuntimeStatus(ready: true, engine: 'fake', sandboxed: false);
    runtimes.register(_StatusRuntime(result: status));

    final context = (await resolve())!;

    expect(context.runtimeStatus, same(status));
    expect(context.paths.sandboxed, isFalse);
    expect(context.paths.modelRoot, root.path);
  });
}

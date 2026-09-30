import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_chat_prompt.dart';
import 'package:Kelivo/core/services/acp/acp_chat_sessions.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_binding.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/home/services/acp_chat_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';

/// A scripted agent: answers initialize, session/new|load and every prompt
/// with one text chunk naming the session and the prompt text.
class _ScriptedAgent extends AcpChannel {
  _ScriptedAgent({
    this.loadSession = false,
    this.loadFails = false,
    this.resumeSession = false,
    this.resumeFails = false,
    this.images = false,
    this.mcpHttp = false,
  });

  final bool loadSession;
  final bool loadFails;
  final bool resumeSession;
  final bool resumeFails;
  final bool images;
  final bool mcpHttp;
  final _incoming = StreamController<dynamic>();
  final _closed = Completer<void>();
  final sent = <Map<String, Object?>>[];
  int sessions = 0;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  Future<void> get closed => _closed.future;

  bool get isClosed => _closed.isCompleted;

  @override
  Future<void> send(Map<String, Object?> message) async {
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(message)) as Map,
    );
    sent.add(copy);
    final id = copy['id'];
    final params = copy['params'] as Map? ?? const {};
    void reply(Object? result) => scheduleMicrotask(
      () => _incoming.add({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
    switch (copy['method']) {
      case 'initialize':
        reply({
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': loadSession,
            'sessionCapabilities': {
              if (resumeSession) 'resume': <String, Object?>{},
            },
            'promptCapabilities': {'image': images},
            'mcpCapabilities': {'http': mcpHttp},
          },
        });
      case 'session/new':
        reply({
          'sessionId': 'new-${++sessions}',
          'modes': {
            'currentModeId': 'ask',
            'availableModes': [
              {'id': 'ask', 'name': 'Ask'},
              {'id': 'code', 'name': 'Code'},
            ],
          },
        });
      case 'session/load':
      case 'session/resume':
        if (copy['method'] == 'session/load' ? loadFails : resumeFails) {
          scheduleMicrotask(
            () => _incoming.add({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32002, 'message': 'Session not found'},
            }),
          );
        } else {
          reply({
            'modes': {
              'currentModeId': 'ask',
              'availableModes': [
                {'id': 'ask', 'name': 'Ask'},
                {'id': 'code', 'name': 'Code'},
              ],
            },
          });
        }
      case 'session/set_mode':
        reply(<String, Object?>{});
      case 'session/prompt':
        final session = params['sessionId'];
        final text = [
          for (final block in params['prompt'] as List) (block as Map)['text'],
        ].join('|');
        scheduleMicrotask(() {
          _incoming
            ..add({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': session,
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': '$session:$text'},
                },
              },
            })
            ..add({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'stopReason': 'end_turn'},
            });
        });
    }
  }

  @override
  void close() {
    if (!_closed.isCompleted) _closed.complete();
    unawaited(_incoming.close());
  }
}

final class _ReadFailureOverrides extends IOOverrides {
  _ReadFailureOverrides(this.file);
  final File file;
  @override
  File createFile(String path) =>
      path == file.path ? _ReadFailureFile(file) : super.createFile(path);
}

class _ReadFailureFile implements File {
  _ReadFailureFile(this.file);
  final File file;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<Uint8List> readAsBytes() async =>
      throw FileSystemException('injected read failure', path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const provider = AcpProviderInput(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'k',
    model: 'deepseek-chat',
  );
  const imageProvider = AcpProviderInput(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'k',
    model: 'deepseek-chat',
    imageInput: true,
  );
  final spec = AcpAgentSpec.byId('opencode')!;

  late List<_ScriptedAgent> started;
  late List<({String cwd, List<Mount> mounts})> launches;

  AcpChatSessions sessionsWith({
    bool loadSession = false,
    bool loadFails = false,
    bool resumeSession = false,
    bool resumeFails = false,
    bool images = false,
    bool mcpHttp = false,
  }) {
    started = [];
    launches = [];
    return AcpChatSessions(
      start: (spec, provider, {required cwd, required mounts}) {
        launches.add((cwd: cwd, mounts: mounts));
        final channel = _ScriptedAgent(
          loadSession: loadSession,
          loadFails: loadFails,
          resumeSession: resumeSession,
          resumeFails: resumeFails,
          images: images,
          mcpHttp: mcpHttp,
        );
        started.add(channel);
        return AcpAgent.start(channel, clientVersion: '1');
      },
    );
  }

  AcpChatTurn turn(
    String text, {
    String conversation = 'c1',
    String? saved,
    String? mode,
    List<String> images = const [],
    String history = '',
    String cwd = '/workspace',
    AcpProviderInput? using,
    AcpAgentSpec? agentSpec,
    void Function(String)? onSession,
    AcpMcpTools? moruTools,
  }) => AcpChatTurn(
    conversationId: conversation,
    spec: agentSpec ?? spec,
    provider: using ?? provider,
    cwd: cwd,
    prompt: [
      if (text.isNotEmpty) {'type': 'text', 'text': text},
    ],
    history: history,
    savedSessionId: saved,
    savedModeId: mode,
    userImagePaths: images,
    imageNotSentMessage: "Image was not sent.",
    onSession: onSession,
    moruTools: moruTools,
  );

  Future<String> answer(AcpChatSessions sessions, AcpChatTurn turn) async {
    final chunks = await sessions.send(turn).toList();
    expect(chunks.last, isA<Finish>());
    return chunks.whereType<TextDelta>().map((c) => c.text).join();
  }

  for (final http in [true, false]) {
    for (final load in [true, false]) {
      test(
        'Moru MCP is sent on ${load ? 'load' : 'new'} (${http ? 'HTTP' : 'stdio'}) and closes with the process',
        () async {
          final sessions = sessionsWith(loadSession: load, mcpHttp: http);
          addTearDown(sessions.closeAll);
          final tools = AcpMcpTools(
            key: 'a',
            definitions: () => [],
            execute: (_, _, {required toolCallId}) async => {'content': []},
          );
          await answer(
            sessions,
            turn('hello', saved: load ? 'saved' : null, moruTools: tools),
          );
          final request = started.single.sent.singleWhere(
            (m) => m['method'] == (load ? 'session/load' : 'session/new'),
          );
          final config =
              ((request['params'] as Map)['mcpServers'] as List).single as Map;
          expect(config['name'], 'moru');
          final env = config['env'] as List?;
          final url = http
              ? config['url'] as String
              : (env!.first as Map)['value'] as String;
          final token = http
              ? ((config['headers'] as List).single as Map)['value'] as String
              : 'Bearer ${(env!.last as Map)['value']}';
          final client = HttpClient();
          addTearDown(client.close);
          final ping = await client.postUrl(Uri.parse(url));
          ping.headers.set('Authorization', token);
          ping.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}));
          final response = await ping.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
          // Process death (not only explicit close) owns server cleanup.
          started.single.close();
          final removed = Completer<void>();
          void changed() {
            if (!sessions.hasAgent('c1') && !removed.isCompleted) {
              removed.complete();
            }
          }

          sessions.addListener(changed);
          addTearDown(() => sessions.removeListener(changed));
          changed();
          await removed.future;
          // The listener closure is scheduled before its change notification.
          await expectLater(
            Socket.connect('127.0.0.1', Uri.parse(url).port),
            throwsA(isA<SocketException>()),
          );
        },
      );
    }
  }

  test('audio and video are never wrapped in image blocks', () async {
    final dir = Directory.systemTemp.createTempSync('acp-media-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = ['${dir.path}/video.mp4', '${dir.path}/audio.mp3'];
    for (final path in paths) {
      File(path).writeAsBytesSync([1, 2, 3]);
    }
    final sessions = sessionsWith(images: true);
    addTearDown(sessions.closeAll);
    await answer(sessions, turn('look', images: paths, using: imageProvider));
    final request = started.single.sent.lastWhere(
      (m) => m['method'] == 'session/prompt',
    );
    expect((request['params'] as Map)['prompt'], [
      {'type': 'text', 'text': 'look'},
    ]);
  });

  test(
    'an asynchronous file read failure leaves a note and still sends the prompt',
    () async {
      final dir = Directory.systemTemp.createTempSync('acp-read-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/photo.png')..writeAsBytesSync([1]);
      final sessions = sessionsWith(images: true);
      addTearDown(sessions.closeAll);
      await IOOverrides.runWithIOOverrides(
        () => answer(
          sessions,
          turn('look', images: [file.path], using: imageProvider),
        ),
        _ReadFailureOverrides(file),
      );
      final request = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((request['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'look'},
        {'type': 'text', 'text': 'Image was not sent.'},
      ]);
    },
  );

  test(
    'a mode update refreshes state and reapplies the saved mode next turn',
    () async {
      final sessions = sessionsWith();
      addTearDown(sessions.closeAll);
      await answer(sessions, turn('hi', mode: 'code'));
      final changed = Completer<void>();
      sessions.addListener(() {
        if (sessions.sessionFor('c1')?.currentModeId == 'ask' &&
            !changed.isCompleted) {
          changed.complete();
        }
      });
      started.single._incoming.add({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 'new-1',
          'update': {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'ask',
          },
        },
      });
      await changed.future.timeout(const Duration(seconds: 2));
      expect(sessions.sessionFor('c1')!.currentModeId, 'ask');
      await answer(sessions, turn('more', mode: 'code'));
      expect(
        started.single.sent.where((m) => m['method'] == 'session/set_mode'),
        hasLength(2),
      );
      expect(sessions.sessionFor('c1')!.currentModeId, 'code');
    },
  );

  test(
    'image capable agent receives the latest attachments as base64 blocks',
    () async {
      final dir = Directory.systemTemp.createTempSync('acp-images-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final png = File('${dir.path}/upload/photo.png');
      png.parent.createSync();
      png.writeAsBytesSync([137, 80, 78, 71]);
      final jpg = File('${dir.path}/upload/photo.jpg')
        ..writeAsBytesSync([255, 216, 255]);
      SandboxPathResolver.debugSetDirs(docsDir: dir.path);
      addTearDown(SandboxPathResolver.debugSetDirs);
      final sessions = sessionsWith(images: true);
      addTearDown(sessions.closeAll);
      await answer(
        sessions,
        turn(
          'look',
          images: ['kelivo-file:///upload/photo.png', jpg.uri.toString()],
          using: imageProvider,
        ),
      );
      final request = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((request['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'look'},
        {
          'type': 'image',
          'mimeType': 'image/png',
          'data': base64Encode(png.readAsBytesSync()),
        },
        {
          'type': 'image',
          'mimeType': 'image/jpeg',
          'data': base64Encode(jpg.readAsBytesSync()),
        },
      ]);
      await answer(sessions, turn('no images', using: imageProvider));
      final next = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((next['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'no images'},
      ]);
    },
  );

  test(
    'unsupported and unavailable images leave an explicit text note',
    () async {
      final dir = Directory.systemTemp.createTempSync('acp-unsupported-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final image = File('${dir.path}/photo.png')
        ..writeAsBytesSync([137, 80, 78, 71]);
      final sessions = sessionsWith();
      addTearDown(sessions.closeAll);
      await answer(
        sessions,
        turn('', images: [image.path], using: imageProvider),
      );
      final request = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((request['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'Image was not sent.'},
      ]);
      sessions.closeAll();
      final capable = sessionsWith(images: true);
      addTearDown(capable.closeAll);
      await answer(
        capable,
        turn(
          'look',
          images: ['/missing.png', 'https://example.com/private.png'],
          using: imageProvider,
        ),
      );
      final unavailable = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((unavailable['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'look'},
        {'type': 'text', 'text': 'Image was not sent.'},
      ]);
    },
  );

  test(
    'a text-only model receives a note even when the agent supports images',
    () async {
      final dir = Directory.systemTemp.createTempSync('acp-text-model-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final image = File('${dir.path}/photo.png')
        ..writeAsBytesSync([137, 80, 78, 71]);
      final sessions = sessionsWith(images: true);
      addTearDown(sessions.closeAll);
      await answer(sessions, turn('look', images: [image.path]));
      final request = started.single.sent.lastWhere(
        (m) => m['method'] == 'session/prompt',
      );
      expect((request['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'look'},
        {'type': 'text', 'text': 'Image was not sent.'},
      ]);
    },
  );

  test(
    'keeps modes and applies the saved mode before the next prompt',
    () async {
      final sessions = sessionsWith();
      addTearDown(sessions.closeAll);
      await answer(sessions, turn('hi'));
      expect(sessions.sessionFor('c1')!.modes.map((m) => m.id), [
        'ask',
        'code',
      ]);
      expect(sessions.sessionFor('c1')!.currentModeId, 'ask');
      await answer(sessions, turn('write', mode: 'code'));
      expect(sessions.sessionFor('c1')!.currentModeId, 'code');
      final sent = started.single.sent;
      final modeIndex = sent.indexWhere(
        (m) => m['method'] == 'session/set_mode',
      );
      expect(sent[modeIndex]['params'], {
        'sessionId': 'new-1',
        'modeId': 'code',
      });
      expect(sent[modeIndex + 1]['method'], 'session/prompt');
      await answer(sessions, turn('more', mode: 'code'));
      expect(
        sent.where((m) => m['method'] == 'session/set_mode'),
        hasLength(1),
      );
    },
  );

  test(
    'restores mode after loading or restarting and ignores unavailable modes',
    () async {
      final sessions = sessionsWith(loadSession: true);
      addTearDown(sessions.closeAll);
      await answer(sessions, turn('hi', saved: 'saved', mode: 'code'));
      expect(sessions.sessionFor('c1')!.id, 'saved');
      expect(sessions.sessionFor('c1')!.currentModeId, 'code');
      sessions.close('c1');
      expect(sessions.sessionFor('c1'), isNull);
      await answer(sessions, turn('again', mode: 'code'));
      expect(sessions.sessionFor('c1')!.currentModeId, 'code');
      await answer(sessions, turn('unknown', mode: 'removed'));
      expect(sessions.sessionFor('c1')!.currentModeId, 'code');
      expect(
        started.last.sent.where((m) => m['method'] == 'session/set_mode'),
        hasLength(1),
      );
    },
  );

  test('a chat keeps one agent and one session across turns', () async {
    final sessions = sessionsWith();
    final saved = <String>[];
    expect(
      await answer(
        sessions,
        turn('hi', history: 'User: old', onSession: saved.add),
      ),
      // A fresh session in a chat with history gets it first.
      'new-1:Earlier in this chat (for context, already answered):\n\n'
      'User: old\n\n---\n|hi',
    );
    expect(
      await answer(sessions, turn('more', history: 'ignored')),
      'new-1:more',
    );
    expect(started, hasLength(1));
    expect(saved, ['new-1']);
    expect(launches.single.cwd, '/workspace');
    expect(sessions.hasAgent('c1'), isTrue);

    // Another chat gets its own agent.
    expect(await answer(sessions, turn('x', conversation: 'c2')), 'new-1:x');
    expect(started, hasLength(2));
    sessions.closeAll();
    expect(started.every((agent) => agent.isClosed), isTrue);
  });

  test('a new model or folder starts a new agent', () async {
    final sessions = sessionsWith();
    await answer(sessions, turn('a'));
    await answer(
      sessions,
      turn(
        'b',
        using: const AcpProviderInput(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'k',
          model: 'deepseek-reasoner',
        ),
      ),
    );
    expect(started, hasLength(2));
    expect(started.first.isClosed, isTrue);
    await answer(sessions, turn('c', cwd: '/workspace/app'));
    expect(started, hasLength(3));
    sessions.closeAll();
  });

  test(
    'changing model image input restarts the agent with its new capabilities',
    () async {
      final sessions = sessionsWith(images: true);
      addTearDown(sessions.closeAll);
      await answer(sessions, turn('text only'));
      await answer(sessions, turn('images enabled', using: imageProvider));
      expect(started, hasLength(2));
      expect(started.first.isClosed, isTrue);
      await answer(
        sessions,
        turn('images still enabled', using: imageProvider),
      );
      expect(started, hasLength(2));
      await answer(sessions, turn('images disabled'));
      expect(started, hasLength(3));
      expect(started[1].isClosed, isTrue);
    },
  );

  test(
    'changing Kimi model context regenerates its agent configuration',
    () async {
      final sessions = sessionsWith();
      addTearDown(sessions.closeAll);
      final kimi = AcpAgentSpec.byId('kimi-code')!;
      await answer(sessions, turn('hi', agentSpec: kimi));
      await answer(
        sessions,
        turn(
          'more',
          agentSpec: kimi,
          using: const AcpProviderInput(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'k',
            model: 'deepseek-chat',
            contextWindow: 65536,
          ),
        ),
      );
      expect(started, hasLength(2));
      expect(started.first.isClosed, isTrue);
    },
  );

  test('a saved session is reopened when the agent can, with no history '
      'sent again', () async {
    final sessions = sessionsWith(loadSession: true);
    final saved = <String>[];
    expect(
      await answer(
        sessions,
        turn('hi', saved: 'old-7', history: 'User: old', onSession: saved.add),
      ),
      'old-7:hi',
    );
    expect(
      started.single.sent.map((m) => m['method']),
      containsAllInOrder(['initialize', 'session/load', 'session/prompt']),
    );
    expect(saved, isEmpty);
    sessions.closeAll();
  });

  test('a session the agent lost starts over with the history', () async {
    final sessions = sessionsWith(loadSession: true, loadFails: true);
    final saved = <String>[];
    final text = await answer(
      sessions,
      turn('hi', saved: 'gone', history: 'User: old', onSession: saved.add),
    );
    expect(text, startsWith('new-1:Earlier in this chat'));
    expect(saved, ['new-1']);
    sessions.closeAll();
  });

  test(
    'an agent advertising resume restores the saved session without history',
    () async {
      final sessions = sessionsWith(resumeSession: true);
      addTearDown(sessions.closeAll);
      final saved = <String>[];
      expect(
        await answer(
          sessions,
          turn(
            'hi',
            saved: 'old-7',
            history: 'User: old',
            onSession: saved.add,
          ),
        ),
        'old-7:hi',
      );
      final request = started.single.sent.singleWhere(
        (m) => m['method'] == 'session/resume',
      );
      expect(request['params'], {
        'sessionId': 'old-7',
        'cwd': '/workspace',
        'mcpServers': [],
      });
      expect(
        started.single.sent.where((m) => m['method'] == 'session/new'),
        isEmpty,
      );
      expect(saved, isEmpty);
      expect(sessions.sessionFor('c1')!.id, 'old-7');
    },
  );

  test(
    'load takes precedence when an agent supports both restore methods',
    () async {
      final sessions = sessionsWith(loadSession: true, resumeSession: true);
      addTearDown(sessions.closeAll);
      expect(await answer(sessions, turn('hi', saved: 'saved')), 'saved:hi');
      expect(
        started.single.sent.where((m) => m['method'] == 'session/load'),
        hasLength(1),
      );
      expect(
        started.single.sent.where((m) => m['method'] == 'session/resume'),
        isEmpty,
      );
    },
  );

  test(
    'a failed resume creates a session and supplies the chat history',
    () async {
      final sessions = sessionsWith(resumeSession: true, resumeFails: true);
      addTearDown(sessions.closeAll);
      final saved = <String>[];
      final text = await answer(
        sessions,
        turn('hi', saved: 'gone', history: 'User: old', onSession: saved.add),
      );
      expect(text, startsWith('new-1:Earlier in this chat'));
      expect(
        started.single.sent.map((m) => m['method']),
        containsAllInOrder(['session/resume', 'session/new', 'session/prompt']),
      );
      expect(saved, ['new-1']);
    },
  );

  test(
    'an agent with no restore capability creates a session with history',
    () async {
      final sessions = sessionsWith();
      addTearDown(sessions.closeAll);
      final text = await answer(
        sessions,
        turn('hi', saved: 'saved', history: 'User: old'),
      );
      expect(text, startsWith('new-1:Earlier in this chat'));
      expect(
        started.single.sent.where(
          (m) =>
              m['method'] == 'session/resume' || m['method'] == 'session/load',
        ),
        isEmpty,
      );
    },
  );

  for (final http in [true, false]) {
    test(
      'resume preserves Moru ${http ? 'HTTP' : 'stdio'} MCP binding',
      () async {
        final sessions = sessionsWith(resumeSession: true, mcpHttp: http);
        addTearDown(sessions.closeAll);
        final tools = AcpMcpTools(
          key: 'a',
          definitions: () => [],
          execute: (_, _, {required toolCallId}) async => {'content': []},
        );
        await answer(sessions, turn('hi', saved: 'saved', moruTools: tools));
        final request = started.single.sent.singleWhere(
          (m) => m['method'] == 'session/resume',
        );
        final config =
            ((request['params'] as Map)['mcpServers'] as List).single as Map;
        expect(config['name'], 'moru');
        expect(config.containsKey('url'), http);
        expect(config.containsKey('command'), !http);
      },
    );
  }

  test('an idle agent is stopped to free memory', () async {
    started = [];
    final sessions = AcpChatSessions(
      idleTimeout: const Duration(milliseconds: 20),
      start: (spec, provider, {required cwd, required mounts}) {
        final channel = _ScriptedAgent();
        started.add(channel);
        return AcpAgent.start(channel, clientVersion: '1');
      },
    );
    await answer(sessions, turn('hi'));
    expect(sessions.hasAgent('c1'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sessions.hasAgent('c1'), isFalse);
    expect(started.single.isClosed, isTrue);
  });

  test('the prompt is the newest user message; the history leaves out '
      'system prompts', () {
    final result = acpPromptFromMessages([
      {'role': 'system', 'content': 'You are Moru.'},
      {'role': 'user', 'content': 'Make a game'},
      {'role': 'assistant', 'content': 'Done: snake.html'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Make it faster'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AAAA'},
          },
        ],
      },
      {'role': 'assistant', 'content': ''},
    ]);
    expect(result.prompt, [
      {'type': 'text', 'text': 'Make it faster'},
    ]);
    expect(result.history, 'User: Make a game\n\nAssistant: Done: snake.html');
    expect(result.history, isNot(contains('Moru')));

    final long = acpPromptFromMessages([
      {'role': 'user', 'content': 'x' * 100},
      {'role': 'user', 'content': 'now'},
    ], historyLimit: 20);
    expect(long.history.length, 21);
    expect(long.history, startsWith('…'));
  });

  group('permission on the tool card', () {
    const request = AcpPermissionRequest(
      sessionId: 's',
      toolCallId: 'acp-tool-t1',
      title: 'rm -rf build',
      kind: 'execute',
      input: {'command': 'rm -rf build'},
      options: [
        AcpPermissionOption(id: 'always', name: 'Always', kind: 'allow_always'),
        AcpPermissionOption(id: 'once', name: 'Once', kind: 'allow_once'),
        AcpPermissionOption(id: 'no', name: 'No', kind: 'reject_once'),
      ],
    );

    test('Allow picks allow-once, Deny picks reject-once', () async {
      final approvals = ToolApprovalService();
      final allowed = AcpChatBridge.answerPermission(
        approvals,
        request,
        conversationId: 'c1',
      );
      final pending = approvals.pendingFor(
        toolCallId: 'acp-tool-t1',
        conversationId: 'c1',
      );
      expect(pending?.toolName, 'rm -rf build');
      expect(pending?.arguments['command'], 'rm -rf build');
      approvals.approve('acp-tool-t1', conversationId: 'c1');
      expect(await allowed, 'once');

      final denied = AcpChatBridge.answerPermission(
        approvals,
        request,
        conversationId: 'c1',
      );
      approvals.deny('acp-tool-t1', conversationId: 'c1');
      expect(await denied, 'no');
    });

    test('trusted mode allows without asking', () async {
      final approvals = ToolApprovalService()..setAutoApproveAll(true);
      expect(
        await AcpChatBridge.answerPermission(
          approvals,
          request,
          conversationId: 'c1',
        ),
        'once',
      );
      expect(approvals.hasPending, isFalse);
    });
  });
}

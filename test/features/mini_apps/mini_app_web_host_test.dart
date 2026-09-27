import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/keep_alive.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_servers.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/mini_app_web_host.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.keep_alive');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Directory temp;
  late SettingsProvider settings;
  late AssistantProvider assistants;
  late MiniAppWebHost host;
  late ProcessKeepAlive keepAlive;
  final environment = MiniAppServerEnvironment(
    runtime: () async => null,
    variables: () async => const {},
  );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    temp = await Directory.systemTemp.createTemp('mini-app-web-host-');
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    await assistants.loaded;
    keepAlive = ProcessKeepAlive(channel: channel);
    host = MiniAppWebHost(
      store: MiniAppStore(
        root: () async => Directory(p.join(temp.path, 'installed')),
      ),
      keepAlive: keepAlive,
      localAddresses: () async => const [],
    );
  });
  tearDown(() async {
    await host.stop();
    host.dispose();
    settings.dispose();
    assistants.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await temp.delete(recursive: true);
  });

  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> start() => host.start(
    settings: settings,
    assistants: assistants,
    environment: environment,
    notificationText: (url) => 'Web server: $url',
  );

  test('starts with a password, keeps Moru alive and stops cleanly', () async {
    final port = await freePort();
    await settings.setMiniAppWeb(port: port, password: 'pw');
    await start();
    expect(host.running, isTrue);
    expect(host.error, isNull);
    expect(host.urls, ['http://127.0.0.1:$port']);
    expect(calls.map((c) => c.method), ['hold']);
    expect(calls.single.arguments, {
      'id': MiniAppWebHost.keepAliveId,
      'text': 'Web server: http://127.0.0.1:$port',
    });

    // A raw request: the test binding stubs HttpClient out.
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.write(
      'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n'
      'Authorization: Basic ${base64.encode(utf8.encode('me:pw'))}\r\n\r\n',
    );
    final response = await utf8.decodeStream(socket);
    expect(response, startsWith('HTTP/1.1 200'));

    await host.stop();
    expect(host.running, isFalse);
    expect(calls.last.method, 'release');
  });

  test('stopping it from the notification stops the server', () async {
    await settings.setMiniAppWeb(port: await freePort(), password: 'pw');
    await start();
    final stopped = Completer<void>();
    host.addListener(() {
      if (!host.running && !stopped.isCompleted) stopped.complete();
    });
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('released', [MiniAppWebHost.keepAliveId]),
      ),
      (_) {},
    );
    await stopped.future.timeout(const Duration(seconds: 5));
    expect(host.running, isFalse);
  });

  test('a missing password or a busy port is explained', () async {
    await settings.setMiniAppWeb(port: await freePort(), password: '');
    await start();
    expect(host.running, isFalse);
    expect(host.error, MiniAppWebHost.errorNoPassword);

    final busy = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(busy.close);
    await settings.setMiniAppWeb(
      port: busy.port,
      password: 'pw',
      localhostOnly: false,
    );
    await start();
    expect(host.running, isFalse);
    expect(host.error, MiniAppWebHost.errorPortInUse);
    expect(calls, isEmpty);
  });
}

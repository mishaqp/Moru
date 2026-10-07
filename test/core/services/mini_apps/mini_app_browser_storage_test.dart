import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_browser_storage.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_browser_storage_state.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  final scripts = <String>[];
  late Directory temp;
  late MiniApp app;
  late FakeWebViewController fake;
  late MiniAppBrowserStorage storage;
  final origin = Uri.parse('https://moru-miniapp-old-game.invalid');
  final backend = Uri.parse('http://127.0.0.1:12345/token/app/old-game/');
  var failImport = false;

  Future<void> nativeEvent(String method, Map<String, Object?> args) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      MiniAppBrowserStorage.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) => done.complete(),
    );
    await done.future;
  }

  void reply(String script, {bool failImport = false}) {
    final phase = RegExp(r'\.sendToPopup\("([^"]+)"').firstMatch(script);
    if (phase == null) return;
    fake.emitChannelMessage(
      'MoruStorageMigration',
      jsonEncode({
        'nonce': phase[1],
        'type': failImport ? 'error' : 'complete',
        'value': 'import failed',
      }),
    );
  }

  setUp(() async {
    calls.clear();
    scripts.clear();
    failImport = false;
    installFakeWebViewPlatform();
    temp = await Directory.systemTemp.createTemp('mini-app-storage-transfer-');
    app = MiniApp(
      id: 'old-game',
      name: 'Game',
      directory: temp.path,
      updatedAt: DateTime.utc(2025),
    );
    await MiniAppBrowserStorageState.registerLegacy(app);
    final controller = WebViewController();
    fake = controller.platform as FakeWebViewController;
    fake.jsHandler = (script) {
      scripts.add(script.split('\n').last);
      return '';
    };
    storage = MiniAppBrowserStorage(
      controller: controller,
      app: app,
      origin: origin,
      nativeId: 42,
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: storage.pageFinished),
    );
    messenger.setMockMethodCallHandler(MiniAppBrowserStorage.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'loadLegacy') {
        await nativeEvent('legacyPageFinished', {
          'id': 42,
          'url': Uri.file(app.entryPath).toString(),
        });
      } else if (call.method == 'evaluateLegacy') {
        final script = (call.arguments as Map)['script'] as String;
        if (script.contains('window.__moruStorageTransfer.openPopup(')) {
          fake.simulateCommittedNavigation(
            origin.replace(path: MiniAppBrowserStorage.transferPath).toString(),
          );
        } else {
          reply(script, failImport: failImport);
        }
      }
      return call.method == 'attach' ? {'cookies': ''} : null;
    });
  });
  tearDown(() async {
    await storage.close();
    messenger.setMockMethodCallHandler(MiniAppBrowserStorage.channel, null);
    await temp.delete(recursive: true);
  });

  test(
    'failed imports retain source access for a retry before startup',
    () async {
      failImport = true;
      await expectLater(
        storage.prepare(backend: backend, ephemeral: false),
        throwsStateError,
      );
      var state = await MiniAppBrowserStorageState.read(app);
      expect(state.complete, isFalse);
      expect(fake.loadedUrls, [
        origin.replace(path: MiniAppBrowserStorage.transferPath).toString(),
      ]);
      expect(fake.javaScriptChannels, isNot(contains('MoruStorageMigration')));
      expect(
        scripts.where(
          (script) => script.contains('window.__moruStorageTransfer.receive('),
        ),
        everyElement(contains('"file://"')),
      );
      expect(calls, [
        'attach',
        'loadLegacy',
        'evaluateLegacy',
        'evaluateLegacy',
        'detach',
      ]);
      // Real popup creation requires a fresh, never-loaded WebView on retry.
      await storage.close();
      final controller = WebViewController();
      fake = controller.platform as FakeWebViewController;
      storage = MiniAppBrowserStorage(
        controller: controller,
        app: app,
        origin: origin,
        nativeId: 42,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: storage.pageFinished),
      );
      failImport = false;
      await storage.prepare(backend: backend, ephemeral: false);
      state = await MiniAppBrowserStorageState.read(app);
      expect(state.complete, isTrue);
      expect(fake.loadedUrls.where((url) => url.startsWith('file:')), isEmpty);
      expect(calls.last, 'finishMigration');
      expect(
        fake.loadedUrls,
        everyElement(endsWith(MiniAppBrowserStorage.transferPath)),
      );
    },
  );

  test(
    'closing during native attachment also removes a late attachment',
    () async {
      final attached = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(MiniAppBrowserStorage.channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'attach' ? attached.future : null;
      });
      final preparing = storage.prepare(backend: backend, ephemeral: false);
      final failed = expectLater(preparing, throwsStateError);
      for (var i = 0; i < 100 && !calls.contains('attach'); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(calls, ['attach']);
      await storage.close();
      attached.complete({'cookies': ''});
      await failed;
      expect(calls, ['attach', 'detach', 'detach']);
      expect((await MiniAppBrowserStorageState.read(app)).complete, isFalse);
      expect(fake.loadedUrls, ['about:blank']);
    },
  );
}

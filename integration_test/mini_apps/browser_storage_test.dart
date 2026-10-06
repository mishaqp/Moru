import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_browser_storage_state.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_local_session.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/utils/app_directories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

/// Android only. The default run seeds file://, upgrades a changed entry path,
/// and reopens on the stable origin. To check a genuine process restart, run
/// twice on the same installation with MORU_STORAGE_RESTART_PHASE=seed/verify,
/// force-stopping com.mishaqp.moru between the runs. Do not clear app data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('MORU_STORAGE_RESTART_PHASE');

  Future<Map<String, dynamic>> evaluate(
    WebViewController controller,
    String body,
  ) async {
    final done = Completer<Map<String, dynamic>>();
    await controller.addJavaScriptChannel(
      'StorageProbe',
      onMessageReceived: (message) {
        if (!done.isCompleted) {
          done.complete(
            Map<String, dynamic>.from(jsonDecode(message.message) as Map),
          );
        }
      },
    );
    try {
      await controller.runJavaScript(
        'Promise.resolve().then(async function () {$body}).then('
        'value => StorageProbe.postMessage(JSON.stringify(value)), '
        'error => StorageProbe.postMessage(JSON.stringify({error: String(error)})));',
      );
      final value = await done.future.timeout(const Duration(seconds: 30));
      expect(value, isNot(contains('error')));
      return value;
    } finally {
      await controller.removeJavaScriptChannel('StorageProbe');
    }
  }

  Future<({WebViewController controller, MiniAppLocalSession session})> open(
    MiniAppStore store,
    MiniApp app,
  ) async {
    final controller = WebViewController();
    final session = await MiniAppLocalSession.start(store: store, app: app);
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      final loaded = Completer<void>();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (session.pageFinished(url)) return;
            if (url == session.entryUri(app).toString() &&
                !loaded.isCompleted) {
              loaded.complete();
            }
          },
          onNavigationRequest: (request) =>
              session.allowsNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await session.prepare(controller);
      await controller.loadRequest(session.entryUri(app));
      await loaded.future.timeout(const Duration(seconds: 30));
      return (controller: controller, session: session);
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  testWidgets(
    'file storage migrates before startup and survives reopen/restart',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(phase, anyOf('', 'seed', 'verify'));
      await tester.runAsync(() async {
        final root = phase.isEmpty
            ? await Directory.systemTemp.createTemp('moru-browser-storage-')
            : Directory(
                p.join(
                  (await AppDirectories.getAppDataDirectory()).path,
                  '.browser-storage-integration',
                ),
              );
        final apps = Directory(p.join(root.path, 'apps'));
        var store = MiniAppStore(root: () async => apps);
        const id = 'browser-storage-fixture';
        const database = 'moru-browser-storage-fixture';
        const localKey = 'moru.browserStorageFixture.progress';
        const legacyCache = 'moru-browser-storage-fixture-legacy';
        const legacyAsset = 'https://moru-legacy-cache.invalid/sprite';
        final opaqueAddress = File(p.join(root.path, 'opaque-cache-url'));
        HttpServer? opaqueServer;
        ({WebViewController controller, MiniAppLocalSession session})? active;
        try {
          if (phase != 'verify') {
            opaqueServer = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            opaqueServer.listen((request) async {
              request.response.headers.set(
                HttpHeaders.cacheControlHeader,
                'no-store',
              );
              request.response.write('legacy opaque sprite');
              await request.response.close();
            });
            final opaqueUrl = 'http://127.0.0.1:${opaqueServer.port}/sprite';
            await opaqueAddress.parent.create(recursive: true);
            await opaqueAddress.writeAsString(opaqueUrl, flush: true);
            final source = Directory(p.join(root.path, 'source'));
            final legacyEntry = File(p.join(source.path, 'pages/legacy.html'));
            await legacyEntry.parent.create(recursive: true);
            await legacyEntry.writeAsString(
              '<!doctype html><body>Legacy game</body>',
            );
            final old = (await store.install(
              source,
              manifest: {
                'id': id,
                'name': 'Storage fixture',
                'entry': 'pages/legacy.html',
              },
            )).app;
            final legacy = WebViewController();
            await legacy.setJavaScriptMode(JavaScriptMode.unrestricted);
            final loaded = Completer<void>();
            await legacy.setNavigationDelegate(
              NavigationDelegate(
                onPageFinished: (_) {
                  if (!loaded.isCompleted) loaded.complete();
                },
              ),
            );
            await legacy.loadFile(old.entryPath);
            await loaded.future.timeout(const Duration(seconds: 30));
            await evaluate(legacy, '''
localStorage.setItem('$localKey', '9');
const db = await new Promise((resolve, reject) => {
  const r = indexedDB.open('$database', 3);
  r.onupgradeneeded = () => r.result.createObjectStore('save');
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
});
await new Promise((resolve, reject) => {
  const tx = db.transaction('save', 'readwrite');
  tx.objectStore('save').put({level: 9}, 'game');
  tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
}); db.close();
await (await caches.open('$legacyCache')).put('$legacyAsset', new Response('legacy sprite'));
const opaque = await fetch('$opaqueUrl', {mode: 'no-cors'});
if (opaque.type !== 'opaque') throw Error('Expected an opaque legacy response');
await (await caches.open('$legacyCache')).put('$opaqueUrl', opaque);
return {seeded: true};
''');
            // Migration must copy the hidden response body, never fetch it again.
            await opaqueServer.close(force: true);
            opaqueServer = null;
            await legacy.loadHtmlString('<!doctype html><html></html>');
            // Simulate installing this update over the previous loadFile release.
            await File(
              p.join(old.directory, MiniAppBrowserStorageState.fileName),
            ).delete();
            store.dispose();
            store = MiniAppStore(root: () async => apps);
            await store.load();
            final replacement = Directory(p.join(root.path, 'replacement'));
            await replacement.create(recursive: true);
            await File(p.join(replacement.path, 'index.html')).writeAsString(
              '<!doctype html><body><p>Game</p><script>'
              'document.body.dataset.progress = localStorage.getItem("$localKey");'
              '</script></body>',
            );
            await store.install(
              replacement,
              manifest: {'id': id, 'name': 'Storage fixture'},
            );
            expect(await File(old.entryPath).exists(), isFalse);
            active = await open(store, store.byId(id)!);
            final restored = await evaluate(active.controller, '''
const db = await new Promise((resolve, reject) => {
  const r = indexedDB.open('$database', 3);
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
});
const save = await new Promise(resolve => {
  const r = db.transaction('save').objectStore('save').get('game');
  r.onsuccess = () => resolve(r.result);
}); db.close();
const opaque = await (await caches.open('$legacyCache')).match('$opaqueUrl');
return {firstScript: document.body.dataset.progress, local: localStorage.getItem('$localKey'), level: save.level, oldCache: await (await (await caches.open('$legacyCache')).match('$legacyAsset')).text(), opaqueType: opaque.type, opaqueStatus: opaque.status};
''');
            expect(restored, {
              'firstScript': '9',
              'local': '9',
              'level': 9,
              'oldCache': 'legacy sprite',
              'opaqueType': 'opaque',
              'opaqueStatus': 0,
            });
            await evaluate(active.controller, '''
localStorage.setItem('$localKey', '10');
const db = await new Promise(resolve => { const r = indexedDB.open('$database'); r.onsuccess = () => resolve(r.result); });
await new Promise((resolve, reject) => {
  const tx = db.transaction('save', 'readwrite'); tx.objectStore('save').put({level: 10}, 'game');
  tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
}); db.close();
document.cookie = 'game=10; Max-Age=86400; Secure; Path=/';
await (await caches.open('game')).put('/sprite', new Response('saved sprite'));
return {saved: true};
''');
            await active.session.close();
            active = null;
          }
          // A new controller, MiniAppStore and loopback server. In verify mode
          // this also runs in a newly started Android application process.
          store.dispose();
          store = MiniAppStore(root: () async => apps);
          await store.load();
          expect(store.byId(id), isNotNull);
          active = await open(store, store.byId(id)!);
          final opaqueUrl = await opaqueAddress.readAsString();
          final persisted = await evaluate(active.controller, '''
const db = await new Promise(resolve => { const r = indexedDB.open('$database'); r.onsuccess = () => resolve(r.result); });
const save = await new Promise(resolve => { const r = db.transaction('save').objectStore('save').get('game'); r.onsuccess = () => resolve(r.result); }); db.close();
const opaque = await (await caches.open('$legacyCache')).match('$opaqueUrl');
return {local: localStorage.getItem('$localKey'), level: save.level, cookie: document.cookie, cache: await (await (await caches.open('game')).match('/sprite')).text(), opaqueType: opaque.type, opaqueStatus: opaque.status};
''');
          expect(persisted, {
            'local': '10',
            'level': 10,
            'cookie': 'game=10',
            'cache': 'saved sprite',
            'opaqueType': 'opaque',
            'opaqueStatus': 0,
          });
          // ignore: avoid_print
          print(
            'MORU_ANDROID_BROWSER_STORAGE:${phase.isEmpty ? 'upgrade-and-reopen' : phase}:passed',
          );
        } finally {
          await opaqueServer?.close(force: true);
          await active?.session.close();
          store.dispose();
          if (phase != 'seed' && await root.exists()) {
            await root.delete(recursive: true);
          }
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

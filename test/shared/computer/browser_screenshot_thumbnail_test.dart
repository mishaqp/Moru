import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_thumbnail_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webview_flutter/webview_flutter.dart';

import '../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;
  final cache = BrowserThumbnailCache.instance;
  late Directory directory;

  setUp(() async {
    installFakeWebViewPlatform();
    cache.clear();
    directory = await Directory.systemTemp.createTemp('computer-browser-shot');
    final originalCapture = session.captureBytes;
    final originalDirectory = session.screenshotDirectory;
    final originalVisit = session.onVisit;
    session.onVisit = (_, _) {};
    addTearDown(() {
      session.captureBytes = originalCapture;
      session.screenshotDirectory = originalDirectory;
      session.onVisit = originalVisit;
    });
    session.screenshotDirectory = () async => directory;
  });
  tearDown(() async {
    cache.clear();
    await directory.delete(recursive: true);
  });

  Future<void> attach(String url) async {
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));
    await session.load(Uri.parse(url));
    FakeWebViewPlatform.lastCreated!.jsHandler = (script) =>
        script.contains('innerWidth')
        ? jsonEncode({'width': 412, 'height': 800})
        : jsonEncode({'ok': true, 'url': url});
  }

  test(
    'thumbnail belongs to the starting conversation after an owner switch',
    () async {
      await attach('https://example.com');
      session.setOwnerConversationId('chat-a');
      final activity = session.recordActivity(action: 'screenshot');
      final sourceBytes = img.encodeJpg(img.Image(width: 960, height: 600));
      final writingStarted = Completer<void>();
      final releaseWriting = Completer<void>();
      session.captureBytes = (_) async => sourceBytes;
      session.screenshotDirectory = () async {
        writingStarted.complete();
        await releaseWriting.future;
        return directory;
      };
      final pending = session.screenshot();
      await writingStarted.future;
      session.setOwnerConversationId('chat-b');
      await session.controller!.loadRequest(
        Uri.parse('https://other.example.com'),
      );
      releaseWriting.complete();
      final result = await pending;
      expect(result['ok'], isTrue);
      expect(result['url'], 'https://example.com');
      expect(result['viewport'], {'width': 412, 'height': 800});
      expect(
        await File(result['screenshot'] as String).readAsBytes(),
        sourceBytes,
      );
      expect(cache.forStep('chat-a', activity), isNotNull);
      expect(cache.latestIn('chat-a')!.width, 480);
      expect(cache.latestIn('chat-b'), isNull);
    },
  );

  test(
    'a takeover during readiness never captures the next chat page',
    () async {
      await attach('https://example.com');
      session.setOwnerConversationId('chat-a');
      session.recordActivity(action: 'screenshot');
      session.pageStarted('https://example.com');
      var captures = 0;
      session.captureBytes = (_) async {
        captures++;
        return img.encodeJpg(img.Image(width: 60, height: 90));
      };
      final pending = session.screenshot();
      final stopped = expectLater(
        pending,
        throwsA(isA<BrowserStoppedException>()),
      );
      session.setOwnerConversationId('chat-b');
      session.recordActivity(action: 'open');
      await session.controller!.loadRequest(
        Uri.parse('https://other.example.com'),
      );
      await stopped;
      expect(captures, 0);
      expect(cache.latestIn('chat-a'), isNull);
      expect(cache.latestIn('chat-b'), isNull);
    },
  );

  test(
    'a takeover during native capture discards the changed page bytes',
    () async {
      await attach('https://example.com');
      session.setOwnerConversationId('chat-a');
      session.recordActivity(action: 'screenshot');
      final captureStarted = Completer<void>();
      final releaseCapture = Completer<void>();
      session.captureBytes = (_) async {
        captureStarted.complete();
        await releaseCapture.future;
        return img.encodeJpg(img.Image(width: 60, height: 90));
      };
      final pending = session.screenshot();
      final stopped = expectLater(
        pending,
        throwsA(isA<BrowserStoppedException>()),
      );
      await captureStarted.future;
      session.setOwnerConversationId('chat-b');
      session.recordActivity(action: 'open');
      await session.controller!.loadRequest(
        Uri.parse('https://other.example.com'),
      );
      releaseCapture.complete();
      await stopped;
      expect(cache.latestIn('chat-a'), isNull);
      expect(cache.latestIn('chat-b'), isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
    },
  );

  test(
    'a delayed older screenshot file cannot replace the newer native preview',
    () async {
      await attach('https://example.com');
      session.setOwnerConversationId('chat');
      final olderActivity = session.recordActivity(action: 'screenshot');
      final writingStarted = Completer<void>();
      final releaseWriting = Completer<void>();
      var writes = 0;
      session.screenshotDirectory = () async {
        if (writes++ == 0) {
          writingStarted.complete();
          await releaseWriting.future;
        }
        return directory;
      };
      session.captureBytes = (_) async =>
          img.encodeJpg(img.Image(width: 60, height: 90));
      final older = session.screenshot();
      await writingStarted.future;
      final newerActivity = session.recordActivity(action: 'screenshot');
      final newer = await session.screenshot();
      final latest = cache.latestIn('chat');
      expect(latest?.stepId, newerActivity);
      expect(latest?.sourcePath, newer['screenshot']);
      releaseWriting.complete();
      final olderResult = await older;
      expect(
        cache.forStep('chat', olderActivity)?.sourcePath,
        olderResult['screenshot'],
      );
      expect(cache.latestIn('chat'), same(latest));
    },
  );

  test(
    'auth page screenshot result stays original and is not cached for display',
    () async {
      const url = 'https://auth.openai.com/authorize?code=private-code';
      await attach(url);
      session.setOwnerConversationId('auth-chat');
      session.recordActivity(action: 'screenshot');
      final sourceBytes = img.encodeJpg(img.Image(width: 120, height: 200));
      session.captureBytes = (_) async => sourceBytes;
      final result = await session.screenshot();
      expect(result['ok'], isTrue);
      expect(result['url'], url);
      expect(
        await File(result['screenshot'] as String).readAsBytes(),
        sourceBytes,
      );
      expect(cache.latestIn('auth-chat'), isNull);
    },
  );
}

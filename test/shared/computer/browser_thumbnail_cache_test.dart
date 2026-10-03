import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_thumbnail_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BrowserThumbnailCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('computer-thumbnails');
    cache = BrowserThumbnailCache();
  });
  tearDown(() async {
    cache.dispose();
    await dir.delete(recursive: true);
  });

  Future<File> picture(String name, {int width = 60, int height = 90}) => File(
    '${dir.path}/shot-$name.jpg',
  ).writeAsBytes(img.encodeJpg(img.Image(width: width, height: height)));

  test(
    'reduces a real screenshot to a bounded JPEG without changing its source',
    () async {
      final file = await picture('large', width: 1200, height: 600);
      final original = await file.readAsBytes();
      final thumbnail = await cache.capture(
        conversationId: 'chat-a',
        stepId: 'open',
        sourcePath: file.path,
        sourceDirectory: dir,
        pageUrl: 'https://example.com',
      );
      expect(thumbnail, isNotNull);
      expect(thumbnail!.width, 480);
      expect(thumbnail.height, 240);
      expect(
        thumbnail.bytes.length,
        lessThanOrEqualTo(BrowserThumbnailCache.maxEncodedBytes),
      );
      expect(img.decodeJpg(thumbnail.bytes)!.width, 480);
      expect(await file.readAsBytes(), original);
      expect(cache.forStep('chat-a', 'open'), same(thumbnail));
      expect(cache.forSource('chat-a', file.path), same(thumbnail));
    },
  );

  test(
    'keeps only the newest 24 pictures in each chat and isolates fallback',
    () async {
      final file = await picture('small');
      for (var i = 0; i < 25; i++) {
        await cache.capture(
          conversationId: 'chat-a',
          stepId: 'step-$i',
          sourcePath: file.path,
          sourceDirectory: dir,
        );
      }
      final other = await cache.capture(
        conversationId: 'chat-b',
        stepId: 'other',
        sourcePath: file.path,
        sourceDirectory: dir,
      );
      expect(cache.forStep('chat-a', 'step-0'), isNull);
      expect(cache.forStep('chat-a', 'step-1'), isNotNull);
      expect(cache.latestIn('chat-a')!.stepId, 'step-24');
      expect(cache.latestIn('chat-b'), same(other));
      expect(cache.latestIn('missing-chat'), isNull);
      expect(cache.latestIn(null), isNull);
      expect(cache.forStep('chat-b', 'step-24'), isNull);
      cache.clearConversation('chat-a');
      expect(cache.latestIn('chat-a'), isNull);
      expect(cache.latestIn('chat-b'), same(other));
    },
  );

  test(
    'auth pages cannot create previews or displace the last safe screenshot',
    () async {
      final file = await picture('auth');
      final safe = await cache.capture(
        conversationId: 'chat',
        stepId: 'safe',
        sourcePath: file.path,
        sourceDirectory: dir,
        pageUrl: 'https://example.com',
      );
      final rejected = await cache.capture(
        conversationId: 'chat',
        stepId: 'auth',
        sourcePath: file.path,
        sourceDirectory: dir,
        pageUrl: 'https://auth.openai.com/authorize?code=private-code',
      );
      expect(rejected, isNull);
      final opaque = await cache.capture(
        conversationId: 'chat',
        stepId: 'opaque-auth',
        sourcePath: file.path,
        sourceDirectory: dir,
        pageUrl: '■',
      );
      expect(opaque, isNull);
      expect(cache.forStep('chat', 'auth'), isNull);
      expect(cache.latestIn('chat'), same(safe));
    },
  );

  test(
    'restored history stays exact without replacing a native fallback',
    () async {
      final newerFile = await picture('native');
      final olderFile = await picture('history');
      final native = await cache.capture(
        conversationId: 'chat',
        stepId: 'native',
        sourcePath: newerFile.path,
        sourceDirectory: dir,
      );
      final history = await cache.capture(
        conversationId: 'chat',
        stepId: 'history',
        sourcePath: olderFile.path,
        sourceDirectory: dir,
        historical: true,
      );
      expect(history, isNotNull);
      expect(cache.forStep('chat', 'history'), same(history));
      expect(cache.forSource('chat', olderFile.path), same(history));
      expect(cache.latestIn('chat'), same(native));
    },
  );

  test('fallback belongs to the step page and capture time', () async {
    final file = await picture('owned-page');
    final capturedAt = DateTime.utc(2026, 10, 3, 12);
    final thumbnail = await cache.capture(
      conversationId: 'chat',
      stepId: 'activity',
      sourcePath: file.path,
      sourceDirectory: dir,
      pageUrl: 'https://ya.ru/search',
      pageKey: 'yandex-page',
      capturedAt: capturedAt,
    );
    expect(thumbnail!.pageUrl, 'https://ya.ru/search');
    expect(thumbnail.pageKey, 'yandex-page');
    expect(thumbnail.capturedAt, capturedAt);
    expect(
      cache.previewForStep(
        'chat',
        pageUrl: 'https://ya.ru',
        startedAt: capturedAt,
      ),
      same(thumbnail),
    );
    expect(
      cache.previewForStep(
        'chat',
        activityId: 'activity',
        pageUrl: 'https://ya.ru/search',
        pageKey: 'yandex-page',
        startedAt: capturedAt,
      ),
      same(thumbnail),
    );
    for (final invalid in [
      (page: 'https://wttr.in', key: null, start: capturedAt),
      (page: 'https://ya.ru', key: 'another-page', start: capturedAt),
      (
        page: 'https://ya.ru',
        key: null,
        start: capturedAt.add(const Duration(seconds: 1)),
      ),
      (page: 'https://ya.ru', key: null, start: null),
      (page: null, key: null, start: capturedAt),
      (
        page: 'https://ya.ru/?access_token=private',
        key: null,
        start: capturedAt,
      ),
    ]) {
      expect(
        cache.previewForStep(
          'chat',
          activityId: 'activity',
          pageUrl: invalid.page,
          pageKey: invalid.key,
          startedAt: invalid.start,
        ),
        isNull,
      );
    }
    expect(
      cache.previewForStep(
        'other-chat',
        pageUrl: 'https://ya.ru',
        startedAt: capturedAt,
      ),
      isNull,
    );
  });

  test(
    'restored source stays exact but cannot become a recent fallback',
    () async {
      final file = await picture('restored-page');
      final thumbnail = await cache.capture(
        conversationId: 'chat',
        stepId: 'restored',
        sourcePath: file.path,
        sourceDirectory: dir,
        pageUrl: 'https://ya.ru',
        historical: true,
      );
      expect(thumbnail!.capturedAt, isNull);
      expect(
        cache.previewForStep('chat', sourcePath: file.path),
        same(thumbnail),
      );
      expect(
        cache.previewForStep(
          'chat',
          activityId: 'restored',
          pageUrl: 'https://ya.ru',
          startedAt: DateTime.utc(2020),
        ),
        isNull,
      );
    },
  );

  test(
    'a restored preview remains available at capacity beside native latest',
    () async {
      final file = await picture('capacity');
      for (var i = 0; i < BrowserThumbnailCache.maxEntriesPerChat; i++) {
        await cache.capture(
          conversationId: 'chat',
          stepId: 'native-$i',
          sourcePath: file.path,
          sourceDirectory: dir,
        );
      }
      final native = cache.latestIn('chat');
      for (var i = 0; i < BrowserThumbnailCache.maxEntriesPerChat; i++) {
        final restored = await cache.capture(
          conversationId: 'chat',
          stepId: 'historical-$i',
          sourcePath: file.path,
          sourceDirectory: dir,
          historical: true,
        );
        expect(cache.forStep('chat', 'historical-$i'), same(restored));
        expect(cache.latestIn('chat'), same(native));
      }
      expect(cache.forStep('chat', 'native-0'), isNull);
      expect(cache.forStep('chat', 'historical-0'), isNull);
      expect(cache.forStep('chat', 'historical-1'), isNotNull);
    },
  );

  test(
    'overlapping history reduction cannot replace pending native latest',
    () async {
      final nativeFile = await picture(
        'pending-native',
        width: 1200,
        height: 900,
      );
      final historyFile = await picture('pending-history');
      final native = cache.capture(
        conversationId: 'chat',
        stepId: 'native',
        sourcePath: nativeFile.path,
        sourceDirectory: dir,
      );
      final history = cache.capture(
        conversationId: 'chat',
        stepId: 'history',
        sourcePath: historyFile.path,
        sourceDirectory: dir,
        historical: true,
      );
      final results = await Future.wait([native, history]);
      expect(results.every((result) => result != null), isTrue);
      expect(cache.forStep('chat', 'history'), same(results[1]));
      expect(cache.latestIn('chat'), same(results[0]));
    },
  );

  test('delayed disk ingestion keeps native snapshot order', () async {
    final olderSequence = cache.reserveCaptureSequence();
    final newerSequence = cache.reserveCaptureSequence();
    final file = await picture('delayed-disk');
    final newer = await cache.capture(
      conversationId: 'chat',
      stepId: 'newer',
      sourcePath: file.path,
      sourceDirectory: dir,
      captureSequence: newerSequence,
    );
    final older = await cache.capture(
      conversationId: 'chat',
      stepId: 'older',
      sourcePath: file.path,
      sourceDirectory: dir,
      captureSequence: olderSequence,
    );
    expect(older, isNotNull);
    expect(cache.forStep('chat', 'older'), same(older));
    expect(cache.latestIn('chat'), same(newer));
  });

  test(
    'checked reads refuse screenshots outside the trusted app directory',
    () async {
      final file = await picture('outside');
      final trusted = await Directory('${dir.path}/trusted').create();
      expect(
        await cache.capture(
          conversationId: 'chat',
          stepId: 'outside',
          sourcePath: file.path,
          sourceDirectory: trusted,
        ),
        isNull,
      );
      expect(cache.latestIn('chat'), isNull);
    },
  );

  test('invalid images leave the last usable preview intact', () async {
    final file = await picture('safe');
    final safe = await cache.capture(
      conversationId: 'chat',
      stepId: 'safe',
      sourcePath: file.path,
      sourceDirectory: dir,
    );
    final invalid = await File(
      '${dir.path}/shot-invalid.jpg',
    ).writeAsString('not an image');
    expect(
      await cache.capture(
        conversationId: 'chat',
        stepId: 'invalid',
        sourcePath: invalid.path,
        sourceDirectory: dir,
      ),
      isNull,
    );
    expect(cache.latestIn('chat'), same(safe));
  });

  test(
    'clearing a chat during decode prevents a late preview from reappearing',
    () async {
      final file = await picture('late');
      final pending = cache.capture(
        conversationId: 'chat',
        stepId: 'late',
        sourcePath: file.path,
        sourceDirectory: dir,
      );
      cache.clearConversation('chat');
      expect(await pending, isNull);
      expect(cache.latestIn('chat'), isNull);
    },
  );

  test('process cache limits the number of retained chat buckets', () async {
    final file = await picture('chats');
    for (var i = 0; i <= BrowserThumbnailCache.maxChats; i++) {
      await cache.capture(
        conversationId: 'chat-$i',
        stepId: 'step',
        sourcePath: file.path,
        sourceDirectory: dir,
      );
    }
    expect(cache.latestIn('chat-0'), isNull);
    expect(cache.latestIn('chat-${BrowserThumbnailCache.maxChats}'), isNotNull);
  });
}

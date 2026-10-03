import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:Kelivo/core/services/browser/browser_thumbnail_cache.dart';
import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_step_thumbnail.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

void main() {
  final cache = BrowserThumbnailCache.instance;

  setUp(cache.clear);
  tearDown(cache.clear);

  Future<void> cacheWeatherPage(
    WidgetTester tester, {
    String pageUrl = 'https://wttr.in/Paris',
    String fileName = 'weather.jpg',
  }) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'browser-thumbnail-owner',
      );
      addTearDown(() => directory.delete(recursive: true));
      final picture = img.Image(width: 12, height: 8);
      img.fill(picture, color: img.ColorRgb8(70, 150, 200));
      final file = await File(
        '${directory.path}/$fileName',
      ).writeAsBytes(img.encodeJpg(picture));
      expect(
        await cache.capture(
          conversationId: 'chat',
          stepId: 'weather-capture',
          sourcePath: file.path,
          sourceDirectory: directory,
          pageUrl: pageUrl,
        ),
        isNotNull,
      );
    });
  }

  testWidgets('ya.ru step cannot reuse the chat wttr.in screenshot', (
    tester,
  ) async {
    await cacheWeatherPage(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: ComputerStep(
              id: 'yandex-open',
              toolName: 'browser_use',
              arguments: {'action': 'open', 'url': 'https://ya.ru'},
              metadata: {
                'browser': {'startedAt': '2020-01-01T00:00:00Z'},
              },
            ),
            conversationId: 'chat',
            width: 64,
            height: 40,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Lucide.Globe), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    final preview = tester.getRect(find.byType(ComputerStepThumbnail));
    final globe = tester.getRect(find.byIcon(Lucide.Globe));
    expect(preview.size, const Size(64, 40));
    expect(globe.center, preview.center);
    final fallback = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Lucide.Globe),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (fallback.decoration as BoxDecoration).color,
      Theme.of(
        tester.element(find.byIcon(Lucide.Globe)),
      ).colorScheme.surfaceContainerHighest,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing step page ownership does not reuse chat latest', (
    tester,
  ) async {
    await cacheWeatherPage(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: ComputerStep(id: 'unknown', toolName: 'browser_use'),
            conversationId: 'chat',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Lucide.Globe), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live fallback domain keeps the captured launch display filter', (
    tester,
  ) async {
    const filter = ToolDisplayRedaction(
      text: _redactLaunchSecret,
      value: _redactLaunchValue,
    );
    final step = await filter.run(() async {
      return ComputerStep(id: 'live-page', toolName: 'browser_use');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: step,
            conversationId: 'chat',
            browserPageUrl: 'https://ya.ru',
            browserDomain: 'launch-secret',
            width: 64,
            height: 40,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('launch-secret'), findsNothing);
    expect(find.byIcon(Lucide.Globe), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(step.canPreviewBrowserPage('https://launch-secret'), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final sample in [
    (
      name: 'cached fallback page URL keeps the captured launch filter',
      pageUrl: 'https://wttr.in/launch-secret',
      fileName: 'weather.jpg',
      exactSource: false,
    ),
    (
      name: 'exact cached source keeps the candidate page launch filter',
      pageUrl: 'https://wttr.in/launch-secret',
      fileName: 'weather.jpg',
      exactSource: true,
    ),
    (
      name: 'cached fallback source keeps the captured launch filter',
      pageUrl: 'https://wttr.in/Paris',
      fileName: 'launch-secret.jpg',
      exactSource: false,
    ),
  ]) {
    testWidgets(sample.name, (tester) async {
      await cacheWeatherPage(
        tester,
        pageUrl: sample.pageUrl,
        fileName: sample.fileName,
      );
      const filter = ToolDisplayRedaction(
        text: _redactLaunchSecret,
        value: _redactLaunchValue,
      );
      final step = await filter.run(() async {
        return ComputerStep(
          id: 'current-launch',
          toolName: 'browser_use',
          arguments: {'url': 'https://wttr.in/Paris'},
          content: sample.exactSource
              ? jsonEncode({
                  'url': 'https://wttr.in/Paris',
                  'screenshot': cache.latestIn('chat')!.sourcePath,
                })
              : null,
          metadata: {
            'browser': {'startedAt': '2020-01-01T00:00:00Z'},
          },
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComputerStepThumbnail(step: step, conversationId: 'chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Lucide.Globe), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact preview retains the checked screenshot pixels', (
    tester,
  ) async {
    await cacheWeatherPage(tester);
    final step = ComputerStep(
      id: 'weather-read',
      toolName: 'browser_use',
      arguments: {'action': 'read', 'url': 'https://wttr.in/Paris'},
      content: jsonEncode({
        'ok': true,
        'url': 'https://wttr.in/Paris',
        'screenshot': cache.latestIn('chat')!.sourcePath,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: step,
            conversationId: 'chat',
            width: 64,
            height: 40,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Lucide.Globe), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('computer-step-thumbnail:weather-read')),
      ),
      const Size(64, 40),
    );
    final clip = tester.widget<ClipRRect>(
      find
          .ancestor(
            of: find.byKey(
              const ValueKey('computer-step-thumbnail:weather-read'),
            ),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.borderRadius, BorderRadius.circular(10));
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });
}

String _redactLaunchSecret(String value) =>
    value.replaceAll('launch-secret', '[REDACTED]');

Object? _redactLaunchValue(Object? value) => value;

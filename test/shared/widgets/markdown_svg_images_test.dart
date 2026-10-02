import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/pages/image_viewer_page.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/shared/widgets/markdown_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

const _svg =
    "<svg xmlns='http://www.w3.org/2000/svg' width='80' height='80'>"
    "<circle cx='40' cy='40' r='35' fill='orange'/></svg>";

Widget _harness(Widget child) => ChangeNotifierProvider(
  create: (_) => SettingsProvider(createBusinessTestPreferences()),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Future<ui.Image?> _decodeDisplayedImage(WidgetTester tester) async {
  await tester.pump();
  expect(find.byType(Image), findsWidgets);
  final provider = tester.widget<Image>(find.byType(Image).first).image;
  final ready = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!ready.isCompleted) ready.complete(info.image.clone());
      info.dispose();
    },
    onError: (_, _) {
      if (!ready.isCompleted) ready.complete(null);
    },
  );
  stream.addListener(listener);
  try {
    // SVG compilation crosses a real isolate/engine boundary. Flush the
    // widget's fake-async continuations between real IO turns until the actual
    // stream completes; waiting inside runAsync alone cannot drain that zone.
    final deadline = Stopwatch()..start();
    while (!ready.isCompleted &&
        deadline.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump();
    }
    expect(ready.isCompleted, isTrue, reason: 'image stream did not finish');
    final image = await ready.future;
    await tester.pump();
    return image;
  } finally {
    stream.removeListener(listener);
  }
}

Future<void> _expectOrangeSvg(WidgetTester tester) async {
  final image = await _decodeDisplayedImage(tester);
  expect(image, isNotNull, reason: 'SVG must decode through flutter_svg');
  try {
    expect(image!.width, 80);
    expect(image.height, 80);
    final pixels = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final center = (40 * image.width + 40) * 4;
    expect(pixels!.buffer.asUint8List().sublist(center, center + 4), [
      255,
      165,
      0,
      255,
    ]);
    expect(tester.takeException(), isNull);
  } finally {
    image?.dispose();
  }
}

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });
  final sources = {
    'raw utf8': 'data:image/svg+xml;utf8,$_svg',
    'utf8 with literal closing parenthesis':
        'data:image/svg+xml;utf8,${_svg.replaceFirst("<circle", "<!-- a literal ) and fake </svg> in a comment --><circle")}',
    'utf8 with transform parentheses':
        'data:image/svg+xml;utf8,${_svg.replaceFirst('<circle', "<g transform='rotate(0 40 40)'><circle").replaceFirst('</svg>', '</g></svg>')}',
    'utf8 with XML epilog':
        'data:image/svg+xml;utf8,$_svg<!-- generated export ) --><?export done?>',
    'percent encoded': 'data:image/svg+xml,${Uri.encodeComponent(_svg)}',
    'base64': 'data:image/svg+xml;base64,${base64Encode(utf8.encode(_svg))}',
    'checked bytes': 'data:image/*;base64,${base64Encode(utf8.encode(_svg))}',
  };
  for (final entry in sources.entries) {
    testWidgets('chat displays SVG data URI ${entry.key}', (tester) async {
      await tester.pumpWidget(
        _harness(MarkdownWithCodeHighlight(text: '![логотип](${entry.value})')),
      );
      await _expectOrangeSvg(tester);
    });
    testWidgets('viewer displays and zooms SVG data URI ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(ImageViewerPage(images: [entry.value])));
      await _expectOrangeSvg(tester);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 5);
      viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 2);
    });
  }

  testWidgets('SVG export bytes match the image after a cache hit', (
    tester,
  ) async {
    var requests = 0;
    const url = 'https://example.test/changing.svg';
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          _harness(Image(image: MarkdownImageProvider(url))),
        );
        await _expectOrangeSvg(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final provider = MarkdownImageProvider(url);
        await tester.pumpWidget(_harness(Image(image: provider)));
        final displayed = await _decodeDisplayedImage(tester);
        try {
          final pixels = await tester.runAsync(
            () => displayed!.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final data = await tester.runAsync(provider.readSource);
          final expectedFill = pixels!.getUint8((40 * 80 + 40) * 4) == 255
              ? "fill='orange'"
              : "fill='blue'";
          expect(utf8.decode(data!.bytes), contains(expectedFill));
        } finally {
          displayed?.dispose();
        }
      },
      () => MockClient(
        (request) async => http.Response(
          requests++ == 0 ? _svg : _svg.replaceFirst('orange', 'blue'),
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      ),
    );
  });

  for (final url in [
    'https://example.test/logo.svg',
    'https://example.test/image',
  ]) {
    for (final viewer in [false, true]) {
      testWidgets('SVG HTTP $url in ${viewer ? 'viewer' : 'chat'}', (
        tester,
      ) async {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              _harness(
                viewer
                    ? ImageViewerPage(images: [url])
                    : MarkdownWithCodeHighlight(text: '![логотип]($url)'),
              ),
            );
            await _expectOrangeSvg(tester);
          },
          () => MockClient(
            (request) async => http.Response(
              _svg,
              200,
              headers: {
                'content-type': url.endsWith('.svg')
                    ? 'application/octet-stream'
                    : 'image/svg+xml; charset=utf-8',
              },
            ),
          ),
        );
      });
    }
  }

  for (final viewer in [false, true]) {
    testWidgets('broken SVG shows an icon in ${viewer ? 'viewer' : 'chat'}', (
      tester,
    ) async {
      final source =
          'data:image/svg+xml;base64,${base64Encode(utf8.encode('<svg><broken>'))}';
      await tester.pumpWidget(
        _harness(
          viewer
              ? ImageViewerPage(images: [source])
              : MarkdownWithCodeHighlight(text: '![]($source)'),
        ),
      );
      final image = await _decodeDisplayedImage(tester);
      expect(image, isNull);
      expect(find.byIcon(Lucide.ImageOff), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SVG external image href does not issue a second HTTP request', (
    tester,
  ) async {
    final requests = <Uri>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          _harness(
            const MarkdownWithCodeHighlight(
              text: '![](https://example.test/logo.svg)',
            ),
          ),
        );
        await _expectOrangeSvg(tester);
        expect(requests, [Uri.parse('https://example.test/logo.svg')]);
      },
      () => MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          _svg.replaceFirst(
            '</svg>',
            '<image href="https://external.test/secret.png" width="80" height="80"/></svg>',
          ),
          200,
          headers: {'content-type': 'image/svg+xml'},
        );
      }),
    );
  });

  testWidgets('viewer refuses a local SVG outside allowed roots', (
    tester,
  ) async {
    final dir = Directory(
      p.join(Directory.current.path, '.dart_tool'),
    ).createTempSync('svg_outside_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'secret.svg'))..writeAsStringSync(_svg);
    await tester.pumpWidget(_harness(ImageViewerPage(images: [file.path])));
    final image = await _decodeDisplayedImage(tester);
    expect(image, isNull);
    expect(find.byIcon(Lucide.ImageOff), findsWidgets);
  });

  test('SVG data URI rejects payloads above the raster byte budget', () {
    final payload = 'x' * (kMaxMarkdownImageBytes + 1);
    expect(
      () => decodeMarkdownImageData('data:image/svg+xml;utf8,$payload'),
      throwsFormatException,
    );
  });

  testWidgets('huge SVG dimensions stay inside raster decode limits', (
    tester,
  ) async {
    final huge = _svg.replaceFirst("width='80'", "width='100000'");
    final source =
        'data:image/svg+xml;base64,${base64Encode(utf8.encode(huge))}';
    await tester.pumpWidget(_harness(ImageViewerPage(images: [source])));
    final image = await _decodeDisplayedImage(tester);
    expect(image, isNotNull);
    expect(image!.width, lessThanOrEqualTo(kMaxViewerDecodeEdge));
    expect(image.height, greaterThan(0));
    expect(
      image.width * image.height,
      lessThanOrEqualTo(kMaxViewerDecodePixels),
    );
    image.dispose();
  });

  testWidgets('SVG HTTP rejects a payload above the image byte budget', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          _harness(
            const MarkdownWithCodeHighlight(
              text: '![](https://example.test/too-large.svg)',
            ),
          ),
        );
        expect(await _decodeDisplayedImage(tester), isNull);
        expect(find.byIcon(Lucide.ImageOff), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (request) async => http.Response(
          'x' * (kMaxMarkdownImageBytes + 1),
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      ),
    );
  });
}

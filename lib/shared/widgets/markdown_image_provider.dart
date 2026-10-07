import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../../core/services/workspace/local_image_access.dart';
import '../../utils/safe_resize_image.dart';

/// The same encoded-byte budget applies to SVG and raster message images.
const int kMaxMarkdownImageBytes = 20 * 1024 * 1024;
const int kMaxMarkdownImageEdge = 4096;
const int kMaxMarkdownImagePixels = 12 * 1024 * 1024;

Uint8List decodeMarkdownImageData(String source) {
  // Percent encoding can use three source characters per byte. Bound input
  // before allocating the decoded payload, then check the actual byte count.
  if (source.length > kMaxMarkdownImageBytes * 3 + 256) {
    throw const FormatException('Image data URI is too large');
  }
  final comma = source.indexOf(',');
  if (comma < 0) throw const FormatException('Invalid image data URI');
  final header = source
      .substring(0, comma)
      .replaceAll(
        RegExp(r';utf8(?=;|$)', caseSensitive: false),
        ';charset=utf-8',
      );
  final data = UriData.parse('$header${source.substring(comma)}');
  if (!data.mimeType.toLowerCase().startsWith('image/')) {
    throw const FormatException('Expected image data');
  }
  final bytes = data.contentAsBytes();
  _checkSize(bytes);
  return bytes;
}

bool isMarkdownSvg(Uint8List bytes, {String source = '', String? mimeType}) {
  final uri = Uri.tryParse(source);
  if (mimeType?.split(';').first.trim().toLowerCase() == 'image/svg+xml' ||
      uri?.path.toLowerCase().endsWith('.svg') == true ||
      source.toLowerCase().startsWith('data:image/svg+xml')) {
    return true;
  }
  // Checked local bytes are passed to the viewer as data:image/*, so retain
  // detection after the original path and its extension have been discarded.
  final prefix = utf8.decode(bytes.take(1024).toList(), allowMalformed: true);
  return RegExp(
    r'^\s*(?:<\?xml[^>]*>\s*)?(?:<!--[\s\S]*?-->\s*)*<svg(?:\s|>)',
  ).hasMatch(prefix.replaceFirst('\uFEFF', ''));
}

ImageProvider markdownImageFromBytes(Uint8List bytes, {String source = ''}) {
  // Invalid checked files still reach the asynchronous provider error path,
  // where Image.errorBuilder can render a placeholder without a build error.
  return bytes.isEmpty ||
          bytes.length > kMaxMarkdownImageBytes ||
          isMarkdownSvg(bytes, source: source)
      ? MarkdownImageProvider(source, bytes: bytes)
      : MemoryImage(bytes);
}

String checkedMarkdownImageDataUri(Uint8List bytes, {required String source}) =>
    'data:image/${isMarkdownSvg(bytes, source: source) ? 'svg+xml' : '*'};base64,${base64Encode(bytes)}';

/// XML boundaries keep literal parentheses and fake closing tags in comments
/// inside raw SVG data destinations, including comments/PIs after the root.
int? rawSvgDocumentLength(String source) {
  if (!source.trimLeft().startsWith('<')) return null;
  var depth = 0;
  var started = false;
  int? documentEnd;
  try {
    for (final event in parseEvents(
      source,
      validateNesting: true,
      withLocation: true,
    )) {
      if (documentEnd != null) {
        if (event is XmlCommentEvent ||
            event is XmlProcessingEvent ||
            (event is XmlTextEvent && event.value.trim().isEmpty)) {
          documentEnd = event.stop;
          continue;
        }
        return documentEnd;
      }
      if (event is XmlStartElementEvent) {
        if (!started && event.localName != 'svg') return null;
        started = true;
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      } else {
        continue;
      }
      if (started && depth == 0) documentEnd = event.stop;
    }
  } on XmlException {
    return documentEnd;
  }
  return documentEnd;
}

Future<Uint8List> markdownImageRasterBytes(
  Uint8List bytes, {
  String source = '',
  String? mimeType,
}) async {
  _checkSize(bytes);
  return isMarkdownSvg(bytes, source: source, mimeType: mimeType)
      ? _rasterizeSvg(bytes)
      : bytes;
}

/// Loads source bytes once, then uses flutter_svg for SVG and Flutter's
/// ordinary raster codec otherwise. Keeping one ImageProvider means chat and
/// ImageViewerPage share errors, bounded decoding and existing zoom behavior.
class MarkdownImageProvider extends ImageProvider<MarkdownImageProvider> {
  MarkdownImageProvider(this.source, {this.bytes});

  final String source;
  final Uint8List? bytes;
  final _sourceRead = _ImageSourceRead();

  @override
  Future<MarkdownImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MarkdownImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    MarkdownImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final completer = MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      // Never include model-written URLs or embedded image data in diagnostics.
      debugLabel: 'Markdown image',
    );
    completer.addEphemeralErrorListener((_, _) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final data = await readSource();
    final payload = await markdownImageRasterBytes(
      data.bytes,
      source: source,
      mimeType: data.mimeType,
    );
    return decode(await ui.ImmutableBuffer.fromUint8List(payload));
  }

  Future<({Uint8List bytes, String? mimeType})> readSource() =>
      _sourceRead.future ??= _readSource();

  Future<({Uint8List bytes, String? mimeType})> _readSource() async {
    Uint8List? payload = bytes;
    String? mimeType;
    if (payload == null) {
      if (source.startsWith('data:')) {
        payload = decodeMarkdownImageData(source);
      } else if (source.startsWith('https://') ||
          source.startsWith('http://')) {
        final client = http.Client();
        try {
          final response = await client
              .send(http.Request('GET', Uri.parse(source)))
              .timeout(const Duration(seconds: 30));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw StateError('Image HTTP ${response.statusCode}');
          }
          if ((response.contentLength ?? 0) > kMaxMarkdownImageBytes) {
            throw const FormatException('Image is too large');
          }
          mimeType = response.headers['content-type'];
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            if (builder.length + chunk.length > kMaxMarkdownImageBytes) {
              throw const FormatException('Image is too large');
            }
            builder.add(chunk);
          }
          payload = builder.takeBytes();
        } finally {
          client.close();
        }
      } else {
        payload = await readLocalImageBytes(
          source,
          maxBytes: kMaxMarkdownImageBytes,
        );
      }
    }
    if (payload == null) throw const FormatException('Image is unavailable');
    _checkSize(payload);
    return (bytes: payload, mimeType: mimeType);
  }

  // Identity keys bind decoded cache entries to this checked source read.
  // Source-only equality could show an earlier instance's cached picture and
  // then export different bytes after the file or HTTP response changes.
}

void _checkSize(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > kMaxMarkdownImageBytes) {
    throw const FormatException('Image is empty or too large');
  }
}

class _ImageSourceRead {
  Future<({Uint8List bytes, String? mimeType})>? future;
}

Future<Uint8List> _rasterizeSvg(Uint8List bytes) async {
  final document = XmlDocument.parse(utf8.decode(bytes));
  final root = document.rootElement;
  if (root.name.local != 'svg' ||
      (root.namespaceUri != null &&
          root.namespaceUri != 'http://www.w3.org/2000/svg') ||
      document.children.any((node) => node is XmlDoctype)) {
    throw const FormatException('Invalid SVG document');
  }
  // flutter_svg can fetch <image> hrefs while compiling. Remove embedded
  // images and non-fragment references before handing any XML to its loader;
  // neither HTTP, file paths nor nested data SVGs may trigger a second read.
  for (final element in root.descendants.whereType<XmlElement>().toList()) {
    if (element.name.local == 'image') {
      element.parent?.children.remove(element);
      continue;
    }
    element.attributes.removeWhere(
      (attribute) =>
          attribute.name.local == 'href' &&
          !attribute.value.trim().startsWith('#'),
    );
  }
  final info = await vg.loadPicture(SvgStringLoader(root.toXmlString()), null);
  ui.Picture? scaled;
  ui.Image? image;
  try {
    final size = info.size;
    if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
      throw const FormatException('Invalid SVG dimensions');
    }
    final target = clampDecodedPixelSize(
      width: size.width,
      height: size.height,
      maxEdge: kMaxMarkdownImageEdge,
      maxPixels: kMaxMarkdownImagePixels,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(target.width / size.width, target.height / size.height)
      ..drawPicture(info.picture);
    scaled = recorder.endRecording();
    image = await scaled.toImage(target.width, target.height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('SVG rasterization failed');
    return png.buffer.asUint8List();
  } finally {
    image?.dispose();
    scaled?.dispose();
    info.picture.dispose();
  }
}

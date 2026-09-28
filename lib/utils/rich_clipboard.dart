import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

/// Copies Markdown as rich text: plain text plus HTML, which Notes, Gmail
/// and Docs paste with its formatting.
class RichClipboard {
  const RichClipboard._();

  static const MethodChannel _channel = MethodChannel('app.clipboard');

  /// HTML for [markdown] (GitHub flavour: tables, strikethrough, task
  /// lists). Scripts, frames, styles and event handlers a reply may carry
  /// are dropped; the rest of its inline HTML stays.
  static String htmlOf(String markdown) {
    final raw = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final fragment = html_parser.parseFragment(raw);
    for (final element in fragment.querySelectorAll(
      'script, style, iframe, object, embed',
    )) {
      element.remove();
    }
    for (final element in fragment.querySelectorAll('*')) {
      element.attributes.removeWhere(
        (name, value) =>
            '$name'.toLowerCase().startsWith('on') ||
            value.trim().toLowerCase().startsWith('javascript:'),
      );
    }
    return fragment.outerHtml;
  }

  /// Copies [markdown] with its formatting; plain text where rich text
  /// cannot be written. The plain part is the Markdown source.
  static Future<void> copyMarkdown(String markdown) async {
    bool? rich;
    try {
      rich = await _channel.invokeMethod<bool>('setHtml', {
        'text': markdown,
        'html': htmlOf(markdown),
      });
    } on MissingPluginException {
      rich = false;
    } on PlatformException {
      rich = false;
    }
    if (rich != true) await Clipboard.setData(ClipboardData(text: markdown));
  }
}

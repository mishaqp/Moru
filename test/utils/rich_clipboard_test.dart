import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/utils/rich_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Markdown becomes HTML with tables and without scripts', () {
    final html = RichClipboard.htmlOf(
      '# Title\n\n**bold** and ~~gone~~\n\n'
      '| a | b |\n| - | - |\n| 1 | 2 |\n\n'
      '<script>alert(1)</script>\n\n'
      '<a href="javascript:alert(1)" onclick="x()">link</a>',
    );
    expect(html, contains('<h1>Title</h1>'));
    expect(html, contains('<strong>bold</strong>'));
    expect(html, contains('<del>gone</del>'));
    expect(html, contains('<td>1</td>'));
    expect(html, isNot(contains('script')));
    expect(html, isNot(contains('onclick')));
    expect(html, isNot(contains('javascript:')));
    expect(html, contains('>link</a>'));
  });

  test('rich text goes through the channel, plain text without it', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    String? plain;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        plain = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const channel = MethodChannel('app.clipboard');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    await RichClipboard.copyMarkdown('**hi**');
    expect(calls.single.method, 'setHtml');
    expect(calls.single.arguments, {
      'text': '**hi**',
      'html': contains('<strong>hi</strong>'),
    });
    expect(plain, isNull);

    messenger.setMockMethodCallHandler(channel, null);
    await RichClipboard.copyMarkdown('**hi**');
    expect(plain, '**hi**');
  });
}

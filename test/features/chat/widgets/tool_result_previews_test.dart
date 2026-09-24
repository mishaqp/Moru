import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/widgets/tool_result_previews.dart';

Future<void> _pump(WidgetTester tester, Widget? preview) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: preview ?? const Text('plain'))),
  );
}

Widget? _preview(String tool, Map<String, dynamic> args, Object? result) =>
    structuredToolPreview(
      toolName: tool,
      arguments: args,
      content: result == null ? null : jsonEncode(result),
      textColor: Colors.black,
      mutedColor: Colors.grey,
      errorColor: Colors.red,
    );

void main() {
  testWidgets('web search shows sources instead of JSON', (tester) async {
    await _pump(
      tester,
      _preview(
        'search_web',
        {'query': 'flutter'},
        {
          'items': [
            for (var i = 0; i < 5; i++)
              {'title': 'Result $i', 'url': 'https://www.site$i.dev/a'},
          ],
        },
      ),
    );
    expect(find.text('site0.dev'), findsOneWidget);
    expect(find.text('Result 2'), findsOneWidget);
    expect(find.text('Result 3'), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    expect(find.textContaining('"items"'), findsNothing);
  });

  testWidgets('browser shows the action, the page and a failure', (
    tester,
  ) async {
    await _pump(
      tester,
      _preview(
        'browser_use',
        {'action': 'open', 'url': 'https://example.com/docs'},
        {'ok': false, 'error': 'timeout', 'message': 'Page did not load'},
      ),
    );
    expect(find.text('open'), findsOneWidget);
    expect(find.text('example.com/docs'), findsOneWidget);
    expect(find.text('Page did not load'), findsOneWidget);
  });

  test('other tools keep the plain summary', () {
    expect(_preview('get_weather', const {}, {'ok': true}), isNull);
    expect(_preview('search_web', const {}, null), isNull);
  });
}

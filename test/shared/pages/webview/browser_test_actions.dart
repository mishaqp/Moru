import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the browser's real overflow action without waiting for a busy
/// page's indeterminate progress animation to settle.
Future<void> closeBrowserFromMenu(
  WidgetTester tester, {
  bool confirm = false,
}) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Close browser'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  if (confirm) {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Close browser'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

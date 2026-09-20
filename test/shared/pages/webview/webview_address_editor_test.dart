import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_address_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBrowserAddress', () {
    test('accepts a bare domain and prepends https', () {
      final uri = parseBrowserAddress('example.com');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.host, 'example.com');
    });

    test('accepts a full valid URL as-is', () {
      final uri = parseBrowserAddress('http://example.com/path?q=1');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'http');
      expect(uri.path, '/path');
    });

    test('rejects a non-http(s) scheme', () {
      expect(parseBrowserAddress('ftp://example.com'), isNull);
    });

    test('rejects an empty host', () {
      expect(parseBrowserAddress('https://'), isNull);
    });

    test('rejects a blank string', () {
      expect(parseBrowserAddress('   '), isNull);
    });

    test('trims surrounding whitespace', () {
      final uri = parseBrowserAddress('  example.com  ');
      expect(uri?.host, 'example.com');
    });
  });

  group('showBrowserAddressEditor', () {
    Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('a valid submit calls onSubmit with the parsed uri', (
      tester,
    ) async {
      Uri? submitted;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBrowserAddressEditor(
                context,
                currentUrl: 'https://example.com',
                onSubmit: (uri) => submitted = uri,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'newsite.com');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.host, 'newsite.com');
      expect(submitted!.scheme, 'https');
    });

    testWidgets(
      'an invalid submit shows a visible inline error instead of a silent '
      'no-op',
      (tester) async {
        var callCount = 0;
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showBrowserAddressEditor(
                  context,
                  currentUrl: 'https://example.com',
                  onSubmit: (_) => callCount++,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ftp://bad');
        await tester.tap(find.text('Go'));
        await tester.pump();

        expect(callCount, 0);
        expect(
          find.text('Enter a valid http or https address.'),
          findsOneWidget,
        );
        // The sheet stays open -- not a silent dismissal.
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  });
}

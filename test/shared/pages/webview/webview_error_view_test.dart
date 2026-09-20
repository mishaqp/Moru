import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('shows the error title and a Retry button', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      wrap(
        WebViewErrorView(
          error: const WebResourceError(
            errorCode: -2,
            description: 'net::ERR_NAME_NOT_RESOLVED',
            errorType: WebResourceErrorType.hostLookup,
            isForMainFrame: true,
          ),
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text("This page couldn't load"), findsOneWidget);
    expect(find.text('Could not connect to the server.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browser_error_retry_button')));
    expect(retried, isTrue);
  });

  testWidgets('falls back to the raw description for an unmapped error type', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewErrorView(
          error: const WebResourceError(
            errorCode: -99,
            description: 'Something platform-specific went wrong',
          ),
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('Something platform-specific went wrong'), findsOneWidget);
  });
}

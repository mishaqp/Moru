import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(PreferredSizeWidget appBar) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(appBar: appBar, body: const SizedBox()),
  );

  testWidgets('shows the domain, not the full URL, as the primary text', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com/some/long/path?x=1',
          title: null,
          onClose: () {},
          onShowConsole: () {},
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(find.textContaining('/some/long/path'), findsNothing);
  });

  testWidgets('shows a short page title only when it differs from the domain', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: 'Example Domain',
          onClose: () {},
          onShowConsole: () {},
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Example Domain'), findsOneWidget);
  });

  testWidgets('omits the subtitle when the title equals the domain', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: 'example.com',
          onClose: () {},
          onShowConsole: () {},
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('tapping the address area calls onTapAddress', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: null,
          onClose: () {},
          onTapAddress: () => tapped = true,
          onShowConsole: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('browser_address_tap_target')));
    expect(tapped, isTrue);
  });

  testWidgets('close button calls onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: null,
          onClose: () => closed = true,
          onShowConsole: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Close'));
    expect(closed, isTrue);
  });

  testWidgets(
    'agent-only menu items (activity log, settings) are absent when their '
    'callbacks are null',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          WebViewTopBar(
            currentUrl: 'https://example.com',
            title: null,
            onClose: () {},
            onShowConsole: () {},
          ),
        ),
      );

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Activity log'), findsNothing);
      expect(find.text('Browser settings'), findsNothing);
      expect(find.text('Console Logs'), findsOneWidget);
    },
  );

  testWidgets('shows all menu items when every callback is provided, with '
      'the console item last, below a divider', (tester) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: null,
          onClose: () {},
          onCopyLink: () {},
          onOpenExternally: () {},
          onShowActivityLog: () {},
          onOpenSettings: () {},
          onShowConsole: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Open in Browser'), findsOneWidget);
    expect(find.text('Activity log'), findsOneWidget);
    expect(find.text('Browser settings'), findsOneWidget);
    expect(find.text('Console Logs'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
  });

  testWidgets('no separate address bar exists outside the top bar itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: null,
          onClose: () {},
          onTapAddress: () {},
          onShowConsole: () {},
        ),
      ),
    );

    // Only one place shows the domain text.
    expect(find.text('example.com'), findsOneWidget);
  });
}

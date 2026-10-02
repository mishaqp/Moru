import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/pages/webview/webview_top_bar.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/frosted/frosted_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

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
    expect(find.byType(PopupMenuDivider), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Console Logs')).dy,
      greaterThan(tester.getTopLeft(find.text('Activity log')).dy),
    );
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

  testWidgets('the address pill marks plain http and shows load progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'http://example.com',
          title: null,
          onClose: () {},
          onShowConsole: () {},
          progress: 0.4,
        ),
      ),
    );
    final lock = tester.widget<Icon>(
      find.byKey(const ValueKey('browser_address_lock')),
    );
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(lock.color, theme.colorScheme.error);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('browser_address_progress')),
    );
    expect(bar.value, 0.4);

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
    expect(
      find.byKey(const ValueKey('browser_address_progress')),
      findsNothing,
    );
  });

  testWidgets('address and bookmark have separate 48dp touch targets', (
    tester,
  ) async {
    var edited = 0;
    var bookmarked = 0;
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com/full/path?q=1',
          title: 'An example page',
          onClose: () {},
          onTapAddress: () => edited++,
          onToggleBookmark: () => bookmarked++,
          onShowConsole: () {},
          progress: 0.4,
        ),
      ),
    );
    final address = find.byKey(const ValueKey('browser_address_tap_target'));
    final bookmark = find.byKey(const ValueKey('browser_bookmark_star'));
    expect(tester.getSize(address).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(bookmark).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(bookmark).height, greaterThanOrEqualTo(48));
    await tester.tap(address);
    await tester.tap(bookmark);
    await tester.tapAt(
      tester.getRect(address).bottomCenter + const Offset(0, -1),
    );
    await tester.tapAt(
      tester.getRect(bookmark).bottomCenter + const Offset(0, -1),
    );
    expect(edited, 2);
    expect(bookmarked, 2);
  });

  testWidgets(
    'desktop-site menu uses an icon and right switch and toggles once',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        wrap(
          WebViewTopBar(
            currentUrl: 'https://example.com',
            title: null,
            onClose: () {},
            onShowConsole: () {},
            desktopMode: false,
            onDesktopModeChanged: changes.add,
          ),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Lucide.Monitor), findsOneWidget);
      final toggle = find.byType(IosSwitch);
      expect(toggle, findsOneWidget);
      expect(tester.widget<IosSwitch>(toggle).value, isFalse);
      expect(
        tester.getCenter(toggle).dx,
        greaterThan(tester.getCenter(find.text('Desktop site')).dx),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(find.text('Desktop site'), findsNothing);
    },
  );

  testWidgets('history and AI activity have different icons in grouped menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://example.com',
          title: null,
          onClose: () {},
          onShowConsole: () {},
          onCopyLink: () {},
          onOpenExternally: () {},
          onShowBookmarks: () {},
          onShowHistory: () {},
          onShowUserscripts: () {},
          desktopMode: true,
          onDesktopModeChanged: (_) {},
          onClearSiteData: () {},
          onOpenSettings: () {},
          onShowActivityLog: () {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Lucide.History), findsOneWidget);
    expect(find.byIcon(Lucide.Bot), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsNWidgets(3));
  });

  testWidgets('long title and all address actions fit at 1.3 text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var minimized = 0;
    await tester.pumpWidget(
      wrap(
        WebViewTopBar(
          currentUrl: 'https://a-long-domain.example.com/path?q=1',
          title: 'A long page title that needs to remain inside the address',
          onClose: () {},
          onMinimize: () => minimized++,
          onTapAddress: () {},
          onToggleBookmark: () {},
          onShowTabs: () {},
          tabCount: 8,
          onShowConsole: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final minimize = find.byKey(const ValueKey('browser_minimize'));
    expect(tester.getSize(minimize).width, greaterThanOrEqualTo(48));
    await tester.tapAt(tester.getRect(minimize).topLeft + const Offset(1, 6));
    expect(minimized, 1);
  });

  testWidgets('Glass address and menu follow the app tint without live blur', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setGlassTheme(true);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: wrap(
          WebViewTopBar(
            currentUrl: 'https://example.com',
            title: 'Example',
            onClose: () {},
            onTapAddress: () {},
            onShowConsole: () {},
          ),
        ),
      ),
    );
    final surfaces = tester.widgetList<FrostedSurface>(
      find.byType(FrostedSurface),
    );
    expect(surfaces, isNotEmpty);
    expect(surfaces.first.style.background.a, closeTo(0.34, 0.001));
    expect(surfaces.first.style.border.a, closeTo(0.2, 0.001));
    expect(surfaces.first.style.blurSigma, 0);
    expect(find.byType(BackdropFilter), findsNothing);
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>),
    );
    expect(
      menu.color!.a,
      greaterThanOrEqualTo(0.9),
      reason: 'toolbar text must not compete with menu labels through the tint',
    );
    expect(menu.color!.a, lessThan(1));
    await settings.setGlassTheme(false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FrostedSurface>(find.byType(FrostedSurface))
          .style
          .background
          .a,
      closeTo(0.7, 0.001),
    );
  });
}

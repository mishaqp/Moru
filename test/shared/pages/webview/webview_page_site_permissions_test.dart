import 'package:Kelivo/core/services/browser/browser_site_permissions.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../../support/fake_webview_platform.dart';

class _Request extends PlatformWebViewPermissionRequest {
  _Request(Set<WebViewPermissionResourceType> types) : super(types: types);

  /// The answer, kept outside the immutable request.
  final List<bool> answers = [];

  bool? get granted => answers.isEmpty ? null : answers.single;

  @override
  Future<void> grant() async => answers.add(true);

  @override
  Future<void> deny() async => answers.add(false);
}

void main() {
  final permissions = BrowserSitePermissions.instance;
  final originalRuntime = permissions.requestRuntime;

  setUp(() {
    installFakeWebViewPlatform();
    permissions
      ..reset()
      ..requestRuntime = (_) async => true;
  });

  tearDown(() {
    permissions
      ..reset()
      ..requestRuntime = originalRuntime;
  });

  testWidgets('a site asking for the camera and microphone gets them only '
      'after the user allows it, once per site', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WebViewPage(url: 'https://meet.example/room'),
      ),
    );
    await tester.pump();
    final fake = FakeWebViewPlatform.lastCreated!;

    final first = _Request({
      WebViewPermissionResourceType.camera,
      WebViewPermissionResourceType.microphone,
    });
    fake.onPermission!(first);
    await tester.pumpAndSettle();
    expect(find.text('meet.example'), findsWidgets);
    expect(
      find.text('Allow this site to use: camera, microphone?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(first.granted, isTrue);

    final again = _Request({WebViewPermissionResourceType.camera});
    fake.onPermission!(again);
    await tester.pumpAndSettle();
    expect(find.text('Allow'), findsNothing);
    expect(again.granted, isTrue);
  });

  testWidgets('blocking denies the request', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WebViewPage(url: 'https://cam.example'),
      ),
    );
    await tester.pump();
    final request = _Request({WebViewPermissionResourceType.camera});
    FakeWebViewPlatform.lastCreated!.onPermission!(request);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(request.granted, isFalse);
  });
}

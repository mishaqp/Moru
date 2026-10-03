import 'package:Kelivo/core/services/auth/oauth_callback_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real Android callback through its native browser channel.
/// Returns the same launcher for the occupied-loopback recovery path.
OAuthUrlLauncher mockAndroidOAuthBrowser([OAuthUrlLauncher? launcher]) {
  const channel = MethodChannel('app.oauth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'cancel') return null;
    expect(call.method, 'authenticate');
    if (launcher == null) fail('Unexpected native browser launch');
    final arguments = call.arguments as Map<Object?, Object?>;
    final url = Uri.parse(arguments['url']! as String);
    expect(await launcher(url), isTrue);
    return Uri.parse(arguments['redirectUri']! as String)
        .replace(queryParameters: {'state': url.queryParameters['state']!})
        .toString();
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launcher ?? (_) async => false;
}

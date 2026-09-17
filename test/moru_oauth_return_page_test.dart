import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/auth/oauth_callback_io.dart';
import 'package:Kelivo/core/services/auth/oauth_callback_types.dart';
import 'package:flutter_test/flutter_test.dart';

class _Browser implements OAuthCallback {
  @override
  final redirectUri = Uri.parse('com.mishaqp.moru://mcp-oauth-callback/test');
  final pending = Completer<Uri>();

  @override
  Future<Uri> authorize(Uri url, Duration timeout, OAuthUrlLauncher launch) =>
      pending.future;

  @override
  Future<Uri> waitForCallback(Duration timeout) => pending.future;

  @override
  Future<void> close() async {
    if (!pending.isCompleted) {
      pending.completeError(
        const OAuthCallbackException('cancelled', cancelled: true),
      );
    }
  }
}

void main() {
  test('loopback offers a return link without exposing the code', () async {
    final browser = _Browser();
    final callback = await createMobileLoopbackOAuthCallbackForTesting(browser);
    addTearDown(callback.close);
    final pending = callback.authorize(
      Uri.parse('https://auth.openai.com/oauth/authorize?state=nonce'),
      const Duration(seconds: 3),
      (_) async => true,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      callback.redirectUri.replace(query: 'state=nonce&code=private-auth-code'),
    );
    request.followRedirects = false;
    final response = await request.close();
    final html = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok);
    expect(html, contains('Return to Moru'));
    final returnUrl = browser.redirectUri.replace(query: 'state=nonce');
    final escapedUrl = const HtmlEscape().convert(returnUrl.toString());
    expect(html, contains('href="$escapedUrl"'));
    expect(html, isNot(contains('private-auth-code')));
    expect(response.headers.value('cache-control'), 'no-store');
    expect(response.headers.value('referrer-policy'), 'no-referrer');
    expect((await pending).queryParameters['code'], 'private-auth-code');
  });
}

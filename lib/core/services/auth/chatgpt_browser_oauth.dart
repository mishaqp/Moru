part of 'provider_oauth_adapter.dart';

/// Keep the registered redirect and PKCE verifier, but do not make an Android
/// loopback listener or a second native intent the only way to finish login.
Future<ProviderOAuthCredentials> _loginChatGptInBrowser(
  ChatGptOAuthAdapter adapter,
  OAuthWire wire,
  OAuthCancellation cancellation,
  OAuthPromptHandler onPrompt,
  OAuthUrlLauncher launcher,
) async {
  final redirect = Uri.parse('http://localhost:1455/auth/callback');
  final verifier = oauthRandomString(32);
  final state = oauthRandomString(24);
  OAuthCallback? callback;
  try {
    callback = await openOAuthCallback(
      Uri.parse('https://auth.openai.com'),
      loopbackRedirect: redirect,
      expectedState: state,
    );
  } on SocketException {
    // A busy/unavailable local port must not prevent browser + manual login.
    RequestLogger.logLine('[OAUTH] browser-callback listener-unavailable');
  }
  final received = Completer<Uri>();
  received.future.ignore();
  var accepting = true;
  var closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    accepting = false;
    try {
      await callback?.close();
    } catch (_) {
      // Native cleanup must not replace a successful token exchange or cancel.
      RequestLogger.logLine('[OAUTH] browser-callback cleanup-failed');
    }
  }

  bool submit(String input) {
    if (!accepting || cancellation.isCancelled || received.isCompleted) {
      return false;
    }
    final uri = parseCodexOAuthCallback(input, state);
    if (uri == null) return false;
    received.complete(uri);
    return true;
  }

  final url = Uri.https('auth.openai.com', '/oauth/authorize', {
    'response_type': 'code',
    'client_id': adapter.provider.clientId,
    'redirect_uri': redirect.toString(),
    'scope': adapter.provider.scope,
    'code_challenge': oauthPkceChallenge(verifier),
    'code_challenge_method': 'S256',
    'state': state,
    'id_token_add_organizations': 'true',
    'codex_cli_simplified_flow': 'true',
    'originator': 'kelivo',
  });
  unawaited(cancellation.whenCancelled.then((_) => close()));
  try {
    cancellation.check();
    await onPrompt(
      OAuthLoginPrompt(
        url: url,
        browserAuthorization: true,
        submitAuthorizationCode: submit,
      ),
    );
    cancellation.check();
    if (!received.isCompleted) {
      unawaited(() async {
        try {
          final local = callback;
          if (local == null) {
            await launcher(url);
            return;
          }
          final result = await local.authorize(
            url,
            const Duration(minutes: 10),
            launcher,
          );
          if (!accepting || cancellation.isCancelled || received.isCompleted) {
            return;
          }
          if (!submit(result.toString())) {
            received.completeError(
              const ProviderOAuthException(
                ProviderOAuthFailure.invalidResponse,
                code: 'browser-callback/mismatch',
              ),
            );
          }
        } on OAuthCallbackException {
          // The user can return from a failed localhost page and paste its URL.
          RequestLogger.logLine(
            '[OAUTH] browser-callback manual-entry-available',
          );
        } on TimeoutException {
          // The single deadline below also bounds manual entry.
        } catch (error, stack) {
          if (accepting && !received.isCompleted) {
            received.completeError(error, stack);
          }
        }
      }());
    }
    final result = await Future.any<Uri>([
      received.future,
      cancellation.whenCancelled.then(
        (_) =>
            throw const ProviderOAuthException(ProviderOAuthFailure.cancelled),
      ),
    ]).timeout(const Duration(minutes: 10));
    accepting = false;
    cancellation.check();
    if (result.queryParameters.containsKey('error')) {
      throw const ProviderOAuthException(ProviderOAuthFailure.denied);
    }
    final credentials = await adapter._exchange(
      wire,
      result.queryParameters['code']!,
      verifier,
      redirect.toString(),
    );
    cancellation.check();
    return credentials;
  } on TimeoutException {
    throw const ProviderOAuthException(
      ProviderOAuthFailure.timeout,
      code: 'browser-callback/timeout',
    );
  } finally {
    await close();
  }
}

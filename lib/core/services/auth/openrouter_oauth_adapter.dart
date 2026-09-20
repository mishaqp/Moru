part of 'provider_oauth_adapter.dart';

/// OpenRouter's official OAuth PKCE login (openrouter.ai `/auth` +
/// `/api/v1/auth/keys`). Independent of, and does not replace, the existing
/// manual API-key OpenRouter provider.
///
/// Per OpenRouter's docs (confirmed, not re-derived here): the authorize
/// request takes `callback_url`, `code_challenge`, `code_challenge_method`
/// and `key_label`, and has no `state` parameter; the exchange returns only
/// `{key, user_id}` with no refresh token and no expiry.
class OpenRouterOAuthAdapter extends ProviderOAuthAdapter {
  @override
  OAuthProvider get provider => OAuthProvider.openrouter;

  @override
  Future<ProviderOAuthCredentials> login(
    OAuthWire wire,
    OAuthCancellation cancellation,
    OAuthPromptHandler onPrompt, {
    bool deviceCode = true,
    OAuthUrlLauncher? launcher,
  }) async {
    final callback = await OpenRouterOAuthCallback.bind();
    final verifier = oauthRandomString(32);
    final received = Completer<String>();
    final url = Uri.https('openrouter.ai', '/auth', {
      'callback_url': callback.redirectUri.toString(),
      'code_challenge': oauthPkceChallenge(verifier),
      'code_challenge_method': 'S256',
      'key_label': _openRouterKeyLabel,
    });
    bool submit(String input) {
      if (cancellation.isCancelled || received.isCompleted) return false;
      final code = _openRouterAuthorizationCode(input);
      if (code == null) return false;
      received.complete(code);
      return true;
    }

    unawaited(cancellation.whenCancelled.then((_) => callback.close()));
    try {
      cancellation.check();
      // Started before the prompt so a very fast browser redirect is never
      // missed while onPrompt/launch are still running. It may go unused
      // (e.g. a synchronous manual submit during onPrompt), so it must not
      // be reported as an unhandled rejection when close() later rejects it.
      final loopback = callback.waitForCallback(const Duration(minutes: 10))
        ..ignore();
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
            final opened =
                await (launcher ??
                        (uri) => launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        ))
                    .call(url);
            if (!opened) return;
            final result = await loopback;
            if (cancellation.isCancelled || received.isCompleted) return;
            if (result.queryParameters.containsKey('error')) {
              received.completeError(
                const ProviderOAuthException(ProviderOAuthFailure.denied),
              );
            } else if (!submit(result.toString())) {
              received.completeError(
                const ProviderOAuthException(
                  ProviderOAuthFailure.invalidResponse,
                ),
              );
            }
          } on TimeoutException {
            // The shared deadline below also covers manual code entry.
          } catch (error, stack) {
            if (!received.isCompleted) received.completeError(error, stack);
          }
        }());
      }
      final code = await Future.any<String>([
        received.future,
        cancellation.whenCancelled.then(
          (_) => throw const ProviderOAuthException(
            ProviderOAuthFailure.cancelled,
          ),
        ),
      ]).timeout(const Duration(minutes: 10));
      cancellation.check();
      final result = await _exchange(wire, code, verifier);
      await callback.close();
      return result;
    } on TimeoutException {
      // A plain try/finally with an `await` in the finally clause makes an
      // already-handled exception look unhandled to the zone here, so every
      // exit path closes the callback explicitly instead.
      await callback.close();
      throw const ProviderOAuthException(ProviderOAuthFailure.timeout);
    } catch (_) {
      await callback.close();
      rethrow;
    }
  }

  Future<ProviderOAuthCredentials> _exchange(
    OAuthWire wire,
    String code,
    String verifier,
  ) async {
    final response = await wire.request(
      provider.tokenEndpoint,
      json: {
        'code': code,
        'code_verifier': verifier,
        'code_challenge_method': 'S256',
      },
    );
    if (!response.ok) {
      throw _requestFailure(response, null, secrets: [code, verifier]);
    }
    return credentials(response.data);
  }

  @override
  ProviderOAuthCredentials credentials(
    Map<String, dynamic> data, {
    ProviderOAuthCredentials? stored,
    String? deviceId,
  }) {
    final key = oauthString(data['key']);
    if (key == null) {
      throw const ProviderOAuthException(ProviderOAuthFailure.invalidResponse);
    }
    return ProviderOAuthCredentials(
      accessToken: key,
      refreshToken: null,
      expiresAt: null,
      sessionId: stored?.sessionId ?? const Uuid().v4(),
      accountId: oauthString(data['user_id']) ?? stored?.accountId,
    );
  }

  /// OpenRouter's exchanged key has no refresh token and no expiry, so there
  /// is nothing to refresh — this must never make a network call.
  /// `ProviderOAuthService._refresh()` already treats a `loginRequired`
  /// exception from `refresh()` as "please reconnect", which is exactly the
  /// right behavior for a 401 here.
  @override
  Future<ProviderOAuthCredentials> refresh(
    OAuthWire wire,
    ProviderOAuthCredentials stored,
  ) async {
    throw const ProviderOAuthException(ProviderOAuthFailure.loginRequired);
  }

  @override
  Future<List<Map<String, dynamic>>> models(
    OAuthWire wire,
    ProviderOAuthCredentials credentials,
  ) async {
    final rows = <Map<String, dynamic>>[];
    final seenNext = <String>{};
    String url = Uri.parse('${provider.baseUrl}/models/user')
        .replace(
          queryParameters: {'output_modalities': 'text', 'limit': '1000'},
        )
        .toString();
    while (true) {
      final result = await get(wire, url, credentials);
      if (result['data'] is! List) {
        throw const ProviderOAuthException(
          ProviderOAuthFailure.invalidResponse,
        );
      }
      for (final row in (result['data'] as List).whereType<Map>()) {
        final model = row.cast<String, dynamic>();
        final architecture = oauthMap(model['architecture']);
        final output = (architecture['output_modalities'] as List? ?? const [])
            .whereType<String>()
            .toSet();
        // Defense in depth beyond output_modalities=text: OpenRouter's own
        // "Jev" (text -> decisions) alpha family, and anything that isn't
        // genuinely a text-output chat model, must never reach the catalog.
        if (!output.contains('text') || output.contains('decisions')) {
          continue;
        }
        final inputModalities =
            (architecture['input_modalities'] as List? ?? const [])
                .whereType<String>()
                .toList();
        final supportedParameters =
            (model['supported_parameters'] as List? ?? const [])
                .whereType<String>()
                .toList();
        rows.add({
          'id': model['id'],
          'display_name': model['name'],
          'input_modalities': inputModalities,
          'supports_image_in': inputModalities.contains('image'),
          'supports_reasoning': supportedParameters.contains('reasoning'),
        });
      }
      final next = oauthString(oauthMap(result['links'])['next']);
      if (next == null) break;
      if (!seenNext.add(next)) {
        throw const ProviderOAuthException(
          ProviderOAuthFailure.invalidResponse,
        );
      }
      url = next;
    }
    return rows;
  }

  @override
  Future<ProviderUsageSnapshot> usage(
    OAuthWire wire,
    ProviderOAuthCredentials credentials,
  ) async {
    final result = await get(wire, '${provider.baseUrl}/key', credentials);
    final data = oauthMap(result['data']);
    final limit = oauthNumber(data['limit']);
    final used = oauthNumber(data['usage']);
    final rateLimit = oauthMap(data['rate_limit']);
    return ProviderUsageSnapshot(
      windows: [
        ProviderUsageWindow(
          id: 'credits',
          unit: 'usd',
          used: used,
          limit: limit,
          usedPercent: limit != null && limit > 0 && used != null
              ? (used / limit * 100).clamp(0, 100)
              : null,
          label: oauthString(rateLimit['note']),
        ),
      ],
      fetchedAt: DateTime.now(),
    );
  }
}

const _openRouterKeyLabel = 'Moru';

/// Accept either a bare authorization code or a pasted callback URL
/// containing one. There is no `state` to validate against here (OpenRouter
/// does not have one); the loopback listener's nonce path is what binds a
/// browser redirect to this specific login attempt.
String? _openRouterAuthorizationCode(String input) {
  var value = input.trim();
  if (value.isEmpty || value.length > 16384) return null;
  final uri = Uri.tryParse(value);
  if (uri?.hasScheme == true) {
    value = uri!.queryParameters['code'] ?? '';
  } else if (value.contains('code=')) {
    final params = Uri.splitQueryString(
      value.replaceFirst(RegExp(r'^[?#]'), ''),
    );
    value = params['code'] ?? '';
  }
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;
  return value;
}

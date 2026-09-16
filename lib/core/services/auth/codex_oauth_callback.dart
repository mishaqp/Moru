/// Parse only the complete callback from the active Codex PKCE login.
/// Never accept a bare code: without state it cannot be tied to this attempt.
Uri? parseCodexOAuthCallback(String input, String expectedState) {
  final value = input.trim();
  if (value.isEmpty || value.length > 16384 || expectedState.isEmpty) {
    return null;
  }
  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'http' ||
        !{'localhost', '127.0.0.1', '::1'}.contains(uri.host) ||
        uri.port != 1455 ||
        uri.path != '/auth/callback' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    final params = uri.queryParametersAll;
    if (params['state']?.length != 1 ||
        params['state']!.single != expectedState) {
      return null;
    }
    final codes = params['code'];
    final errors = params['error'];
    final result = codes ?? errors;
    if ((codes != null && errors != null) ||
        result == null ||
        result.length != 1 ||
        result.single.isEmpty ||
        result.single.length > 4096 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(result.single)) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

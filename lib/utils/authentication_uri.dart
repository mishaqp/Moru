/// Whether an HTTP address carries authentication material or points at a
/// supported provider's authorization page. These addresses must not be kept
/// in browser journals, even after the page title changes.
bool isAuthenticationUri(Uri uri) {
  if (!uri.isScheme('http') && !uri.isScheme('https')) return false;

  if (_hasAuthenticationFields(uri.query)) return true;
  var fragment = uri.fragment;
  try {
    fragment = Uri.decodeComponent(fragment);
  } on FormatException {
    // Still inspect any valid field names in a malformed fragment.
  }
  if (_hasAuthenticationFields(fragment)) return true;

  if (!_authorizationHosts.contains(uri.host.toLowerCase())) return false;
  var path = uri.path.toLowerCase();
  try {
    path = '/${uri.pathSegments.join('/').toLowerCase()}';
  } on FormatException {
    // Keep checking an otherwise valid URI with malformed path escapes.
  }
  return _authorizationPath.hasMatch(path);
}

const _authenticationFields = {
  'state',
  'nonce',
  'code',
  'device',
  'devicecode',
  'deviceauthid',
  'usercode',
  'authorizationcode',
  'accesstoken',
  'refreshtoken',
  'idtoken',
  'token',
  'authtoken',
  'oauthtoken',
  'oauthverifier',
  'codechallenge',
  'codeverifier',
  'clientsecret',
};

const _authorizationHosts = {
  'auth.openai.com',
  'auth0.openai.com',
  'auth.anthropic.com',
  'claude.com',
  'claude.ai',
  'platform.claude.com',
  'console.anthropic.com',
  'platform.openai.com',
  'chat.openai.com',
  'chatgpt.com',
};

final _authorizationPath = RegExp(
  r'^/(?:authorize|oauth|login|auth|deviceauth|codex/device|u/login)(?:/|$)',
);
final _fieldSeparator = RegExp(r'[&?;]');
final _fieldFormatting = RegExp(r'[_-]');

bool _hasAuthenticationFields(String fields) {
  for (final field in fields.split(_fieldSeparator)) {
    var key = field.split('=').first;
    try {
      key = Uri.decodeQueryComponent(key);
    } on FormatException {
      // A malformed value elsewhere must not hide a valid parameter name.
    }
    if (_authenticationFields.contains(
      key.toLowerCase().replaceAll(_fieldFormatting, ''),
    )) {
      return true;
    }
  }
  return false;
}

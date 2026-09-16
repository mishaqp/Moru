import 'dart:async';
import 'dart:io';

/// Fixed labels only: URLs, response bodies and exception text may hold tokens.
String oauthRequestStage(Uri uri) => switch (uri.path) {
  '/api/accounts/deviceauth/usercode' => 'device-authorization',
  '/api/accounts/deviceauth/token' => 'device-poll',
  '/oauth/token' => 'token-exchange',
  _ => 'oauth-request',
};

/// Dio wraps transport errors in ClientException. Inspect but never emit its
/// text: it can contain the complete request URI, proxy credentials or tokens.
String oauthTransportReason(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is TlsException) return 'tls';
  final text = error.toString().toLowerCase();
  if (text.contains('handshakeexception') ||
      text.contains('certificate_verify_failed') ||
      text.contains('certificate verify failed') ||
      text.contains('badcertificate')) {
    return 'tls';
  }
  if (text.contains('failed host lookup') ||
      text.contains('name or service not known') ||
      text.contains('nodename nor servname') ||
      text.contains('name resolution')) {
    return 'dns';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'timeout';
  }
  if (text.contains('connection refused')) return 'connection-refused';
  if (text.contains('network is unreachable') ||
      text.contains('network unreachable') ||
      text.contains('no route to host')) {
    return 'network-unreachable';
  }
  if (text.contains('connection reset') || text.contains('connection closed')) {
    return 'connection-closed';
  }
  return 'transport';
}

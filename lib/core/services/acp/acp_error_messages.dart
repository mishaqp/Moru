import 'dart:io';

import '../../../l10n/app_localizations.dart';
import 'acp_agent.dart';

export 'acp_connection.dart' show AcpFailureKind;

/// The agent's command is not in the Linux environment: the shell's
/// "command not found" status, e.g. after switching to a fresh distribution.
bool isAcpCommandMissing(Object error) {
  final text = error is AcpError ? error.message : error.toString();
  return text.contains('exited (code 127)');
}

AcpFailureKind? classifyAcpFailure(Object error) {
  if (error is AcpError && error.failureKind != null) return error.failureKind;
  if (error is SocketException) return AcpFailureKind.network;
  if (error is AcpError && error.code == 401) {
    return AcpFailureKind.apiKey;
  }
  final raw = error is AcpError
      ? '${error.message}\n${error.data ?? ''}'
      : error.toString();
  final text = raw.toLowerCase().replaceAll(RegExp(r'[_-]'), ' ');
  if (text.contains('invalid provider headers')) return AcpFailureKind.headers;
  if (RegExp(
    r'\b401\b|(?:invalid|incorrect) api\s*key|api\s*key.{0,40}(?:invalid|incorrect)',
  ).hasMatch(text)) {
    return AcpFailureKind.apiKey;
  }
  if (RegExp(r'modelnotfound|model not found|unknown model').hasMatch(text) ||
      RegExp(
        r'\bmodel(?:\s+(?:[\x60\x22\x27][^\x60\x22\x27]+[\x60\x22\x27]|[a-z0-9_./:-]+))?\s+(?:is\s+)?(?:not found|does not exist|not available)',
      ).hasMatch(raw.toLowerCase())) {
    return AcpFailureKind.model;
  }
  if (RegExp(
    r'\b(?:enotfound|eai again|econnrefused|econnreset|enetunreach|ehostunreach)\b|failed host lookup|fetch failed|network (?:error|unreachable|is unreachable|connection)|no (?:network|internet)|connection (?:refused|reset)|socketexception',
  ).hasMatch(text)) {
    return AcpFailureKind.network;
  }
  return null;
}

String? acpFailureMessage(AcpFailureKind? kind, AppLocalizations l10n) =>
    switch (kind) {
      AcpFailureKind.apiKey => l10n.agentsErrorApiKey,
      AcpFailureKind.model => l10n.agentsErrorModel,
      AcpFailureKind.network => l10n.agentsErrorNetwork,
      AcpFailureKind.headers => l10n.agentsErrorHeaders,
      null => null,
    };

/// Keep unknown errors intact. Recognized errors retain their protocol code
/// and diagnostic data, while their visible message no longer exposes stderr.
Object localizeAcpError(Object error, AppLocalizations l10n) {
  final message = acpFailureMessage(classifyAcpFailure(error), l10n);
  if (message == null) return error;
  return AcpError(
    error is AcpError ? error.code : AcpError.internalError,
    message,
    error is AcpError ? error.data : null,
    classifyAcpFailure(error),
  );
}

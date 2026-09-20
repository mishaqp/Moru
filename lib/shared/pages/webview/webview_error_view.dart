import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// Replaces the WebView area when the main frame itself failed to load
/// (`WebResourceError.isForMainFrame == true`). A subresource error (an
/// image, a script, an iframe) never reaches this widget -- it stays logged
/// to the diagnostics console only, exactly as before.
class WebViewErrorView extends StatelessWidget {
  const WebViewErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final WebResourceError error;
  final VoidCallback onRetry;

  String _reason(AppLocalizations l10n) {
    switch (error.errorType) {
      case WebResourceErrorType.hostLookup:
      case WebResourceErrorType.connect:
        return l10n.browserErrorReasonConnect;
      case WebResourceErrorType.timeout:
        return l10n.browserErrorReasonTimeout;
      case WebResourceErrorType.badUrl:
      case WebResourceErrorType.unsupportedScheme:
        return l10n.browserErrorReasonBadUrl;
      case WebResourceErrorType.failedSslHandshake:
        return l10n.browserErrorReasonSsl;
      default:
        return error.description.trim().isNotEmpty
            ? error.description.trim()
            : l10n.browserErrorTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('browser_main_frame_error'),
      color: cs.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Lucide.TriangleAlert,
                size: 36,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.browserErrorTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _reason(l10n),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('browser_error_retry_button'),
                onPressed: onRetry,
                icon: const Icon(Lucide.RefreshCw, size: 16),
                label: Text(l10n.browserErrorRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

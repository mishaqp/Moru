import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// One captured `console.*` message from the page's own JavaScript, relayed
/// through the `Console` JS channel `webview_page.dart` installs on every
/// WebView (agent session or plain link/browser).
class ConsoleMessage {
  ConsoleMessage({
    required this.level,
    required this.message,
    this.source,
    this.line,
  });

  final String level;
  final String message;
  final String? source;
  final int? line;
}

/// The diagnostics console sheet, unchanged from the pre-split
/// `webview_page.dart`: same list, same level coloring, same
/// `messageWebViewConsoleLogs`/`messageWebViewNoConsoleMessages` copy. Moved
/// here so it can be reused from the top bar's overflow menu without
/// growing the shell file.
class ConsoleSheet extends StatelessWidget {
  const ConsoleSheet({super.key, required this.messages});

  final List<ConsoleMessage> messages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.messageWebViewConsoleLogs,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (messages.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  l10n.messageWebViewNoConsoleMessages,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: messages.length,
                itemBuilder: (ctx, i) {
                  final m = messages[i];
                  Color c;
                  switch (m.level) {
                    case 'ERROR':
                      c = cs.error;
                      break;
                    case 'WARN':
                    case 'WARNING':
                      c = cs.secondary;
                      break;
                    default:
                      c = cs.onSurface;
                      break;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${m.level}: ${m.message}\n${l10n.moruConsoleSource('${m.source ?? ''}${m.line != null ? ':${m.line}' : ''}')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: c,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

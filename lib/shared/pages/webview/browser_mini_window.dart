import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../features/home/services/browser_agent_actions.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/snackbar.dart' show rootNavigatorKey;
import '../../../theme/app_font_weights.dart';
import 'webview_page.dart';

/// Opens the shared agent browser: expands the mini window when the browser
/// is minimized, otherwise starts a new session at [startUrl].
Future<void> openSharedBrowser({
  String startUrl = 'https://www.google.com',
}) async {
  final session = BrowserAgentSession.instance;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  if (session.minimized.value) {
    await session.releaseMiniWindow();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const WebViewPage(agentSession: true),
        ),
      ),
    );
    return;
  }
  if (session.isAttached) return;
  unawaited(
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WebViewPage(url: startUrl, agentSession: true),
      ),
    ),
  );
}

/// The minimized shared browser, floating above every screen like a
/// picture-in-picture window: drag it by the header, tap to expand, close
/// with ✕. The page underneath stays interactive.
class BrowserMiniWindow extends StatefulWidget {
  const BrowserMiniWindow({super.key});

  static const Key windowKey = ValueKey<String>('browser-mini-window');
  static const Key expandKey = ValueKey<String>('browser-mini-expand');
  static const Key closeKey = ValueKey<String>('browser-mini-close');

  @override
  State<BrowserMiniWindow> createState() => _BrowserMiniWindowState();
}

class _BrowserMiniWindowState extends State<BrowserMiniWindow> {
  /// Distance of the window from the bottom-right corner of the safe area.
  Offset _fromBottomRight = const Offset(12, 150);

  @override
  Widget build(BuildContext context) {
    final session = BrowserAgentSession.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: session.minimized,
      builder: (context, minimized, _) {
        final controller = session.controller;
        if (!minimized || controller == null) return const SizedBox.shrink();
        final media = MediaQuery.of(context);
        final width = (media.size.width * 0.46).clamp(150.0, 240.0);
        final height = width * 1.4;
        final maxRight = media.size.width - width - 8;
        final maxBottom = media.size.height - height - media.padding.top - 8;
        final offset = Offset(
          _fromBottomRight.dx.clamp(8.0, maxRight < 8 ? 8.0 : maxRight),
          _fromBottomRight.dy.clamp(
            media.padding.bottom + 8,
            maxBottom < 8 ? 8.0 : maxBottom,
          ),
        );
        return Positioned(
          right: offset.dx,
          bottom: offset.dy,
          width: width,
          height: height,
          child: _MiniWindowCard(
            key: BrowserMiniWindow.windowKey,
            controller: controller,
            onDrag: (delta) => setState(() {
              _fromBottomRight = Offset(
                offset.dx - delta.dx,
                offset.dy - delta.dy,
              );
            }),
          ),
        );
      },
    );
  }
}

class _MiniWindowCard extends StatelessWidget {
  const _MiniWindowCard({
    super.key,
    required this.controller,
    required this.onDrag,
  });

  final WebViewController controller;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final session = BrowserAgentSession.instance;
    return Material(
      elevation: 10,
      color: cs.surface,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onDrag(details.delta),
            onTap: () => unawaited(openSharedBrowser()),
            child: Container(
              height: 36,
              color: cs.surfaceContainerHigh,
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Icon(Lucide.Globe, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ValueListenableBuilder<BrowserActivity?>(
                      valueListenable: session.currentActivity,
                      builder: (context, activity, _) {
                        final running =
                            activity?.outcome == BrowserActivityOutcome.running;
                        return Text(
                          running
                              ? browserActivityLabel(
                                  activity!,
                                  ru:
                                      Localizations.localeOf(
                                        context,
                                      ).languageCode ==
                                      'ru',
                                )
                              : l10n.browserMiniTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: AppFontWeights.semibold,
                            color: running ? cs.primary : cs.onSurface,
                          ),
                        );
                      },
                    ),
                  ),
                  _HeaderButton(
                    key: BrowserMiniWindow.expandKey,
                    icon: Lucide.Maximize2,
                    tooltip: l10n.browserMiniExpand,
                    onTap: () => unawaited(openSharedBrowser()),
                  ),
                  _HeaderButton(
                    key: BrowserMiniWindow.closeKey,
                    icon: Lucide.X,
                    tooltip: l10n.commonClose,
                    onTap: () => unawaited(session.closeMinimized()),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(openSharedBrowser()),
              // The small preview is watch-only; interacting happens in the
              // expanded page.
              child: IgnorePointer(
                child: WebViewWidget(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

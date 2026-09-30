import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_http_auth.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/snackbar.dart' show rootNavigatorKey;
import '../../../theme/app_font_weights.dart';
import 'webview_page.dart';
import 'webview_site_handlers.dart';
import 'webview_status_banner.dart';

/// Opens the shared agent browser: expands the mini window when the browser
/// is minimized, otherwise starts a new session at [startUrl]. With
/// [newTab], a browser that is already open shows [startUrl] in a new tab.
Future<void> openSharedBrowser({
  String startUrl = 'https://www.google.com',
  bool newTab = false,
  BrowserHttpAuth? authentication,
}) async {
  final session = BrowserAgentSession.instance;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  final wasAttached = session.isAttached;
  WebViewController? prepared;
  Future<void> addTab() async {
    if (authentication != null && !authentication.isActive) {
      throw const BrowserHttpAuthException();
    }
    final result = await session.newTab(
      url: startUrl,
      preparedController: prepared,
      mayOpen: authentication == null ? null : () => authentication.isActive,
    );
    if (authentication != null &&
        (result['ok'] != true || !authentication.isActive)) {
      if (result['ok'] == true) {
        await session.closeTab(result['tab_id'] as String);
      }
      throw const BrowserHttpAuthException();
    }
  }

  try {
    if (authentication != null) {
      // Never authorize an existing controller: Android's challenge gives no
      // port. Bootstrap privately before the controller joins tabs/user scripts.
      if (startUrl != authentication.origin.toString()) {
        throw const BrowserHttpAuthException();
      }
      prepared = createSiteAwareController(
        visible: () => session.isRouteCurrent && !session.minimized.value,
      );
      await authentication.bootstrap(prepared);
      await prepareAgentBrowserController(prepared);
      if (!authentication.isActive || (wasAttached && !session.isAttached)) {
        throw const BrowserHttpAuthException();
      }
      newTab = true;
    }
    if (session.minimized.value) {
      await session.releaseMiniWindow();
      if (authentication != null && !authentication.isActive) {
        throw const BrowserHttpAuthException();
      }
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const WebViewPage(agentSession: true),
          ),
        ),
      );
      if (newTab) {
        // The page takes the parked browser back in its first frame.
        await WidgetsBinding.instance.endOfFrame;
        await addTab();
      }
      return;
    }
    if (session.isAttached) {
      if (newTab) await addTab();
      return;
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WebViewPage(
            url: startUrl,
            agentSession: true,
            preparedController: prepared,
          ),
        ),
      ),
    );
  } catch (_) {
    if (authentication == null) rethrow;
    final abandoned = prepared;
    if (abandoned != null) {
      // There is no native controller disposal API. Stop its page and release
      // our reference; it never joins the shared session on a failed handoff.
      try {
        await abandoned.setJavaScriptMode(JavaScriptMode.disabled);
        await abandoned.setNavigationDelegate(
          NavigationDelegate(
            onHttpAuthRequest: (request) => request.onCancel(),
          ),
        );
        unawaited(
          abandoned
              .loadRequest(Uri.parse('about:blank'))
              .catchError((Object _) {}),
        );
      } catch (_) {}
    }
    throw const BrowserHttpAuthException();
  }
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

  /// While a finger drags the window it follows at once; on release it
  /// glides to the nearer side of the screen.
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final session = BrowserAgentSession.instance;
    return ListenableBuilder(
      // The tab list too: the model may switch tabs while minimized.
      listenable: Listenable.merge([session.minimized, session.tabs]),
      builder: (context, _) {
        final minimized = session.minimized.value;
        final controller = session.controller;
        if (!minimized || controller == null) return const SizedBox.shrink();
        final media = MediaQuery.of(context);
        final width = (media.size.width * 0.46).clamp(150.0, 240.0);
        final height = width * 1.4;
        final maxRight = media.size.width - width - 8;
        final maxBottom = media.size.height - height - media.padding.top - 8;
        Offset clamped(Offset o) => Offset(
          o.dx.clamp(8.0, maxRight < 8 ? 8.0 : maxRight),
          o.dy.clamp(media.padding.bottom + 8, maxBottom < 8 ? 8.0 : maxBottom),
        );
        final offset = clamped(_fromBottomRight);
        return AnimatedPositioned(
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          right: offset.dx,
          bottom: offset.dy,
          width: width,
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              alignment: Alignment.bottomRight,
              child: Opacity(
                opacity: ((scale - 0.85) / 0.15).clamp(0.0, 1.0),
                child: child,
              ),
            ),
            child: _MiniWindowCard(
              key: BrowserMiniWindow.windowKey,
              controller: controller,
              // From the state, not from this build's offset: several moves
              // (and the lift) may arrive before the next build.
              onDrag: (delta) => setState(() {
                _dragging = true;
                _fromBottomRight = clamped(
                  Offset(
                    _fromBottomRight.dx - delta.dx,
                    _fromBottomRight.dy - delta.dy,
                  ),
                );
              }),
              onDragEnd: () => setState(() {
                _dragging = false;
                final right = clamped(_fromBottomRight).dx;
                final centre = media.size.width - right - width / 2;
                _fromBottomRight = Offset(
                  centre < media.size.width / 2 ? maxRight : 12,
                  _fromBottomRight.dy,
                );
              }),
            ),
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
    required this.onDragEnd,
  });

  final WebViewController controller;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final session = BrowserAgentSession.instance;
    return ValueListenableBuilder<BrowserActivity?>(
      valueListenable: session.currentActivity,
      builder: (context, activity, _) {
        final running = activity?.outcome == BrowserActivityOutcome.running;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: running
                  ? cs.primary.withValues(alpha: 0.8)
                  : cs.outlineVariant.withValues(alpha: 0.6),
              width: running ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (running ? cs.primary : Colors.black).withValues(
                  alpha: running ? 0.28 : 0.22,
                ),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => onDrag(details.delta),
                  onPanEnd: (_) => onDragEnd(),
                  onTap: () => unawaited(openSharedBrowser()),
                  child: Container(
                    height: 38,
                    color: cs.surfaceContainerHigh,
                    padding: const EdgeInsets.only(left: 10),
                    child: Row(
                      children: [
                        Expanded(child: _MiniAddress(session: session)),
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
                ValueListenableBuilder<bool>(
                  valueListenable: session.pageLoading,
                  builder: (context, loading, _) => SizedBox(
                    height: 2,
                    child: loading
                        ? const LinearProgressIndicator(minHeight: 2)
                        : null,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(openSharedBrowser()),
                    // The small preview is watch-only; interacting happens
                    // in the expanded page.
                    child: IgnorePointer(
                      child: WebViewWidget(
                        key: ObjectKey(controller),
                        controller: controller,
                      ),
                    ),
                  ),
                ),
                if (running)
                  BrowserActivityStrip(activity: activity!, compact: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lock and domain of the page the mini window shows.
class _MiniAddress extends StatelessWidget {
  const _MiniAddress({required this.session});

  final BrowserAgentSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: session.pageUrl,
      builder: (context, url, _) {
        final uri = url == null ? null : Uri.tryParse(url);
        final host = uri?.host ?? '';
        final secure = uri?.scheme == 'https';
        return Row(
          children: [
            Icon(
              host.isEmpty
                  ? Lucide.Globe
                  : (secure ? Lucide.Lock : Lucide.LockOpen),
              size: 13,
              color: host.isEmpty || secure
                  ? cs.onSurface.withValues(alpha: 0.6)
                  : cs.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                host.isEmpty
                    ? l10n.browserMiniTitle
                    : (host.startsWith('www.') ? host.substring(4) : host),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (session.tabs.value.length > 1)
              Container(
                key: const ValueKey('browser-mini-tab-count'),
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${session.tabs.value.length}',
                  style: TextStyle(fontSize: 10, color: cs.onSurface),
                ),
              ),
          ],
        );
      },
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

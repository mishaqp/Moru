import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_guard.dart';
import '../../../features/home/services/browser_agent_actions.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// Strips under the browser's address bar: the check a site shows (captcha,
/// Cloudflare, rate limit), and what the chat's assistant is doing in the
/// page with a Stop button. [showActivity] is false while the page's own
/// Ask-AI panel shows its status, so one run is not shown twice.
class WebViewStatusBanner extends StatelessWidget {
  const WebViewStatusBanner({super.key, required this.showActivity});

  static const Key challengeKey = ValueKey<String>('browser-challenge-banner');
  static const Key activityKey = ValueKey<String>('browser-agent-activity');
  static const Key stopKey = ValueKey<String>('browser-agent-stop');

  final bool showActivity;

  @override
  Widget build(BuildContext context) {
    final session = BrowserAgentSession.instance;
    return ValueListenableBuilder<BrowserChallenge?>(
      valueListenable: session.challenge,
      builder: (context, challenge, _) =>
          ValueListenableBuilder<BrowserActivity?>(
            valueListenable: session.currentActivity,
            builder: (context, activity, _) {
              final running =
                  showActivity &&
                  activity?.outcome == BrowserActivityOutcome.running;
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (challenge != null) _ChallengeStrip(challenge),
                    if (running) BrowserActivityStrip(activity: activity!),
                  ],
                ),
              );
            },
          ),
    );
  }
}

class _ChallengeStrip extends StatelessWidget {
  const _ChallengeStrip(this.challenge);

  final BrowserChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final (icon, text) = switch (challenge.kind) {
      'rate_limited' => (Lucide.Timer, l10n.browserChallengeRateLimited),
      'access_denied' => (Lucide.Ban, l10n.browserChallengeDenied),
      _ => (Lucide.ShieldAlert, l10n.browserChallengeVerify),
    };
    return Container(
      key: WebViewStatusBanner.challengeKey,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the assistant does in the browser right now, with a pulsing dot and
/// Stop; used by the browser page and the mini window.
class BrowserActivityStrip extends StatelessWidget {
  const BrowserActivityStrip({
    super.key,
    required this.activity,
    this.compact = false,
  });

  final BrowserActivity activity;

  /// Smaller text and no outer margin, for the mini window.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final label = browserActivityLabel(
      activity,
      ru: Localizations.localeOf(context).languageCode == 'ru',
    );
    return Container(
      key: WebViewStatusBanner.activityKey,
      margin: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: EdgeInsets.only(left: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: compact ? 0.9 : 0.6),
        borderRadius: BorderRadius.circular(compact ? 0 : 14),
      ),
      child: Row(
        children: [
          const _PulsingDot(),
          SizedBox(width: compact ? 6 : 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                fontWeight: AppFontWeights.semibold,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            key: WebViewStatusBanner.stopKey,
            tooltip: l10n.browserComposerStopTooltip,
            visualDensity: VisualDensity.compact,
            iconSize: compact ? 15 : 18,
            color: cs.onPrimaryContainer,
            onPressed: BrowserAgentSession.instance.requestStop,
            icon: const Icon(Lucide.CircleStop),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

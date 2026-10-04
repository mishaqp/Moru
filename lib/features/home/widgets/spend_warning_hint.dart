import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/model_catalog/model_catalog.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/widgets/token_display_widget.dart';
import '../../stats/widgets/spend_limits_settings.dart';
import '../services/spend_control_service.dart';
import 'chat_token_sheet.dart';

/// A small composer hint, refreshed on completed usage and local midnight.
class SpendWarningHint extends StatefulWidget {
  const SpendWarningHint({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<SpendWarningHint> createState() => _SpendWarningHintState();
}

class _SpendWarningHintState extends State<SpendWarningHint>
    with WidgetsBindingObserver {
  String? _signature;
  Future<SpendControlStatus>? _status;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ModelCatalog.instance.addListener(_refresh);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      _refresh();
      _scheduleMidnight();
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _signature = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    ModelCatalog.instance.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revision = context.select<ChatService, int>(
      (chats) => chats.statisticsRevision,
    );
    final settings = context.watch<SettingsProvider>();
    if (!settings.spendLimits.enabled) return const SizedBox.shrink();
    final now = DateTime.now();
    final signature =
        '${widget.conversationId}:$revision:${now.year}-${now.month}-${now.day}:${jsonEncode(settings.spendLimits.toJson())}';
    if (_signature != signature) {
      _signature = signature;
      _status = SpendControlService(
        chats: context.read<ChatService>(),
        settings: settings,
      ).status(widget.conversationId, includeContext: false);
    }
    return FutureBuilder<SpendControlStatus>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        if (status == null || (!status.chatWarning && !status.dailyWarning)) {
          return const SizedBox.shrink();
        }
        final l10n = AppLocalizations.of(context)!;
        String remaining(ChatTokenSummary usage, double? usd, int? tokens) {
          final dollars = SpendControlStatus.remainingUsd(usage, usd);
          final count = SpendControlStatus.remainingTokens(usage, tokens);
          return [
            if (dollars != null)
              '${usage.costComplete ? '' : '≤ '}\$${dollars.toStringAsFixed(4)}',
            if (count != null)
              l10n.spendTokenAmount(TokenStatsRow.compact(count)),
          ].join(' · ');
        }

        final text = [
          if (status.chatWarning)
            l10n.spendChatRemaining(
              remaining(
                status.chat,
                status.limits.chatUsd,
                status.limits.chatTokens,
              ),
            ),
          if (status.dailyWarning)
            l10n.spendDailyRemaining(
              remaining(
                status.today,
                status.limits.dailyUsd,
                status.limits.dailyTokens,
              ),
            ),
        ].join(' · ');
        final partial =
            (status.chatWarning &&
                status.limits.chatUsd != null &&
                !status.chat.costComplete) ||
            (status.dailyWarning &&
                status.limits.dailyUsd != null &&
                !status.today.costComplete);
        final color = status.exceeded
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            onTap: () => showSpendLimitsSettings(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    status.blocked ? Lucide.CircleStop : Lucide.Gauge,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        status.blocked
                            ? l10n.spendHardStopMessage
                            : status.exceeded
                            ? l10n.spendLimitReachedHint(text)
                            : l10n.spendWarningHint(text),
                        if (partial) l10n.spendPartialPrice,
                      ].join(' '),
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

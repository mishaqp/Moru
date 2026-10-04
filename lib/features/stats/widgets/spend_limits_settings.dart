import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';

Future<void> showSpendLimitsSettings(BuildContext context) {
  final settings = context.read<SettingsProvider>();
  return showCustomBottomSheet<void>(
    context: context,
    title: AppLocalizations.of(context)!.spendLimitsTitle,
    partialHeightFactor: 0.8,
    builder: (_, controller) =>
        SpendLimitsSettings(settings: settings, scrollController: controller),
  );
}

class SpendLimitsSettings extends StatefulWidget {
  const SpendLimitsSettings({
    super.key,
    required this.settings,
    this.scrollController,
  });
  final SettingsProvider settings;
  final ScrollController? scrollController;
  @override
  State<SpendLimitsSettings> createState() => _SpendLimitsSettingsState();
}

class _SpendLimitsSettingsState extends State<SpendLimitsSettings> {
  late final Map<String, TextEditingController> _fields;
  late bool _hardStop;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final limits = widget.settings.spendLimits;
    _fields = {
      for (final entry in limits.toJson().entries)
        if (entry.key != 'hard_stop')
          entry.key: TextEditingController(text: entry.value?.toString() ?? ''),
    };
    _hardStop = limits.hardStop;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final changes = <String, dynamic>{'hard_stop': _hardStop};
    for (final entry in _fields.entries) {
      final value = entry.value.text.trim();
      final isPercent = entry.key == 'warning_percent';
      final isUsd = entry.key.endsWith('_usd');
      final num? parsed = value.isEmpty
          ? null
          : isUsd
          ? double.tryParse(value.replaceAll(',', '.'))
          : int.tryParse(value);
      if ((isPercent && (parsed == null || parsed < 1 || parsed > 100)) ||
          (value.isNotEmpty &&
              (parsed == null || !parsed.isFinite || parsed <= 0))) {
        setState(
          () => _error = isPercent
              ? l10n.spendInvalidThreshold
              : l10n.spendInvalidValue,
        );
        return;
      }
      changes[entry.key] = parsed;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.settings.setSpendLimits(
        widget.settings.spendLimits.patch(changes),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      'chat_usd': l10n.spendChatUsd,
      'chat_tokens': l10n.spendChatTokens,
      'daily_usd': l10n.spendDailyUsd,
      'daily_tokens': l10n.spendDailyTokens,
      'warning_percent': l10n.spendWarningThreshold,
    };
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          l10n.spendLimitsNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SectionCard(
          dividers: true,
          children: [
            for (final entry in labels.entries)
              IosFormTextField(
                key: ValueKey('spend-${entry.key}'),
                label: entry.value,
                controller: _fields[entry.key]!,
                inlineLabel: false,
                hintText: entry.key == 'warning_percent'
                    ? '80%'
                    : l10n.spendValueHint,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: entry.key.endsWith('_usd'),
                ),
                enabled: !_saving,
              ),
            IosSwitchRow(
              label: l10n.spendHardStop,
              value: _hardStop,
              onChanged: (value) {
                if (!_saving) setState(() => _hardStop = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.spendHardStopNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.userProfileSave),
        ),
      ],
    );
  }
}

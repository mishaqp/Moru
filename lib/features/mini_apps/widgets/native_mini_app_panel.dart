import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/section_card.dart';

/// A bounded JSON screen made from host widgets. It never executes app code.
class NativeMiniAppPanel extends StatelessWidget {
  const NativeMiniAppPanel({
    super.key,
    required this.screen,
    required this.state,
    required this.onAction,
    this.busy = false,
  });

  final Map<String, dynamic> screen;
  final Map<String, dynamic> state;
  final Future<void> Function(String name, Map<String, dynamic> arguments)
  onAction;
  final bool busy;

  /// Screen strings can be plain text or locale maps, without expressions.
  static String localizedText(Object? raw, Locale locale) {
    if (raw == null) return '';
    if (raw is! Map) return '$raw';
    final tag = locale.toLanguageTag();
    final value =
        raw[tag] ??
        raw[tag.replaceAll('-', '_')] ??
        (locale.languageCode == 'zh'
            ? raw[locale.scriptCode == 'Hant' ||
                      const ['TW', 'HK', 'MO'].contains(locale.countryCode)
                  ? 'zh_Hant'
                  : 'zh_Hans']
            : null) ??
        raw[locale.languageCode] ??
        raw['en'];
    if (value is String) return value;
    for (final value in raw.values) {
      if (value is String) return value;
    }
    return '';
  }

  static Object? binding(Map<String, dynamic> state, Object? path) {
    if (path is! String || path.isEmpty) return null;
    Object? value = state;
    for (final part in path.split('.')) {
      if (value is Map) {
        value = value[part];
      } else if (value is List) {
        final index = int.tryParse(part);
        if (index == null || index < 0 || index >= value.length) return null;
        value = value[index];
      } else {
        return null;
      }
    }
    return value;
  }

  String _text(BuildContext context, Object? value) =>
      localizedText(value, Localizations.localeOf(context));

  String? _reason(BuildContext context, Object? path) {
    if (path is! String || !path.contains('.')) return null;
    final parts = path.split('.');
    final parent = parts.take(parts.length - 1).join('.');
    final reason =
        binding(state, '$parent.reasons.${parts.last}') ??
        binding(state, '$parent.reasons.group');
    final l10n = AppLocalizations.of(context)!;
    return switch (reason) {
      'permission_required' ||
      'permission_denied' ||
      'service_or_permission_unavailable' ||
      'phone_state_permission_or_subscription_unavailable' ||
      'package_visibility_unavailable' => l10n.miniAppsNativePermissionRequired,
      'unsupported' ||
      'not_available' ||
      'unsupported_android_version' ||
      'command_unsupported' ||
      'no_flash_camera' => l10n.miniAppsNativeUnsupported,
      'sensor_unavailable' => l10n.miniAppsNativeSensorUnavailable,
      'estimate_unavailable' => l10n.miniAppsNativeEstimateUnavailable,
      'setting_unavailable' => l10n.miniAppsNativeSettingUnavailable,
      'service_unavailable' ||
      'camera_unavailable' ||
      'adapter_unavailable' ||
      'network_unavailable' ||
      'package_unavailable' ||
      'display_unavailable' => l10n.miniAppsNativeServiceUnavailable,
      'read_failed' || 'read_timeout' => l10n.miniAppsNativeReadFailed,
      'su_unavailable' => l10n.miniAppsNativeRootUnavailable,
      'root_denied' => l10n.miniAppsNativeRootDenied,
      'command_timeout_or_cancelled' ||
      'unknown_after_timeout' => l10n.miniAppsNativeTimeout,
      'command_failed' || 'failed' => l10n.miniAppsNativeActionError,
      'not_checked' => l10n.miniAppsNativeUnknown,
      null => null,
      _ => l10n.miniAppsNativeUnavailable,
    };
  }

  String _value(
    BuildContext context,
    Map<String, dynamic> component,
    Object? value,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.miniAppsNativeUnavailable;
    if (component['values'] case final Map values) {
      if (values.containsKey('$value')) return _text(context, values['$value']);
    }
    if (value is bool) {
      return value ? l10n.miniAppsNativeOn : l10n.miniAppsNativeOff;
    }
    final locale = Localizations.localeOf(context).toString();
    var unit = _text(context, component['unit']);
    final String text;
    if (value is num && component['format'] == 'bytes') {
      final bytes = value.toDouble();
      final exponent = bytes.abs() >= 1024 * 1024 * 1024
          ? 3
          : bytes.abs() >= 1024 * 1024
          ? 2
          : bytes.abs() >= 1024
          ? 1
          : 0;
      final divisor = switch (exponent) {
        3 => 1024 * 1024 * 1024,
        2 => 1024 * 1024,
        1 => 1024,
        _ => 1,
      };
      text = NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: exponent == 0 ? 0 : 1,
      ).format(bytes / divisor);
      unit = const ['B', 'KiB', 'MiB', 'GiB'][exponent];
    } else if (value is num && component['format'] == 'duration') {
      // Durations in the device snapshot use milliseconds. The colon form
      // avoids unlocalized unit names in declarative screens.
      final duration = Duration(milliseconds: value.toInt());
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final seconds = duration.inSeconds.remainder(60);
      text =
          '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else if (value is num) {
      text = NumberFormat.decimalPattern(locale).format(value);
    } else {
      text = _text(context, value);
    }
    return unit.isEmpty ? text : '$text $unit';
  }

  Object? _controlArguments(Object? raw, Object? value) {
    if (raw is Map) {
      if (raw.length == 1 && raw[r'$value'] == true) return value;
      return {
        for (final entry in raw.entries)
          '${entry.key}': _controlArguments(entry.value, value),
      };
    }
    if (raw is List) {
      return [for (final item in raw) _controlArguments(item, value)];
    }
    return raw;
  }

  Future<void> _invoke(Map<String, dynamic> component, [Object? value]) async {
    final name = component['action'];
    if (busy || name is! String || name.isEmpty) return;
    final args = _controlArguments(component['args'] ?? const {}, value);
    if (args is! Map) return;
    await onAction(name, Map<String, dynamic>.from(args));
  }

  bool _enabled(Map<String, dynamic> component) =>
      !busy &&
      component['action'] is String &&
      component['disabled'] != true &&
      component['enabled'] != false;

  Widget _component(
    BuildContext context,
    Map<String, dynamic> component,
    String identity,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final label = _text(context, component['label'] ?? component['title']);
    final value = binding(state, component['bind']);
    final reason = _reason(context, component['bind']);
    final cs = Theme.of(context).colorScheme;
    switch (component['type']) {
      case 'card':
        final children = component['children'] as List? ?? const [];
        return SectionCard(
          key: ValueKey(identity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              for (var i = 0; i < children.length; i++)
                if (children[i] is Map)
                  _component(
                    context,
                    Map<String, dynamic>.from(children[i] as Map),
                    '$identity.$i',
                  ),
            ],
          ),
        );
      case 'text':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(_text(context, component['text'])),
        );
      case 'value':
      case 'indicator':
        if (component['type'] == 'indicator' &&
            (value is num ||
                component.containsKey('min') ||
                component.containsKey('max'))) {
          final min = (component['min'] as num?)?.toDouble() ?? 0;
          final max = (component['max'] as num?)?.toDouble() ?? 100;
          final reading = value is num && value.isFinite ? value : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IosNavRow(
                label: label,
                labelTrailing: const SizedBox.shrink(),
                subtitle: _value(context, component, reading),
                subtitleMaxLines: null,
                caption: reason,
              ),
              if (reading != null && min.isFinite && max.isFinite && max > min)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LinearProgressIndicator(
                    value: ((reading - min) / (max - min)).clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    semanticsLabel:
                        '$label: ${_value(context, component, reading)}',
                  ),
                ),
            ],
          );
        }
        return IosNavRow(
          label: label,
          labelTrailing: const SizedBox.shrink(),
          subtitle: _value(context, component, value),
          subtitleMaxLines: null,
          caption: reason,
          leading: component['type'] == 'indicator'
              ? Semantics(
                  label: _value(context, component, value),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value == true
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                )
              : null,
        );
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: _enabled(component) ? () => _invoke(component) : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(label),
            ),
          ),
        );
      case 'switch':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (value is! bool)
                      Text(
                        l10n.miniAppsNativeUnavailable,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    if (reason != null) Text(reason),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IosSwitch(
                semanticLabel: label,
                hitTestSize: 48,
                value: value == true,
                onChanged: value is bool && _enabled(component)
                    ? (next) => _invoke(component, next)
                    : null,
              ),
            ],
          ),
        );
      case 'slider':
        final minimum = component['minBind'] != null
            ? binding(state, component['minBind'])
            : component['min'] ?? 0;
        final min = minimum is num ? minimum.toDouble() : 0.0;
        final maximum = component['maxBind'] != null
            ? binding(state, component['maxBind'])
            : component['max'];
        final max = maximum is num ? maximum.toDouble() : min;
        return _NativeSlider(
          key: ValueKey(identity),
          label: label,
          min: min,
          max: max > min ? max : min + 1,
          step: (component['step'] as num?)?.toDouble(),
          value: value is num ? value.toDouble() : null,
          display: (next) => _value(context, component, next),
          unavailable: l10n.miniAppsNativeUnavailable,
          reason: reason,
          enabled:
              value is num &&
              minimum is num &&
              max > min &&
              _enabled(component),
          onCommit: (next) => _invoke(
            component,
            component['step'] is int ? next.round() : next,
          ),
        );
      case 'list':
        final items = component['options'] ?? value;
        if (items is! List || items.isEmpty) {
          return IosNavRow(
            label: label,
            labelTrailing: const SizedBox.shrink(),
            subtitle: items == null
                ? l10n.miniAppsNativeUnavailable
                : l10n.miniAppsNativeNoItems,
            subtitleMaxLines: null,
            caption: reason,
          );
        }
        final entries = <Object, String>{};
        for (final item in items) {
          final Object? itemValue;
          final String itemLabel;
          if (item is Map) {
            final fields = Map<String, dynamic>.from(item);
            itemValue = binding(fields, component['valueKey'] ?? 'value');
            itemLabel = _text(
              context,
              binding(fields, component['labelKey'] ?? 'label'),
            );
          } else {
            itemValue = item;
            itemLabel = _text(context, item);
          }
          if (itemValue is String || itemValue is num || itemValue is bool) {
            entries[itemValue!] = itemLabel;
          }
        }
        if (component['action'] is! String) {
          return IosNavRow(
            label: label,
            labelTrailing: const SizedBox.shrink(),
            subtitle: entries.values.join('\n'),
            subtitleMaxLines: null,
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: DropdownButtonFormField<Object>(
            // External device updates replace FormField's initial selection.
            key: ValueKey(
              '$identity:${component['options'] != null ? value : null}',
            ),
            initialValue:
                component['options'] != null && entries.containsKey(value)
                ? value
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              helperText:
                  component['bind'] != null &&
                      component['options'] != null &&
                      value == null
                  ? reason ?? l10n.miniAppsNativeUnavailable
                  : reason,
              helperMaxLines: 4,
            ),
            hint: Text(l10n.miniAppsNativeChoose),
            items: [
              for (final item in entries.entries)
                DropdownMenuItem<Object>(
                  value: item.key,
                  child: Text(item.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _enabled(component)
                ? (next) => _invoke(component, next)
                : null,
          ),
        );
      default:
        return Text(l10n.miniAppsNativeUnsupported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final components = screen['components'] as List? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < components.length; i++)
          if (components[i] is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _component(
                context,
                Map<String, dynamic>.from(components[i] as Map),
                'component.$i',
              ),
            ),
      ],
    );
  }
}

class _NativeSlider extends StatefulWidget {
  const _NativeSlider({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.display,
    required this.unavailable,
    required this.reason,
    required this.enabled,
    required this.onCommit,
  });

  final String label;
  final double min;
  final double max;
  final double? step;
  final double? value;
  final String Function(double?) display;
  final String unavailable;
  final String? reason;
  final bool enabled;
  final Future<void> Function(double) onCommit;

  @override
  State<_NativeSlider> createState() => _NativeSliderState();
}

class _NativeSliderState extends State<_NativeSlider> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _NativeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || !widget.enabled) _dragValue = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    final step = widget.step;
    final divisions = step != null && step > 0
        ? ((widget.max - widget.min) / step).round().clamp(1, 10000)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label),
          Text(widget.enabled ? widget.display(value) : widget.unavailable),
          if (widget.reason != null) Text(widget.reason!),
          Slider(
            min: widget.min,
            max: widget.max,
            value: (value ?? widget.min).clamp(widget.min, widget.max),
            divisions: divisions,
            label: widget.display(value),
            semanticFormatterCallback: (next) => widget.display(next),
            onChanged: widget.enabled
                ? (next) => setState(() => _dragValue = next)
                : null,
            onChangeEnd: widget.enabled
                ? (next) async {
                    await widget.onCommit(next);
                    if (mounted) setState(() => _dragValue = null);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

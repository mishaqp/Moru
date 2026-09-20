import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/ios_form_text_field.dart';

/// Parses [input] into a navigable http/https [Uri], or returns null when it
/// cannot be made into one.
///
/// A bare host (no `://`) is treated as `https://<host>` -- this is at least
/// as strict as the pre-split dialog: only `http`/`https` schemes are
/// accepted and the host must be non-empty. An invalid result is reported to
/// the caller as `null`, which the address editor turns into a visible
/// inline error rather than silently doing nothing.
Uri? parseBrowserAddress(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final candidate = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Full-URL address editor sheet, replacing the old plain `AlertDialog`.
/// Submitting an invalid address shows [AppLocalizations.browserAddressEditorInvalid]
/// inline instead of silently no-opping.
Future<void> showBrowserAddressEditor(
  BuildContext context, {
  required String? currentUrl,
  required ValueChanged<Uri> onSubmit,
}) {
  return showFormSheet<void>(
    context,
    builder: (sheetContext) =>
        _BrowserAddressEditorSheet(currentUrl: currentUrl, onSubmit: onSubmit),
  );
}

class _BrowserAddressEditorSheet extends StatefulWidget {
  const _BrowserAddressEditorSheet({
    required this.currentUrl,
    required this.onSubmit,
  });

  final String? currentUrl;
  final ValueChanged<Uri> onSubmit;

  @override
  State<_BrowserAddressEditorSheet> createState() =>
      _BrowserAddressEditorSheetState();
}

class _BrowserAddressEditorSheetState
    extends State<_BrowserAddressEditorSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = parseBrowserAddress(_controller.text);
    if (uri == null) {
      setState(
        () =>
            _error = AppLocalizations.of(context)!.browserAddressEditorInvalid,
      );
      return;
    }
    widget.onSubmit(uri);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final secure = _controller.text.trim().startsWith('https://');
    return FormSheet(
      title: l10n.browserAddressEditorTitle,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              secure ? Lucide.Lock : Lucide.LockOpen,
              size: 15,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IosFormTextField(
                label: '',
                controller: _controller,
                inlineLabel: false,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                hintText: l10n.browserAddressEditorHint,
                textInputAction: TextInputAction.go,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12.5, color: cs.error)),
        ],
        const SizedBox(height: 16),
        FormSheetActions(
          cancelLabel: l10n.toolSchemaSettingsCancel,
          confirmLabel: l10n.browserAddressEditorGo,
          onCancel: () => Navigator.of(context).maybePop(),
          onConfirm: _submit,
        ),
      ],
    );
  }
}

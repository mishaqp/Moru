import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_userscripts.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import '../../widgets/snackbar.dart';

/// Installed user scripts: switch on and off, remove, install one from a
/// link. [pageUrl] prefills the link when the open page is a `.user.js`.
Future<void> showUserscriptsSheet(BuildContext context, {String? pageUrl}) {
  unawaited(BrowserUserscripts.instance.load().catchError((Object _) {}));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => UserscriptsSheet(pageUrl: pageUrl),
  );
}

class UserscriptsSheet extends StatefulWidget {
  const UserscriptsSheet({super.key, this.pageUrl});

  static const Key linkKey = ValueKey<String>('userscripts-link');
  static const Key installKey = ValueKey<String>('userscripts-install');
  static Key switchKey(String id) => ValueKey<String>('userscript-on-$id');
  static Key removeKey(String id) => ValueKey<String>('userscript-x-$id');

  final String? pageUrl;

  @override
  State<UserscriptsSheet> createState() => _UserscriptsSheetState();
}

class _UserscriptsSheetState extends State<UserscriptsSheet> {
  late final TextEditingController _link = TextEditingController(
    text: (widget.pageUrl ?? '').toLowerCase().endsWith('.user.js')
        ? widget.pageUrl
        : '',
  );
  bool _installing = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final l10n = AppLocalizations.of(context)!;
    // A link has no spaces; keyboards add them after dots.
    final uri = Uri.tryParse(_link.text.replaceAll(RegExp(r'\s'), ''));
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.userscriptsBadLink,
        type: NotificationType.warning,
      );
      return;
    }
    setState(() => _installing = true);
    String message;
    NotificationType type;
    try {
      final script = await BrowserUserscripts.instance.installFrom(uri);
      message = script == null
          ? l10n.userscriptsNotAScript
          : l10n.userscriptsInstalled(script.name);
      type = script == null
          ? NotificationType.warning
          : NotificationType.success;
      if (script != null) _link.clear();
    } catch (error) {
      message = l10n.userscriptsInstallFailed('$error');
      type = NotificationType.error;
    }
    if (!mounted) return;
    setState(() => _installing = false);
    showAppSnackBar(context, message: message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final store = BrowserUserscripts.instance;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.userscriptsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.userscriptsHint,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: UserscriptsSheet.linkKey,
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'https://…/script.user.js',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: UserscriptsSheet.installKey,
                  onPressed: _installing ? null : _install,
                  child: Text(l10n.userscriptsInstall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ValueListenableBuilder<List<Userscript>>(
                valueListenable: store.scripts,
                builder: (context, scripts, _) {
                  if (scripts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        l10n.userscriptsEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final script in scripts)
                        Row(
                          children: [
                            Icon(Lucide.Code, size: 18, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    script.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: AppFontWeights.semibold,
                                    ),
                                  ),
                                  Text(
                                    [
                                      if (script.version != null)
                                        'v${script.version}',
                                      ...script.matches,
                                      ...script.includes,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              key: UserscriptsSheet.switchKey(script.id),
                              value: script.enabled,
                              onChanged: (on) =>
                                  unawaited(store.setEnabled(script.id, on)),
                            ),
                            IconButton(
                              key: UserscriptsSheet.removeKey(script.id),
                              tooltip: l10n.browserLibraryRemove,
                              icon: const Icon(Lucide.Trash2, size: 18),
                              onPressed: () =>
                                  unawaited(store.remove(script.id)),
                            ),
                          ],
                        ),
                    ],
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

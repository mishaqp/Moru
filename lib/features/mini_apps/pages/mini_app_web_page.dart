import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/keep_alive.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_web_host.dart';

/// "Web server" of My Apps: opens the mini apps in a browser on another
/// device in the Wi-Fi.
class MiniAppWebPage extends StatefulWidget {
  const MiniAppWebPage({super.key, this.host});

  /// [MiniAppWebHost.instance] when null.
  final MiniAppWebHost? host;

  @override
  State<MiniAppWebPage> createState() => _MiniAppWebPageState();
}

class _MiniAppWebPageState extends State<MiniAppWebPage> {
  late final TextEditingController _port;
  late final TextEditingController _password;
  bool _showPassword = false;
  bool _invalidPort = false;

  MiniAppWebHost get _host => widget.host ?? MiniAppWebHost.instance;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    var password = settings.miniAppWebPassword;
    if (settings.miniAppWebPasswordEnabled && password.isEmpty) {
      password = _randomPassword();
      // Not during this build: saving notifies the settings' listeners.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(settings.setMiniAppWeb(password: password)),
      );
    }
    _port = TextEditingController(text: '${settings.miniAppWebPort}');
    _password = TextEditingController(text: password);
  }

  @override
  void dispose() {
    _port.dispose();
    _password.dispose();
    super.dispose();
  }

  static String _randomPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _toggle() async {
    if (_host.running) {
      await _host.stop();
      return;
    }
    final settings = context.read<SettingsProvider>();
    final port = int.tryParse(_port.text.trim());
    final invalid = port == null || port < 1024 || port > 65535;
    setState(() => _invalidPort = invalid);
    if (invalid) return;
    await settings.setMiniAppWeb(port: port, password: _password.text.trim());
    if (!mounted) return;
    await _host.startFrom(context);
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context)!.miniAppsWebCopied,
    );
  }

  String? _errorText(AppLocalizations l10n, SettingsProvider settings) {
    if (_invalidPort) return l10n.miniAppsWebInvalidPort;
    return switch (_host.error) {
      null => null,
      MiniAppWebHost.errorNoPassword => l10n.miniAppsWebNoPassword,
      ProcessKeepAliveException.code => l10n.backgroundProtectionUnavailable,
      MiniAppWebHost.errorPortInUse => l10n.miniAppsWebPortInUse(
        '${settings.miniAppWebPort}',
      ),
      final other => other,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    return ListenableBuilder(
      listenable: _host,
      builder: (context, _) {
        final running = _host.running;
        final error = _errorText(l10n, settings);
        return Scaffold(
          appBar: AppBar(
            leading: Tooltip(
              message: l10n.settingsPageBackButton,
              child: IosIconButton(
                icon: Lucide.ArrowLeft,
                minSize: 44,
                size: 22,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            title: Text(l10n.miniAppsWebTitle),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              SectionCard(
                children: [
                  _FieldRow(
                    icon: Lucide.Network,
                    label: l10n.miniAppsWebPort,
                    subtitle: '1024–65535',
                    child: TextField(
                      key: const ValueKey('mini-app-web-port'),
                      controller: _port,
                      enabled: !running,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textAlign: TextAlign.center,
                      decoration: _fieldDecoration(cs),
                    ),
                  ),
                  const IosRowDivider(),
                  IgnorePointer(
                    ignoring: running,
                    child: IosSwitchRow(
                      icon: Lucide.Smartphone,
                      label: l10n.miniAppsWebLocalhostOnly,
                      subtitle: l10n.miniAppsWebLocalhostOnlySubtitle,
                      value: settings.miniAppWebLocalhostOnly,
                      onChanged: (value) => unawaited(
                        settings.setMiniAppWeb(localhostOnly: value),
                      ),
                    ),
                  ),
                  const IosRowDivider(),
                  IgnorePointer(
                    ignoring: running,
                    child: IosSwitchRow(
                      icon: Lucide.Shield,
                      label: l10n.miniAppsWebPasswordEnabled,
                      subtitle: l10n.miniAppsWebPasswordEnabledSubtitle,
                      value: settings.miniAppWebPasswordEnabled,
                      onChanged: (value) {
                        if (value && _password.text.trim().isEmpty) {
                          _password.text = _randomPassword();
                        }
                        unawaited(
                          settings.setMiniAppWeb(
                            passwordEnabled: value,
                            password: _password.text.trim(),
                          ),
                        );
                      },
                    ),
                  ),
                  const IosRowDivider(),
                  IosSwitchRow(
                    icon: Lucide.Power,
                    label: l10n.miniAppsWebAutostart,
                    subtitle: l10n.miniAppsWebAutostartSubtitle,
                    value: settings.miniAppWebAutostart,
                    onChanged: (value) =>
                        unawaited(settings.setMiniAppWeb(autostart: value)),
                  ),
                  if (settings.miniAppWebPasswordEnabled) ...[
                    const IosRowDivider(),
                    _FieldRow(
                      icon: Lucide.Eye,
                      label: l10n.miniAppsWebPassword,
                      wide: true,
                      child: TextField(
                        key: const ValueKey('mini-app-web-password'),
                        controller: _password,
                        enabled: !running,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (value) => unawaited(
                          settings.setMiniAppWeb(password: value.trim()),
                        ),
                        decoration: _fieldDecoration(cs).copyWith(
                          suffixIcon: IconButton(
                            tooltip: l10n.miniAppsWebPassword,
                            icon: Icon(
                              _showPassword ? Lucide.EyeOff : Lucide.Eye,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(error, style: TextStyle(color: cs.error)),
                ),
              if (running) ...[
                IosSectionHeader(text: l10n.miniAppsWebRunning),
                SectionCard(
                  children: [
                    for (final url in _host.urls) ...[
                      if (url != _host.urls.first) const IosRowDivider(),
                      IosNavRow(
                        key: ValueKey('mini-app-web-url-$url'),
                        icon: Lucide.Copy,
                        label: url,
                        onTap: () => unawaited(_copy(url)),
                        trailing: IosIconButton(
                          icon: Lucide.ExternalLink,
                          size: 18,
                          minSize: 36,
                          onTap: () => unawaited(
                            launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 8),
              IosSectionFooter(text: l10n.miniAppsWebFooter),
              const SizedBox(height: 16),
              _StartButton(
                label: running ? l10n.miniAppsWebStop : l10n.miniAppsWebStart,
                icon: running ? Lucide.Square : Lucide.Play,
                busy: _host.busy,
                onTap: () => unawaited(_toggle()),
              ),
            ],
          ),
        );
      },
    );
  }

  static InputDecoration _fieldDecoration(ColorScheme cs) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: cs.onSurface.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

/// A settings row with a text field on the right.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.child,
    this.subtitle,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Icon(
              icon,
              size: 20,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 15)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: wide ? 180 : 100, child: child),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      key: const ValueKey('mini-app-web-toggle'),
      baseColor: cs.primary,
      borderRadius: BorderRadius.circular(14),
      onTap: busy ? null : onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onPrimary,
                ),
              )
            else
              Icon(icon, size: 18, color: cs.onPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

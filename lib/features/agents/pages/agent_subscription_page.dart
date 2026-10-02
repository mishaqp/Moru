import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/acp/acp_agent_auth.dart';
import '../../../core/services/acp/acp_agent_catalog.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../widgets/agent_labels.dart';

/// The only UI that reads an agent's ephemeral browser link and login code.
/// Leaving this page cancels an unfinished native sign-in process.
class AgentSubscriptionPage extends StatefulWidget {
  const AgentSubscriptionPage({
    super.key,
    required this.agentId,
    this.onSignIn,
  });

  final String agentId;

  /// Selects subscription mode for the intended assistant before native login.
  /// Opening this page or checking an account never invokes it.
  final Future<void> Function()? onSignIn;

  @override
  State<AgentSubscriptionPage> createState() => _AgentSubscriptionPageState();
}

class _AgentSubscriptionPageState extends State<AgentSubscriptionPage> {
  late final AcpAgentManager _manager;
  late final AcpAgentAuth _auth;
  final _code = TextEditingController();
  bool _browserFailed = false;
  bool _openingBrowser = false;
  bool _submittingCode = false;
  bool _startingSignIn = false;
  bool _signInFailed = false;

  @override
  void initState() {
    super.initState();
    _manager = context.read<AcpAgentManager>();
    _auth = _manager.auth;
    _auth.addListener(_clearFinishedCode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final spec = _manager.agent(widget.agentId);
      if (spec?.supportsSubscription == true &&
          _manager.environmentAvailable &&
          !_auth.busy(widget.agentId)) {
        unawaited(_auth.check(spec!));
      }
    });
  }

  void _clearFinishedCode() {
    if (_auth.loginFor(widget.agentId) == null && _code.text.isNotEmpty) {
      _code.clear();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_clearFinishedCode);
    _code
      ..clear()
      ..dispose();
    unawaited(Future<void>.microtask(() => _auth.cancel(widget.agentId)));
    super.dispose();
  }

  Future<void> _openBrowser(Uri url) async {
    setState(() {
      _openingBrowser = true;
      _browserFailed = false;
    });
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The URL stays on this page; platform exceptions are never displayed.
    }
    if (!mounted) return;
    setState(() {
      _openingBrowser = false;
      _browserFailed = !opened;
    });
  }

  Future<void> _signIn(AcpAgentSpec spec) async {
    if (_startingSignIn ||
        _auth.busy(spec.id) ||
        _manager.busy ||
        !_manager.environmentAvailable) {
      return;
    }
    setState(() {
      _startingSignIn = true;
      _signInFailed = false;
      _browserFailed = false;
    });
    try {
      await widget.onSignIn?.call();
      if (!mounted) return;
      await _auth.signIn(spec);
    } catch (_) {
      // Assistant persistence failures stay private like native auth failures.
      if (mounted) setState(() => _signInFailed = true);
    } finally {
      if (mounted) setState(() => _startingSignIn = false);
    }
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.isEmpty || _submittingCode) return;
    setState(() => _submittingCode = true);
    _code.clear();
    await _auth.submitCode(widget.agentId, code);
    if (mounted) setState(() => _submittingCode = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final manager = context.watch<AcpAgentManager>();
    final spec = manager.agent(widget.agentId);
    final status = _auth.status(widget.agentId);
    final busy = _auth.busy(widget.agentId);
    final login = _auth.loginFor(widget.agentId);
    final ready =
        !busy &&
        !_startingSignIn &&
        !manager.busy &&
        manager.environmentAvailable;
    final failure =
        agentAuthFailureLabel(l10n, _auth.failure(widget.agentId)) ??
        (_signInFailed ? l10n.agentsAuthFailureStart : null);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.agentsAuthTitle),
      ),
      body: spec?.supportsSubscription != true
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SectionCard(
                  children: [
                    IosNavRow(
                      key: const ValueKey('agent-auth-status'),
                      icon: agentIcon(spec!),
                      label: spec.name,
                      detailText: agentAuthStatusLabel(l10n, status),
                    ),
                  ],
                ),
                IosSectionFooter(text: l10n.agentsAuthSubscriptionHint),
                IosSectionFooter(
                  text: spec.id == AcpAgentSpec.codexId
                      ? l10n.agentsAuthCodexHint
                      : l10n.agentsAuthCodeHint,
                ),
                if (!manager.environmentAvailable)
                  IosSectionFooter(text: l10n.agentsAuthFailureEnvironment),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      failure,
                      style: TextStyle(color: cs.error, height: 1.35),
                    ),
                  ),
                if (login != null) ...[
                  if (login.awaitingUser)
                    IosSectionFooter(text: l10n.agentsAuthWaiting),
                  if (login.deviceCode case final code?) ...[
                    IosSectionHeader(text: l10n.agentsAuthDeviceCode),
                    SectionCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          code,
                          key: const ValueKey('agent-auth-device-code'),
                          style: const TextStyle(
                            fontSize: 22,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (login.url case final url?) ...[
                    IosTileButton(
                      key: const ValueKey('agent-auth-open-browser'),
                      icon: LucideIcons.externalLink,
                      label: l10n.agentsAuthOpenBrowser,
                      enabled: !_openingBrowser,
                      backgroundColor: cs.primary,
                      onTap: () => unawaited(_openBrowser(url)),
                    ),
                    if (_browserFailed)
                      IosSectionFooter(text: l10n.agentsAuthBrowserFailed),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        url.toString(),
                        key: const ValueKey('agent-auth-url'),
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                  if (spec.id == AcpAgentSpec.claudeCodeId &&
                      login.awaitingUser) ...[
                    SectionCard(
                      child: IosFormTextField(
                        key: const ValueKey('agent-auth-code'),
                        label: l10n.agentsAuthCode,
                        controller: _code,
                        inlineLabel: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.send,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => unawaited(_submitCode()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    IosTileButton(
                      key: const ValueKey('agent-auth-submit-code'),
                      icon: LucideIcons.send,
                      label: l10n.agentsAuthSubmitCode,
                      enabled: !_submittingCode && _code.text.trim().isNotEmpty,
                      onTap: () => unawaited(_submitCode()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Center(child: CircularProgressIndicator.adaptive()),
                  const SizedBox(height: 12),
                  IosTileButton(
                    key: const ValueKey('agent-auth-cancel'),
                    icon: LucideIcons.x,
                    label: l10n.agentsAuthCancel,
                    onTap: () {
                      _code.clear();
                      unawaited(_auth.cancel(widget.agentId));
                    },
                  ),
                ] else ...[
                  IosTileButton(
                    key: const ValueKey('agent-auth-sign-in'),
                    icon: LucideIcons.logIn,
                    label: l10n.agentsAuthSignIn,
                    enabled: ready,
                    backgroundColor: cs.primary,
                    onTap: () => unawaited(_signIn(spec)),
                  ),
                  const SizedBox(height: 10),
                  IosTileButton(
                    key: const ValueKey('agent-auth-check'),
                    icon: LucideIcons.refreshCw,
                    label: l10n.agentsAuthCheck,
                    enabled: ready,
                    onTap: () => unawaited(_auth.check(spec)),
                  ),
                  const SizedBox(height: 10),
                  IosTileButton(
                    key: const ValueKey('agent-auth-sign-out'),
                    icon: LucideIcons.logOut,
                    label: l10n.agentsAuthSignOut,
                    enabled: ready && status == AcpAuthStatus.signedIn,
                    foregroundColor: cs.error,
                    onTap: () {
                      _code.clear();
                      unawaited(_auth.signOut(spec));
                    },
                  ),
                  if (busy || _startingSignIn) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator.adaptive()),
                  ],
                ],
              ],
            ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/mini_apps/mini_app_permissions.dart';
import '../../core/services/mini_apps/mini_app_runtime.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/custom_bottom_sheet.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../shared/widgets/section_card.dart';
import '../home/services/tool_approval_service.dart';

Future<void> showMiniAppPermissions(
  BuildContext context, {
  required MiniApp app,
  required MiniAppRuntime runtime,
  MiniAppStore? store,
}) => showCustomBottomSheet<void>(
  context: context,
  title: AppLocalizations.of(context)!.miniAppsPermissionsTitle,
  builder: (_, controller) => MiniAppPermissionsSheet(
    app: app,
    store: store,
    runtime: runtime,
    scrollController: controller,
  ),
);

/// Grants are edited only by the individual switches, never by loading a panel.
class MiniAppPermissionsSheet extends StatefulWidget {
  const MiniAppPermissionsSheet({
    super.key,
    required this.app,
    required this.runtime,
    this.store,
    this.scrollController,
  });

  final MiniApp app;
  final MiniAppRuntime runtime;
  final MiniAppStore? store;
  final ScrollController? scrollController;

  @override
  State<MiniAppPermissionsSheet> createState() =>
      _MiniAppPermissionsSheetState();
}

class _MiniAppPermissionsSheetState extends State<MiniAppPermissionsSheet> {
  Set<String>? _grants;
  String? _error;
  bool _saving = false;
  int _read = 0;
  StreamSubscription<String>? _changes;

  MiniAppStore get _store => widget.store ?? widget.runtime.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    _changes = widget.runtime.permissions.changes
        .where((id) => id == widget.app.id)
        .listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  void _storeChanged() => unawaited(_load());

  Future<void> _load() async {
    final read = ++_read;
    try {
      final grants = await widget.runtime.permissions.granted(widget.app.id);
      if (mounted && read == _read) {
        setState(() {
          _grants = grants;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && read == _read) {
        setState(
          () => _error = _store.byId(widget.app.id) == null
              ? 'not_found'
              : 'failed',
        );
      }
    }
  }

  Future<void> _set(String capability, bool granted) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.runtime.permissions.setGranted(
        widget.app.id,
        capability,
        granted,
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _label(AppLocalizations l10n, String permission) =>
      switch (permission) {
        'actions.ai' => l10n.miniAppsPermissionAi,
        'device.battery.read' => l10n.miniAppsPermissionBatteryRead,
        'device.screen.read' => l10n.miniAppsPermissionScreenRead,
        'device.audio.read' => l10n.miniAppsPermissionAudioRead,
        'device.connectivity.read' => l10n.miniAppsPermissionConnectivityRead,
        'device.flashlight.read' => l10n.miniAppsPermissionFlashlightRead,
        'device.system.read' => l10n.miniAppsPermissionSystemRead,
        'device.screen.write' => l10n.miniAppsPermissionScreenWrite,
        'device.audio.write' => l10n.miniAppsPermissionAudioWrite,
        'device.flashlight.write' => l10n.miniAppsPermissionFlashlightWrite,
        'device.settings.open' => l10n.miniAppsPermissionSettingsOpen,
        'device.root.power_save' => l10n.miniAppsPermissionRootPowerSave,
        'device.root.wifi' => l10n.miniAppsPermissionRootWifi,
        'device.root.bluetooth' => l10n.miniAppsPermissionRootBluetooth,
        'device.root.data' => l10n.miniAppsPermissionRootData,
        'device.root.airplane' => l10n.miniAppsPermissionRootAirplane,
        'device.root.stop_app' => l10n.miniAppsPermissionRootStopApp,
        _ => permission,
      };

  @override
  void dispose() {
    ++_read;
    _store.removeListener(_storeChanged);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = _store.byId(widget.app.id);
    final capabilities = app == null
        ? <String>[]
        : (MiniAppPermissions.declared(app).toList()..sort());
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(l10n.miniAppsPermissionsExplanation),
        const SizedBox(height: 16),
        if (_error != null)
          Text(
            _error == 'not_found'
                ? l10n.miniAppsNotFound
                : l10n.miniAppsNativeActionError,
            style: TextStyle(color: cs.error),
          ),
        if (_grants == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_grants != null && capabilities.isEmpty)
          Text(l10n.miniAppsNativeNoItems),
        if (_grants != null && capabilities.isNotEmpty)
          SectionCard(
            child: Column(
              children: [
                for (final capability in capabilities)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_label(l10n, capability)),
                              if (capability == 'actions.ai')
                                Text(
                                  l10n.miniAppsPermissionAiHint,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              if (capability.startsWith('device.root.'))
                                Text(
                                  l10n.miniAppsPermissionRootHint,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IosSwitch(
                          key: ValueKey('mini-app-permission-$capability'),
                          semanticLabel: _label(l10n, capability),
                          hitTestSize: 48,
                          value: _grants!.contains(capability),
                          onChanged: _saving || _error == 'not_found'
                              ? null
                              : (value) => _set(capability, value),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

int _approvalSequence = 0;

/// Native and web button actions use the same pending-consent service as chat.
/// Dismissal and ownership loss deny the exact pending request; no Always grant.
Future<bool> requestMiniAppActionApproval(
  BuildContext context, {
  required MiniApp app,
  required MiniAppAction action,
  required Map<String, dynamic> arguments,
  required bool Function() isActive,
  required String scope,
  required ToolApprovalService approvals,
}) async {
  if (!context.mounted || !isActive()) return false;
  final l10n = AppLocalizations.of(context)!;
  SettingsProvider? settings;
  try {
    settings = context.read<SettingsProvider>();
  } catch (_) {}
  void syncTrust() {
    if (settings != null) {
      approvals.setAutoApproveAll(settings.toolAutoApproveAll);
    }
  }

  syncTrust();
  settings?.addListener(syncTrust);
  final callId = 'mini-app-ui-${++_approvalSequence}';
  final result = approvals.requestApproval(
    toolCallId: callId,
    toolName: MiniAppRuntime.toolNameFor(app.id, action.name),
    arguments: arguments,
    conversationId: scope,
    owner: ToolApprovalOwner(
      conversationId: scope,
      generationRunId: callId,
      assistantMessageId: callId,
      isActive: isActive,
    ),
  );
  ModalRoute<dynamic>? route;
  var resolved = false;
  void closeSheet() {
    final current = route;
    if (current != null && current.isActive) {
      current.navigator?.removeRoute(current);
    }
  }

  try {
    final request = approvals.pendingFor(
      toolCallId: callId,
      conversationId: scope,
    );
    if (request == null) return (await result).approved && isActive();
    // Use the service's redacted display snapshot for shared web actions too.
    final displayed = request.arguments;
    final sheet = showCustomBottomSheet<void>(
      context: context,
      title: l10n.miniAppsNativeConfirmTitle,
      builder: (sheetContext, controller) {
        route = ModalRoute.of(sheetContext);
        if (resolved) {
          WidgetsBinding.instance.addPostFrameCallback((_) => closeSheet());
        }
        return Material(
          type: MaterialType.transparency,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                app.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(action.description),
              if (action.danger == MiniAppDanger.root) ...[
                const SizedBox(height: 12),
                Text(l10n.miniAppsNativeRootWarning),
              ],
              if (displayed['enabled'] is bool) ...[
                const SizedBox(height: 8),
                Text(
                  displayed['enabled'] == true
                      ? l10n.miniAppsNativeOn
                      : l10n.miniAppsNativeOff,
                ),
              ],
              if (displayed['packageName'] is String) ...[
                const SizedBox(height: 8),
                Text(displayed['packageName'] as String),
              ],
              if (displayed.isNotEmpty)
                ExpansionTile(
                  title: Text(l10n.computerAllParameters),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(displayed),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        approvals.deny(callId, conversationId: scope),
                    child: Text(l10n.toolApprovalDeny),
                  ),
                  FilledButton(
                    onPressed: () =>
                        approvals.approve(callId, conversationId: scope),
                    child: Text(l10n.toolApprovalApprove),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    unawaited(
      result.then((_) {
        resolved = true;
        closeSheet();
      }),
    );
    await sheet;
    approvals.deny(callId, conversationId: scope, reason: 'cancelled');
    return (await result).approved && isActive();
  } finally {
    settings?.removeListener(syncTrust);
    approvals.deny(callId, conversationId: scope, reason: 'cancelled');
  }
}

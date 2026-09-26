import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/compress_context_options.dart';
import '../../../core/models/model_context_window.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/services/model_override_resolver.dart';
import '../../../core/services/logging/flutter_logger.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import 'model_edit_state_helper.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

part 'model_detail_widgets.dart';

Future<bool?> showModelDetailSheet(
  BuildContext context, {
  required String providerKey,
  required String modelId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ModelDetailSheet(
          providerKey: providerKey,
          modelId: modelId,
          isNew: false,
        ),
      ),
    ),
  );
}

Future<bool?> showCreateModelSheet(
  BuildContext context, {
  required String providerKey,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ModelDetailSheet(
          providerKey: providerKey,
          modelId: '',
          isNew: true,
        ),
      ),
    ),
  );
}

class _ModelDetailSheet extends StatefulWidget {
  const _ModelDetailSheet({
    required this.providerKey,
    required this.modelId,
    this.isNew = false,
  });
  final String providerKey;
  final String modelId;
  final bool isNew;
  @override
  State<_ModelDetailSheet> createState() => _ModelDetailSheetState();
}

enum _TabKind { basic, advanced, tools }

class _ModelDetailSheetState extends State<_ModelDetailSheet>
    with SingleTickerProviderStateMixin {
  _TabKind _tab = _TabKind.basic;
  late final TabController _tabCtrl;
  late final bool _showBuiltinToolsTab;

  late TextEditingController _idCtrl;
  late TextEditingController _nameCtrl;
  final TextEditingController _contextCtrl = TextEditingController();
  bool _nameEdited = false;
  ModelType _type = ModelType.chat;
  final Set<Modality> _input = {Modality.text};
  final Set<Modality> _output = {Modality.text};
  final Set<ModelAbility> _abilities = {};
  Set<Modality>? _cachedChatInput;
  Set<Modality>? _cachedChatOutput;
  Set<ModelAbility>? _cachedChatAbilities;
  Set<Modality>? _cachedEmbeddingInput;

  // Advanced (UI only)
  final List<_HeaderKV> _headers = [];
  final List<_BodyKV> _bodies = [];

  /// Built-in tool names toggled on, mirroring the persisted set.
  Set<String> _builtInTools = <String>{};

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey);
    // Determine tab count: 3 when the provider exposes editable built-in
    // tools, 2 for others
    _showBuiltinToolsTab = BuiltInToolsHelper.modelSettingsToolNames(
      cfg,
    ).isNotEmpty;
    _tabCtrl = TabController(length: _showBuiltinToolsTab ? 3 : 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() {
        if (_tabCtrl.index == 0) {
          _tab = _TabKind.basic;
        } else if (_tabCtrl.index == 1) {
          _tab = _TabKind.advanced;
        } else {
          _tab = _TabKind.tools;
        }
      });
    });
    // Resolve display model id from per-model overrides when present (apiModelId),
    // falling back to the logical key for backwards compatibility.
    Map<String, dynamic>? initialOv;
    if (!widget.isNew) {
      final raw = cfg.modelOverrides[widget.modelId];
      if (raw is Map) {
        initialOv = raw.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    String displayModelId = widget.modelId;
    if (initialOv != null) {
      final raw = (initialOv['apiModelId'] ?? initialOv['api_model_id'])
          ?.toString()
          .trim();
      if (raw != null && raw.isNotEmpty) {
        displayModelId = raw;
      }
    }
    _idCtrl = TextEditingController(text: displayModelId);
    // Defaults from inferred base if id provided; otherwise generic defaults for new
    final base = ModelRegistry.infer(
      ModelInfo(
        id: displayModelId.isEmpty ? 'custom' : displayModelId,
        displayName: displayModelId.isEmpty ? '' : displayModelId,
      ),
    );
    final ov = initialOv;
    final effective = ov == null
        ? base
        : ModelOverrideResolver.applyModelOverride(
            base,
            ov,
            applyDisplayName: true,
          );
    _nameCtrl = TextEditingController(text: effective.displayName);
    _type = effective.type;
    _input
      ..clear()
      ..addAll(effective.input);
    _output
      ..clear()
      ..addAll(effective.output);
    _abilities
      ..clear()
      ..addAll(effective.abilities);
    if (_type == ModelType.embedding) {
      if (_input.isEmpty) _input.add(Modality.text);
      _cachedEmbeddingInput = {..._input};
    } else if (_type == ModelType.chat) {
      if (_input.isEmpty) _input.add(Modality.text);
      if (_output.isEmpty) _output.add(Modality.text);
    }

    if (ov != null) {
      final contextWindow = readModelContextWindowTokens(ov);
      if (contextWindow != null) _contextCtrl.text = '$contextWindow';
      final rawHdrs = ov['headers'];
      final hdrs = (rawHdrs is List) ? rawHdrs : const <dynamic>[];
      for (final h in hdrs) {
        if (h is Map) {
          final kv = _HeaderKV();
          kv.name.text = h['name']?.toString() ?? '';
          kv.value.text = h['value']?.toString() ?? '';
          _headers.add(kv);
        }
      }
      final rawBds = ov['body'];
      final bds = (rawBds is List) ? rawBds : const <dynamic>[];
      for (final b in bds) {
        if (b is Map) {
          final kv = _BodyKV();
          kv.keyCtrl.text = b['key']?.toString() ?? '';
          kv.valueCtrl.text = b['value']?.toString() ?? '';
          _bodies.add(kv);
        }
      }
      // parseFromOverride, not parseAndNormalize: the request path reads the
      // legacy `tools` / `built_in_tools` keys too, and saving overwrites the
      // override wholesale — reading less here silently drops those settings.
      _builtInTools = BuiltInToolNames.parseFromOverride(ov);
    }
  }

  void _setType(ModelType next) {
    final prev = _type;
    if (prev == next) return;
    _type = next;
    final result = ModelEditTypeSwitch.apply(
      prev: prev,
      next: next,
      input: _input,
      output: _output,
      abilities: _abilities,
      cachedChatInput: _cachedChatInput,
      cachedChatOutput: _cachedChatOutput,
      cachedChatAbilities: _cachedChatAbilities,
      cachedEmbeddingInput: _cachedEmbeddingInput,
    );
    _input
      ..clear()
      ..addAll(result.input);
    _output
      ..clear()
      ..addAll(result.output);
    _abilities
      ..clear()
      ..addAll(result.abilities);
    _cachedChatInput = result.cachedChatInput;
    _cachedChatOutput = result.cachedChatOutput;
    _cachedChatAbilities = result.cachedChatAbilities;
    _cachedEmbeddingInput = result.cachedEmbeddingInput;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _contextCtrl.dispose();
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    for (final b in _bodies) {
      b.keyCtrl.dispose();
      b.valueCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (c, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            _buildHeader(context, l10n),
            _buildTabs(context, l10n),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  ..._buildTabContent(context, l10n),
                  const SizedBox(height: 12),
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
            _buildFooter(context, l10n),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            IosIconButton(
              icon: Lucide.X,
              size: 22,
              color: cs.onSurface,
              minSize: 36,
              onTap: () => Navigator.of(context).maybePop(false),
              semanticLabel: l10n.modelDetailSheetCancelButton,
            ),
            Expanded(
              child: Center(
                child: Text(
                  widget.isNew
                      ? l10n.modelDetailSheetAddModel
                      : l10n.modelDetailSheetEditModel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
            ),
            // Right spacer to balance title centering
            const SizedBox(width: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context, AppLocalizations l10n) {
    // iOS segmented tabs like provider add sheet
    final tabs = <String>[
      l10n.modelDetailSheetBasicTab,
      l10n.modelDetailSheetAdvancedTab,
      if (_showBuiltinToolsTab) l10n.modelDetailSheetBuiltinToolsTab,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SegTabBar(controller: _tabCtrl, tabs: tabs),
    );
  }

  List<Widget> _buildTabContent(BuildContext context, AppLocalizations l10n) {
    switch (_tab) {
      case _TabKind.basic:
        return _buildBasic(context, l10n);
      case _TabKind.advanced:
        return _buildAdvanced(context, l10n);
      case _TabKind.tools:
        return _buildTools(context, l10n);
    }
  }

  List<Widget> _buildBasic(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, l10n.modelDetailSheetModelIdLabel),
            const SizedBox(height: 6),
            TextField(
              controller: _idCtrl,
              readOnly: !widget.isNew, // existing model ID is read-only
              enableInteractiveSelection: widget.isNew,
              style: TextStyle(
                color: widget.isNew
                    ? null
                    : cs.onSurface.withValues(alpha: 0.6),
              ),
              onChanged: widget.isNew
                  ? (v) {
                      if (!_nameEdited) {
                        _nameCtrl.text = v;
                        setState(() {});
                      }
                    }
                  : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: context.appColors.surfaceCard,
                hintText: l10n.modelDetailSheetModelIdHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 46,
                  minHeight: 40,
                ),
                suffixIcon: widget.isNew
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _CopySuffixButton(
                          onTap: () {
                            final text = _idCtrl.text.trim();
                            if (text.isEmpty) return;
                            Clipboard.setData(ClipboardData(text: text));
                            showAppSnackBar(
                              context,
                              message: l10n.shareProviderSheetCopiedMessage,
                              type: NotificationType.success,
                            );
                          },
                          tooltip: l10n.shareProviderSheetCopyButton,
                          icon: Lucide.Copy,
                          color: cs.onSurface.withValues(alpha: 0.9),
                          hoverColor: cs.onSurface.withValues(alpha: 0.08),
                          pressedColor: cs.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _label(context, l10n.modelDetailSheetModelNameLabel),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) {
                if (!_nameEdited) setState(() => _nameEdited = true);
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: context.appColors.surfaceCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _label(context, l10n.modelDetailSheetModelTypeLabel),
            const SizedBox(height: 6),
            _SegmentedSingle(
              options: [
                l10n.modelDetailSheetChatType,
                l10n.modelDetailSheetEmbeddingType,
              ],
              value: _type == ModelType.chat ? 0 : 1,
              onChanged: (i) => setState(
                () => _setType(i == 0 ? ModelType.chat : ModelType.embedding),
              ),
            ),
            if (_type == ModelType.chat) ...[
              const SizedBox(height: 12),
              _label(context, l10n.modelDetailSheetContextWindowLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _contextCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  // The family default applies while the field is empty.
                  hintText:
                      defaultContextWindowTokens(
                        _idCtrl.text.trim(),
                      )?.toString() ??
                      l10n.modelDetailSheetContextWindowHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, l10n.modelDetailSheetInputModesLabel),
            const SizedBox(height: 6),
            _SegmentedMulti(
              options: [
                l10n.modelDetailSheetTextMode,
                l10n.modelDetailSheetImageMode,
              ],
              isSelected: [
                _input.contains(Modality.text),
                _input.contains(Modality.image),
              ],
              onChanged: (idx) => setState(() {
                final mod = idx == 0 ? Modality.text : Modality.image;
                if (_input.contains(mod)) {
                  _input.remove(mod);
                  if (_input.isEmpty) _input.add(Modality.text);
                } else {
                  _input.add(mod);
                }
              }),
            ),
            if (_type == ModelType.chat) ...[
              const SizedBox(height: 12),
              _label(context, l10n.modelDetailSheetOutputModesLabel),
              const SizedBox(height: 6),
              _SegmentedMulti(
                options: [
                  l10n.modelDetailSheetTextMode,
                  l10n.modelDetailSheetImageMode,
                ],
                isSelected: [
                  _output.contains(Modality.text),
                  _output.contains(Modality.image),
                ],
                onChanged: (idx) => setState(() {
                  final mod = idx == 0 ? Modality.text : Modality.image;
                  if (_output.contains(mod)) {
                    _output.remove(mod);
                    if (_output.isEmpty) _output.add(Modality.text);
                  } else {
                    _output.add(mod);
                  }
                }),
              ),
              const SizedBox(height: 12),
              _label(context, l10n.modelDetailSheetAbilitiesLabel),
              const SizedBox(height: 6),
              _SegmentedMulti(
                options: [
                  l10n.modelDetailSheetToolsAbility,
                  l10n.modelDetailSheetReasoningAbility,
                ],
                isSelected: [
                  _abilities.contains(ModelAbility.tool),
                  _abilities.contains(ModelAbility.reasoning),
                ],
                allowEmpty: true,
                onChanged: (idx) => setState(() {
                  final ab = idx == 0
                      ? ModelAbility.tool
                      : ModelAbility.reasoning;
                  if (_abilities.contains(ab)) {
                    _abilities.remove(ab);
                  } else {
                    _abilities.add(ab);
                  }
                }),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAdvanced(BuildContext context, AppLocalizations l10n) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          l10n.modelDetailSheetCustomHeadersTitle,
          style: TextStyle(fontSize: 15, fontWeight: AppFontWeights.semibold),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            for (int i = 0; i < _headers.length; i++)
              _HeaderRow(
                kv: _headers[i],
                onDelete: () => setState(() {
                  final kv = _headers.removeAt(i);
                  kv.name.dispose();
                  kv.value.dispose();
                }),
              ),
            const SizedBox(height: 8),
            _OutlinedAddButton(
              label: l10n.modelDetailSheetAddHeader,
              onTap: () => setState(() => _headers.add(_HeaderKV())),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          l10n.modelDetailSheetCustomBodyTitle,
          style: TextStyle(fontSize: 15, fontWeight: AppFontWeights.semibold),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            for (int i = 0; i < _bodies.length; i++)
              _BodyRow(
                kv: _bodies[i],
                onDelete: () => setState(() {
                  final kv = _bodies.removeAt(i);
                  kv.keyCtrl.dispose();
                  kv.valueCtrl.dispose();
                }),
              ),
            const SizedBox(height: 8),
            _OutlinedAddButton(
              label: l10n.modelDetailSheetAddBody,
              onTap: () => setState(() => _bodies.add(_BodyKV())),
            ),
          ],
        ),
      ),
    ];
  }

  void _toggleBuiltIn(String name, bool on) {
    setState(() {
      if (on) {
        _builtInTools.add(name);
      } else {
        _builtInTools.remove(name);
      }
    });
  }

  List<Widget> _buildTools(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey);
    final bool disableTools = _type == ModelType.embedding;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          l10n.modelDetailSheetBuiltinToolsDescription,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.8),
            fontSize: 13,
          ),
        ),
      ),
      for (final (index, tool) in ModelBuiltInToolTiles.forConfig(
        cfg: cfg,
        l10n: l10n,
      ).indexed)
        Padding(
          padding: EdgeInsets.fromLTRB(16, index == 0 ? 10 : 8, 16, 0),
          child: _ToolTile(
            title: tool.title,
            desc: tool.desc,
            value: tool.available && _builtInTools.contains(tool.name),
            onChanged: disableTools || !tool.available
                ? null
                : (v) => _toggleBuiltIn(tool.name, v),
          ),
        ),
    ];
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: IosTileButton(
          icon: widget.isNew ? Lucide.Plus : Lucide.Check,
          label: widget.isNew
              ? l10n.modelDetailSheetAddButton
              : l10n.modelDetailSheetConfirmButton,
          backgroundColor: cs.primary,
          onTap: _save,
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
    ),
  );

  // Generate a unique logical key for a model instance within a provider.
  // This allows multiple configurations to share the same upstream API model id.
  String _nextModelKey(ProviderConfig cfg, String apiModelId) {
    final existing = <String>{...cfg.models, ...cfg.modelOverrides.keys};
    if (!existing.contains(apiModelId)) return apiModelId;
    int i = 2;
    while (true) {
      final candidate = '$apiModelId#$i';
      if (!existing.contains(candidate)) return candidate;
      i++;
    }
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey);
    final l10n = AppLocalizations.of(context)!;
    // Logical key used inside configs (stable across edits)
    final String prevKey = widget.modelId;
    // Upstream/vendor model id typed by the user
    final String apiModelId = _idCtrl.text.trim();
    // Basic validation
    if (apiModelId.isEmpty || apiModelId.length < 2) {
      showAppSnackBar(
        context,
        message: l10n.modelDetailSheetInvalidIdError,
        type: NotificationType.error,
      );
      return;
    }

    final ov = Map<String, dynamic>.from(old.modelOverrides);
    final headers = [
      for (final h in _headers)
        if (h.name.text.trim().isNotEmpty)
          {'name': h.name.text.trim(), 'value': h.value.text},
    ];
    final bodies = [
      for (final b in _bodies)
        if (b.keyCtrl.text.trim().isNotEmpty)
          {'key': b.keyCtrl.text.trim(), 'value': b.valueCtrl.text},
    ];
    final prev = (prevKey.isNotEmpty && ov[prevKey] is Map)
        ? (ov[prevKey] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final builtInSet = BuiltInToolsHelper.replaceModelSettingsTools(
      cfg: old,
      // Same reader as the load path: the legacy `tools` / `built_in_tools`
      // keys count too, or saving drops what they hold.
      current: BuiltInToolNames.parseFromOverride(prev),
      selected: _builtInTools,
    );
    final builtInTools = BuiltInToolNames.orderedForStorage(builtInSet);
    // Decide which logical key to use for this instance
    final String key = (prevKey.isEmpty || widget.isNew)
        ? _nextModelKey(old, apiModelId)
        : prevKey;
    final bool isEmbedding = _type == ModelType.embedding;
    final contextWindow = int.tryParse(_contextCtrl.text.trim()) ?? 0;
    ov[key] = {
      ...modelSyncMetadata(prev),
      'apiModelId': apiModelId,
      'name': _nameCtrl.text.trim(),
      'type': _type == ModelType.chat ? 'chat' : 'embedding',
      'input': _input
          .map((e) => e == Modality.image ? 'image' : 'text')
          .toList(),
      if (!isEmbedding)
        'output': _output
            .map((e) => e == Modality.image ? 'image' : 'text')
            .toList(),
      if (!isEmbedding)
        'abilities': _abilities
            .map((e) => e == ModelAbility.reasoning ? 'reasoning' : 'tool')
            .toList(),
      'headers': headers,
      'body': bodies,
      if (!isEmbedding && builtInTools.isNotEmpty) 'builtInTools': builtInTools,
      if (!isEmbedding && contextWindow > 0) 'contextWindow': contextWindow,
    };

    // Apply updates to provider config
    try {
      if (prevKey.isEmpty || widget.isNew) {
        // Creating a new model
        final list = old.models.toList()..add(key);
        await settings.setProviderConfig(
          widget.providerKey,
          old.copyWith(modelOverrides: ov, models: list),
        );
      } else {
        // Existing model instance; keep logical key stable and just persist overrides
        await settings.setProviderConfig(
          widget.providerKey,
          old.copyWith(modelOverrides: ov),
        );
      }
    } catch (e, st) {
      FlutterLogger.log(
        '[ModelDetailSheet] save failed: $e\n$st',
        tag: 'Model',
      );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.modelDetailSheetSaveFailedMessage,
        type: NotificationType.error,
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

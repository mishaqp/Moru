part of 'display_settings_page.dart';

class RenderingSettingsPage extends StatelessWidget {
  const RenderingSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    // Rebuild only for the settings this page shows.
    context.select<SettingsProvider, Object>(
      (s) => (
        s.autoCollapseCodeBlock,
        s.autoCollapseCodeBlockLines,
        s.enableAssistantMarkdown,
        s.enableDollarLatex,
        s.enableMathRendering,
        s.enableReasoningMarkdown,
        s.enableUserMarkdown,
        s.mobileCodeBlockWrap,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.displaySettingsPageRenderingSettingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Hash,
                label: l10n.displaySettingsPageEnableDollarLatexTitle,
                value: sp.enableDollarLatex,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableDollarLatex(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Code,
                label: l10n.displaySettingsPageEnableMathTitle,
                value: sp.enableMathRendering,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableMathRendering(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.TextSelect,
                label: l10n.displaySettingsPageEnableUserMarkdownTitle,
                value: sp.enableUserMarkdown,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableUserMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Brain,
                label: l10n.displaySettingsPageEnableReasoningMarkdownTitle,
                value: sp.enableReasoningMarkdown,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setEnableReasoningMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.displaySettingsPageEnableAssistantMarkdownTitle,
                value: sp.enableAssistantMarkdown,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setEnableAssistantMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FoldVertical,
                label: l10n.displaySettingsPageAutoCollapseCodeBlockTitle,
                value: sp.autoCollapseCodeBlock,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setAutoCollapseCodeBlock(v),
              ),
              if (sp.autoCollapseCodeBlock) ...[
                _iosDivider(context),
                _NumberFieldRow(
                  icon: Lucide.ListOrdered,
                  label:
                      l10n.displaySettingsPageAutoCollapseCodeBlockLinesTitle,
                  unit: l10n.displaySettingsPageAutoCollapseCodeBlockLinesUnit,
                  value: sp.autoCollapseCodeBlockLines,
                  min: 1,
                  max: 999,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setAutoCollapseCodeBlockLines(v),
                ),
              ],
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.WrapText,
                label: l10n.displaySettingsPageMobileCodeBlockWrapTitle,
                value: sp.mobileCodeBlockWrap,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setMobileCodeBlockWrap(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberFieldRow extends StatefulWidget {
  const _NumberFieldRow({
    required this.icon,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String unit;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberFieldRow> createState() => _NumberFieldRowState();
}

class _NumberFieldRowState extends State<_NumberFieldRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) _commit();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim()) ?? widget.value;
    final next = parsed.clamp(widget.min, widget.max);
    widget.onChanged(next);
    final text = '$next';
    if (_controller.text != text) {
      _controller.value = _controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Keep controller in sync when not editing
    if (!_focusNode.hasFocus) {
      final t = '${widget.value}';
      if (_controller.text != t) _controller.text = t;
    }

    final baseColor = cs.onSurface.withValues(alpha: 0.9);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.28),
        width: 0.8,
      ),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.0),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Icon(widget.icon, size: 20, color: baseColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 15, color: baseColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, maxWidth: 80),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: baseBorder,
                  enabledBorder: baseBorder,
                  focusedBorder: focusBorder,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.unit,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

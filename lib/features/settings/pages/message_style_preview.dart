part of 'message_style_settings_page.dart';

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.theme,
    required this.editingDark,
    required this.editingUser,
    required this.style,
    required this.userOverrides,
    required this.assistantOverrides,
  });

  final ThemeData theme;
  final bool editingDark;
  final bool editingUser;
  final ChatMessageBackgroundStyle style;
  final ChatBubbleStyleOverrides userOverrides;
  final ChatBubbleStyleOverrides assistantOverrides;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.10),
          width: 0.6,
        ),
      ),
      child: SizedBox(
        height: 220,
        child: Theme(
          key: ValueKey<bool>(editingDark),
          data: theme,
          child: _PreviewScene(
            style: style,
            userOverrides: userOverrides,
            assistantOverrides: assistantOverrides,
            editingUser: editingUser,
          ),
        ),
      ),
    );
  }
}

class _PreviewScene extends StatelessWidget {
  const _PreviewScene({
    required this.style,
    required this.userOverrides,
    required this.assistantOverrides,
    required this.editingUser,
  });

  final ChatMessageBackgroundStyle style;
  final ChatBubbleStyleOverrides userOverrides;
  final ChatBubbleStyleOverrides assistantOverrides;
  final bool editingUser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final userResolved = resolveBubbleStyle(
      cs,
      brightness,
      style,
      userOverrides,
    );
    final assistantResolved = resolveBubbleStyle(
      cs,
      brightness,
      style,
      assistantOverrides,
    );
    final dimInactive = style != ChatMessageBackgroundStyle.defaultStyle;
    Widget maybeDim({required bool active, required Widget child}) {
      if (!dimInactive || active) return child;
      return Opacity(opacity: 0.45, child: child);
    }

    return ChatFrostedBackdrop(
      backdrop: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cs.surface),
          const MobileBackgroundLayer(),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: maybeDim(
                      active: editingUser,
                      child: _PreviewSurface(
                        style: style,
                        resolved: userResolved,
                        defaultColor: brightness == Brightness.dark
                            ? cs.primary.withValues(alpha: 0.15)
                            : cs.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.all(11),
                        child: Text(
                          l10n.messageStyleSettingsPagePreviewUser,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color:
                                style == ChatMessageBackgroundStyle.defaultStyle
                                ? cs.onSurface
                                : userResolved.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                maybeDim(
                  active: !editingUser,
                  child: _PreviewSurface(
                    style: style,
                    resolved: assistantResolved,
                    defaultColor: cs.primaryContainer.withValues(
                      alpha: brightness == Brightness.dark ? 0.25 : 0.30,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    child: Row(
                      children: [
                        ReasoningIcons.thinkingCardIcon(
                          size: 16,
                          color: _previewStrong(context, assistantResolved),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.messageStyleSettingsPagePreviewThinking,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: AppFontWeights.emphasis,
                              color: _previewStrong(context, assistantResolved),
                            ),
                          ),
                        ),
                        Icon(
                          Lucide.ChevronRight,
                          size: 16,
                          color: _previewStrong(context, assistantResolved),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: maybeDim(
                      active: !editingUser,
                      child: _PreviewSurface(
                        style: style,
                        resolved: assistantResolved,
                        bareOnDefault: true,
                        padding: const EdgeInsets.all(11),
                        child: Text(
                          l10n.messageStyleSettingsPagePreviewAssistant,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color:
                                style == ChatMessageBackgroundStyle.defaultStyle
                                ? cs.onSurface
                                : assistantResolved.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _previewStrong(BuildContext context, ResolvedBubbleStyle resolved) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final style = context.read<SettingsProvider>().chatMessageBackgroundStyle;
  if (style == ChatMessageBackgroundStyle.defaultStyle) {
    return cs.secondary;
  }
  final isDark = theme.brightness == Brightness.dark;
  return resolved.text.withValues(alpha: isDark ? 0.88 : 0.78);
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({
    required this.style,
    required this.resolved,
    required this.padding,
    required this.child,
    this.defaultColor,
    this.bareOnDefault = false,
  });

  final ChatMessageBackgroundStyle style;
  final ResolvedBubbleStyle resolved;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Color? defaultColor;
  final bool bareOnDefault;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(padding: padding, child: child);
    switch (style) {
      case ChatMessageBackgroundStyle.frosted:
        return FrostedSurface(
          style: resolved,
          borderRadius: BorderRadius.circular(resolved.radius),
          child: padded,
        );
      case ChatMessageBackgroundStyle.solid:
        final radius = BorderRadius.circular(resolved.radius);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: resolved.background,
            borderRadius: radius,
            border: Border.all(
              color: resolved.border,
              width: resolved.borderWidth,
            ),
          ),
          child: padded,
        );
      case ChatMessageBackgroundStyle.defaultStyle:
        if (bareOnDefault) return child;
        if (defaultColor == null) return padded;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: defaultColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: padded,
        );
    }
  }
}

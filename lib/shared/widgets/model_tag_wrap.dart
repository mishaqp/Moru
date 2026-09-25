import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/models/model_types.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// Shared model tag/capsule renderer used across model lists.
class ModelTagWrap extends StatelessWidget {
  const ModelTagWrap({super.key, required this.model});

  final ModelInfo model;

  Widget _abilityChip({
    required bool isDark,
    required String label,
    required Color baseColor,
    required EdgeInsets padding,
    required Widget child,
    required double darkBgAlpha,
    required double lightBgAlpha,
    required double borderAlpha,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? baseColor.withValues(alpha: darkBgAlpha)
                  : baseColor.withValues(alpha: lightBgAlpha),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: baseColor.withValues(alpha: borderAlpha),
                width: 0.5,
              ),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isEmbedding = model.type == ModelType.embedding;
    final chatLabel = l10n?.modelSelectSheetChatType ?? 'Chat';
    final embeddingLabel = l10n?.modelSelectSheetEmbeddingType ?? 'Embedding';
    final textLabel = l10n?.modelDetailSheetTextMode ?? 'Text';
    final imageLabel = l10n?.modelDetailSheetImageMode ?? 'Image';
    final toolsLabel = l10n?.modelDetailSheetToolsAbility ?? 'Tools';
    final reasoningLabel =
        l10n?.modelDetailSheetReasoningAbility ?? 'Reasoning';

    final chips = <Widget>[];

    chips.add(
      Container(
        decoration: BoxDecoration(
          color: isDark
              ? cs.primary.withValues(alpha: 0.25)
              : cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          model.type == ModelType.chat ? chatLabel : embeddingLabel,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? cs.primary : cs.primary.withValues(alpha: 0.9),
            fontWeight: AppFontWeights.medium,
          ),
        ),
      ),
    );

    final bool embeddingHasNonTextMods =
        isEmbedding && model.input.any((m) => m != Modality.text);
    final inputMods = (isEmbedding && !embeddingHasNonTextMods)
        ? const [Modality.text]
        : (model.type == ModelType.chat && model.input.isEmpty
              ? const [Modality.text]
              : model.input);
    final outputMods = isEmbedding
        ? const [Modality.text]
        : (model.type == ModelType.chat && model.output.isEmpty
              ? const [Modality.text]
              : model.output);

    final inputModsUnique = LinkedHashSet<Modality>.from(
      inputMods,
    ).toList(growable: false);
    final outputModsUnique = LinkedHashSet<Modality>.from(
      outputMods,
    ).toList(growable: false);
    String modLabel(Modality m) => m == Modality.text ? textLabel : imageLabel;
    final ioLabel =
        '${inputModsUnique.map(modLabel).join(', ')} -> ${outputModsUnique.map(modLabel).join(', ')}';

    chips.add(
      Tooltip(
        message: ioLabel,
        child: Semantics(
          label: ioLabel,
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? cs.tertiary.withValues(alpha: 0.25)
                    : cs.tertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: cs.tertiary.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mod in inputModsUnique)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        mod == Modality.text ? Lucide.Type : Lucide.Image,
                        size: 12,
                        color: isDark
                            ? cs.tertiary
                            : cs.tertiary.withValues(alpha: 0.9),
                      ),
                    ),
                  Icon(
                    Lucide.ChevronRight,
                    size: 12,
                    color: isDark
                        ? cs.tertiary
                        : cs.tertiary.withValues(alpha: 0.9),
                  ),
                  for (final mod in outputModsUnique)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        mod == Modality.text ? Lucide.Type : Lucide.Image,
                        size: 12,
                        color: isDark
                            ? cs.tertiary
                            : cs.tertiary.withValues(alpha: 0.9),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!isEmbedding) {
      final uniqueAbilities = LinkedHashSet<ModelAbility>.from(model.abilities);
      for (final ab in uniqueAbilities) {
        if (ab == ModelAbility.tool) {
          chips.add(
            _abilityChip(
              isDark: isDark,
              label: toolsLabel,
              baseColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Icon(
                Lucide.Hammer,
                size: 12,
                color: isDark ? cs.primary : cs.primary.withValues(alpha: 0.9),
              ),
              darkBgAlpha: 0.25,
              lightBgAlpha: 0.15,
              borderAlpha: 0.2,
            ),
          );
        } else if (ab == ModelAbility.reasoning) {
          chips.add(
            _abilityChip(
              isDark: isDark,
              label: reasoningLabel,
              baseColor: cs.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: SvgPicture.asset(
                'assets/icons/deepthink.svg',
                width: 12,
                height: 12,
                colorFilter: ColorFilter.mode(
                  isDark ? cs.secondary : cs.secondary.withValues(alpha: 0.9),
                  BlendMode.srcIn,
                ),
                errorBuilder: (_, __, ___) {
                  if (kDebugMode) {
                    debugPrint(
                      '[ModelTagWrap] Failed to load assets/icons/deepthink.svg',
                    );
                  }
                  return Icon(
                    Lucide.Brain,
                    size: 12,
                    color: isDark
                        ? cs.secondary
                        : cs.secondary.withValues(alpha: 0.9),
                  );
                },
                placeholderBuilder: (_) {
                  return Icon(
                    Lucide.Brain,
                    size: 12,
                    color: isDark
                        ? cs.secondary
                        : cs.secondary.withValues(alpha: 0.9),
                  );
                },
              ),
              darkBgAlpha: 0.3,
              lightBgAlpha: 0.18,
              borderAlpha: 0.25,
            ),
          );
        }
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}

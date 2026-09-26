import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_semantic_colors.dart';

/// The rounded search field of the provider list and the models tab.
class ProviderSearchField extends StatelessWidget {
  const ProviderSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasText = controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: cs.onSurface, fontSize: 14),
        cursorColor: cs.primary,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.5),
            fontSize: 13.5,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          prefixIcon: Icon(
            Lucide.Search,
            size: 16,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Lucide.X,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.48),
                  ),
                  tooltip: hintText,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          filled: true,
          fillColor: context.appColors.surfaceFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';

class ScheduledTargetChoice {
  const ScheduledTargetChoice(this.id, this.title, this.subtitle);
  final String id, title, subtitle;
}

Future<String?> showScheduledTargetPicker(
  BuildContext context, {
  required String title,
  required List<ScheduledTargetChoice> choices,
  String? selected,
}) {
  Widget content() =>
      _TargetPicker(title: title, choices: choices, selected: selected);

  return showFormSheet<String>(context, builder: (_) => content());
}

class _TargetPicker extends StatefulWidget {
  const _TargetPicker({
    required this.title,
    required this.choices,
    required this.selected,
  });
  final String title;
  final List<ScheduledTargetChoice> choices;
  final String? selected;
  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  final query = TextEditingController();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final search = query.text.trim().toLowerCase();
    final choices = widget.choices
        .where(
          (choice) => '${choice.title} ${choice.subtitle}'
              .toLowerCase()
              .contains(search),
        )
        .toList();
    final children = <Widget>[
      IosFormTextField(
        label: l.scheduledTasksSearch,
        hintText: l.scheduledTasksSearch,
        controller: query,
        inlineLabel: false,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      if (choices.isEmpty)
        IosSectionFooter(text: l.scheduledTasksNoTargets)
      else
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .42,
          child: SectionCard(
            child: ListView.separated(
              itemCount: choices.length,
              separatorBuilder: (_, _) => const IosRowDivider(indent: 12),
              itemBuilder: (context, index) {
                final choice = choices[index];
                return IosNavRow(
                  label: choice.title,
                  subtitle: choice.subtitle,
                  subtitleMaxLines: 2,
                  trailing: choice.id == widget.selected
                      ? Icon(
                          LucideIcons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const SizedBox.shrink(),
                  onTap: () => Navigator.pop(context, choice.id),
                );
              },
            ),
          ),
        ),
    ];

    return FormSheet(title: widget.title, children: children);
  }
}

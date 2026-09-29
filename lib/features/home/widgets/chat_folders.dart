import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/chat_folder.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/option_sheet.dart';

/// The Lucide icon of a folder icon key.
IconData chatFolderIcon(String key) => switch (key) {
  'briefcase' => LucideIcons.briefcase,
  'code' => LucideIcons.code,
  'gamepad' => LucideIcons.gamepad2,
  'book' => LucideIcons.bookOpen,
  'star' => LucideIcons.star,
  'heart' => LucideIcons.heart,
  'music' => LucideIcons.music,
  'image' => LucideIcons.image,
  'plane' => LucideIcons.plane,
  'home' => LucideIcons.house,
  'flask' => LucideIcons.flaskConical,
  _ => LucideIcons.folder,
};

/// Asks for a folder name; null when cancelled or left empty.
Future<String?> askChatFolderName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(title: title, initial: initial),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Owns its text controller, so the field outlives the pop animation.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: l10n.sideDrawerFolderNameHint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.sideDrawerCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.sideDrawerSave),
        ),
      ],
    );
  }
}

/// Creates a folder named by the user and returns it, or null.
Future<ChatFolder?> createChatFolder(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final name = await askChatFolderName(
    context,
    title: l10n.sideDrawerNewFolder,
  );
  if (name == null) return null;
  final folder = ChatFolder(id: const Uuid().v4(), name: name, icon: 'folder');
  await settings.setSidebarFolders([...settings.sidebarFolders, folder]);
  return folder;
}

/// Lets the user put [chatId] into a folder, take it out, or start a new
/// folder for it.
Future<void> moveChatToFolder(
  BuildContext context, {
  required String chatId,
  required String? currentFolderId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final chats = context.read<ChatService>();
  const none = '\u0000none';
  const create = '\u0000new';
  final choice = await showOptionSheet<String>(
    context,
    title: l10n.sideDrawerMoveToFolder,
    selected: currentFolderId,
    items: [
      for (final folder in settings.sidebarFolders)
        OptionSheetItem(
          value: folder.id,
          icon: chatFolderIcon(folder.icon),
          label: folder.name,
        ),
      if (currentFolderId != null)
        OptionSheetItem(
          value: none,
          icon: LucideIcons.folderOutput,
          label: l10n.sideDrawerNoFolder,
        ),
      OptionSheetItem(
        value: create,
        icon: LucideIcons.folderPlus,
        label: l10n.sideDrawerNewFolder,
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  var folderId = choice == none ? null : choice;
  if (choice == create) {
    final folder = await createChatFolder(context);
    if (folder == null) return;
    folderId = folder.id;
  }
  await chats.setConversationsFolder([chatId], folderId);
}

/// The menu of a folder header: rename, change the icon, delete.
Future<void> showChatFolderMenu(BuildContext context, ChatFolder folder) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final chats = context.read<ChatService>();
  final action = await showOptionSheet<String>(
    context,
    title: folder.name,
    items: [
      OptionSheetItem(
        value: 'rename',
        icon: LucideIcons.pencil,
        label: l10n.sideDrawerMenuRename,
      ),
      OptionSheetItem(
        value: 'icon',
        icon: chatFolderIcon(folder.icon),
        label: l10n.sideDrawerFolderIcon,
      ),
      OptionSheetItem(
        value: 'delete',
        icon: LucideIcons.trash2,
        label: l10n.sideDrawerFolderDelete,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  List<ChatFolder> replaced(ChatFolder next) => [
    for (final f in settings.sidebarFolders) f.id == folder.id ? next : f,
  ];
  switch (action) {
    case 'rename':
      final name = await askChatFolderName(
        context,
        title: l10n.sideDrawerMenuRename,
        initial: folder.name,
      );
      if (name == null) return;
      await settings.setSidebarFolders(replaced(folder.copyWith(name: name)));
    case 'icon':
      final icon = await _pickFolderIcon(context, folder.icon);
      if (icon == null) return;
      await settings.setSidebarFolders(replaced(folder.copyWith(icon: icon)));
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.sideDrawerFolderDelete),
          content: Text(l10n.sideDrawerFolderDeleteContent(folder.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.sideDrawerCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.sideDrawerFolderDelete,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // The chats go back to the date groups; nothing is deleted.
      final inFolder = [
        for (final c in chats.getAllConversations())
          if (ChatService.folderOf(c) == folder.id) c.id,
      ];
      await settings.setSidebarFolders([
        for (final f in settings.sidebarFolders)
          if (f.id != folder.id) f,
      ]);
      unawaited(chats.setConversationsFolder(inFolder, null));
  }
}

/// A grid of the folder icons; the current one is highlighted.
Future<String?> _pickFolderIcon(BuildContext context, String current) {
  final l10n = AppLocalizations.of(context)!;
  return showFormSheet<String>(
    context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return FormSheet(
        title: l10n.sideDrawerFolderIcon,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final key in ChatFolder.icons)
                InkWell(
                  key: ValueKey<String>('folder-icon-$key'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(ctx).pop(key),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: key == current
                          ? cs.primary.withValues(alpha: 0.16)
                          : cs.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      chatFolderIcon(key),
                      size: 22,
                      color: key == current ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}

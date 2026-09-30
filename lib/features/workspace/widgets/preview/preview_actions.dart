import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:Kelivo/l10n/app_localizations.dart';
import 'preview_file_server.dart';
import 'package:Kelivo/shared/utils/save_file_picker.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';

PreviewFileServer? _previewBrowserServer;
Timer? _previewBrowserServerTtl;
int _previewBrowserGeneration = 0;

Future<void> copyFilePath(BuildContext context, File file) async {
  final l10n = AppLocalizations.of(context)!;
  await Clipboard.setData(ClipboardData(text: file.path));
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    message: l10n.workspacePreviewPathCopied,
    type: NotificationType.success,
  );
}

Future<void> exportPreviewFile(BuildContext context, File file) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    final savePath = await saveHostFileWithPicker(
      file: file,
      dialogTitle: l10n.workspaceFilesExportItem,
    );
    if (savePath == null || !context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.messageExportSheetExportedAs(p.basename(savePath)),
      type: NotificationType.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.messageExportSheetExportFailed('$e'),
      type: NotificationType.error,
    );
  }
}

Future<void> sharePreviewFile(BuildContext context, File file) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: shareAnchorRect(context),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.messageExportSheetExportFailed('$e'),
      type: NotificationType.error,
    );
  }
}

Future<void> openPreviewFileExternally(BuildContext context, File file) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    final res = await OpenFilex.open(file.path);
    if (res.type != ResultType.done && context.mounted) {
      showAppSnackBar(
        context,
        message: l10n.chatMessageWidgetCannotOpenFile(res.message),
        type: NotificationType.error,
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.chatMessageWidgetOpenFileError(e.toString()),
      type: NotificationType.error,
    );
  }
}

Future<void> revealPreviewFileInFileManager(
  BuildContext context,
  File file,
) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    throw UnsupportedError('Reveal is only supported on desktop');
  } catch (e) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.workspacePreviewRevealFailed,
      type: NotificationType.error,
    );
  }
}

Future<void> openPreviewFileInBrowser(
  BuildContext context,
  File file, {
  File? sourceFile,
  String? accessRoot,
}) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    final uri = await startPreviewFileBrowserServer(
      sourceFile ?? file,
      accessRoot: accessRoot,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return;
    if (!context.mounted) return;
    if (Platform.isAndroid) {
      await openPreviewFileExternally(context, file);
      return;
    }
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: l10n.chatMessageWidgetCannotOpenFile(file.path),
        type: NotificationType.error,
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.workspacePreviewLoadError,
      type: NotificationType.error,
    );
  }
}

/// The external browser has no page disposal hook, so its independently owned
/// capability server expires after ten minutes. Embedded previews own theirs.
@visibleForTesting
Future<Uri> startPreviewFileBrowserServer(
  File file, {
  String? accessRoot,
}) async {
  final generation = ++_previewBrowserGeneration;
  await _closePreviewFileBrowserServer();
  if (generation != _previewBrowserGeneration) {
    throw StateError('Preview closed');
  }
  final server = await PreviewFileServer.start(
    sourceFile: file,
    accessRoot: accessRoot ?? file.parent.path,
  );
  if (generation != _previewBrowserGeneration) {
    await server.close();
    throw StateError('Preview closed');
  }
  _previewBrowserServer = server;
  _previewBrowserServerTtl = Timer(const Duration(minutes: 10), () {
    if (identical(_previewBrowserServer, server)) {
      unawaited(closePreviewFileBrowserServer());
    }
  });
  return server.uri;
}

@visibleForTesting
Future<void> closePreviewFileBrowserServer() async {
  _previewBrowserGeneration++;
  await _closePreviewFileBrowserServer();
}

Future<void> _closePreviewFileBrowserServer() async {
  _previewBrowserServerTtl?.cancel();
  _previewBrowserServerTtl = null;
  final server = _previewBrowserServer;
  _previewBrowserServer = null;
  await server?.close();
}

String revealInFileManagerLabel(AppLocalizations l10n) {
  return l10n.workspacePreviewRevealInFileManager;
}

Rect shareAnchorRect(BuildContext context) {
  try {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
  } catch (_) {}
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

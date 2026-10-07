import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/logging/problem_report_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/format_bytes.dart';
import '../../../shared/widgets/snackbar.dart';

class ProblemReportCard extends StatefulWidget {
  const ProblemReportCard({
    super.key,
    required this.name,
    required this.sizeBytes,
  });

  final String name;
  final int sizeBytes;

  static ProblemReportCard? fromContent(String? content) {
    try {
      final result = jsonDecode(content ?? '');
      if (result is! Map ||
          result['ok'] != true ||
          result['name'] is! String ||
          !ProblemReportService.isReportName(result['name'] as String) ||
          result['size_bytes'] is! int) {
        return null;
      }
      final size = result['size_bytes'] as int;
      if (size <= 0 || size > ProblemReportService.maxZipBytes) return null;
      return ProblemReportCard(name: result['name'] as String, sizeBytes: size);
    } catch (_) {
      return null;
    }
  }

  @override
  State<ProblemReportCard> createState() => _ProblemReportCardState();
}

class _ProblemReportCardState extends State<ProblemReportCard> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await ProblemReportService().withShareSnapshot(widget.name, (file) async {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: 'application/zip')]),
        );
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.problemReportUnavailable,
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      Text(
        formatBytes(widget.sizeBytes),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      TextButton.icon(
        onPressed: _sharing ? null : _share,
        icon: const Icon(Lucide.Share2, size: 18),
        label: Text(AppLocalizations.of(context)!.messageMoreSheetShare),
      ),
    ],
  );
}

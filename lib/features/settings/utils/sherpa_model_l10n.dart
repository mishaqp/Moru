import '../../../core/services/asr/sherpa_model_manager.dart';
import '../../../l10n/app_localizations.dart';

/// Display-only access; model IDs, downloads and runtime definitions stay intact.
extension SherpaModelLocalization on SherpaModelDefinition {
  String localizedName(AppLocalizations l10n) => switch (id) {
    'paraformer-zh-small-2024-03-09' => l10n.moruAsrParaformerName,
    'sense-voice-multilingual-int8-2025-09-09' => l10n.moruAsrSenseVoiceName,
    'zipformer-zh-en-mobile-2023-02-20' => l10n.moruAsrZipformerName,
    _ => name,
  };

  String localizedDescription(AppLocalizations l10n) => switch (id) {
    'paraformer-zh-small-2024-03-09' => l10n.moruAsrParaformerDescription,
    'sense-voice-multilingual-int8-2025-09-09' =>
      l10n.moruAsrSenseVoiceDescription,
    'zipformer-zh-en-mobile-2023-02-20' => l10n.moruAsrZipformerDescription,
    _ => description,
  };
}

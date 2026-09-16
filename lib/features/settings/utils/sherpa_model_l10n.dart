import '../../../core/services/asr/sherpa_model_manager.dart';
import '../../../l10n/app_localizations.dart';

/// Display-only access; model IDs, downloads and runtime definitions stay intact.
extension SherpaModelLocalization on SherpaModelDefinition {
  String localizedName(AppLocalizations l10n) => name;

  String localizedDescription(AppLocalizations l10n) => description;
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/model/widgets/model_edit_state_helper.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ModelBuiltInToolTiles.forConfig advertises nothing for the local '
    'provider -- no built-in tool toggle (search, code execution, etc.) is '
    'ever offered for an on-device model',
    () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final cfg = ProviderConfig(
        id: 'litert-local',
        enabled: true,
        name: 'Local',
        apiKey: '',
        baseUrl: '',
        providerType: ProviderKind.local,
      );

      final tiles = ModelBuiltInToolTiles.forConfig(cfg: cfg, l10n: l10n);

      expect(tiles, isEmpty);
    },
  );
}

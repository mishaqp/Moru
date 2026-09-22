import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/model/widgets/model_edit_state_helper.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ModelBuiltInToolTiles.forConfig advertises nothing for the local '
      'provider -- no built-in tool toggle (search, code execution, etc.) is '
      'ever offered for an on-device model', () async {
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
  });

  test(
    'modelSyncMetadata preserves an installed local model\'s file path and '
    'other LiteRT-only fields, not just the oauth keys -- '
    'ModelSelectSheet opens the same generic edit form on long-press for '
    'every provider\'s model tiles, local ones included, and that form has '
    'no field for any of this; without preserving it here, saving the form '
    'wipes localModelPath and turns a working installed model into one '
    'litert_local.dart refuses to run ("No local model file is configured")',
    () {
      final installed = <String, dynamic>{
        'name': 'Qwen3-0.6B_dynamic_wi4b32_afp32',
        'type': 'chat',
        'input': ['text'],
        'output': ['text'],
        'abilities': <String>[],
        'localModelPath': '/data/user/0/.../models/qwen3-0.6b.litertlm',
        'localBackend': 'cpu',
        'localSizeBytes': 344437808,
        'localSourceLabel': 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
        'localInstalledAtMillis': 1758000000000,
        'localSha256':
            'e3e290109da4388d65a17510a0c66af91c8039f52d2c465868dbc43c09a776cf',
      };

      final preserved = modelSyncMetadata(installed);

      expect(preserved['localModelPath'], installed['localModelPath']);
      expect(preserved['localBackend'], 'cpu');
      expect(preserved['localSizeBytes'], 344437808);
      expect(preserved['localSourceLabel'], installed['localSourceLabel']);
      expect(
        preserved['localInstalledAtMillis'],
        installed['localInstalledAtMillis'],
      );
      expect(preserved['localSha256'], installed['localSha256']);
    },
  );
}

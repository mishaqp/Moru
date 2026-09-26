import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'settings_provider.dart';

extension ProviderConfigWatch on BuildContext {
  /// The config of provider [key]; the widget rebuilds only when that config
  /// changes, not on every settings change. A provider without a saved config
  /// gets its defaults.
  ProviderConfig watchProviderConfig(String key, {String? defaultName}) {
    final saved = select<SettingsProvider, ProviderConfig?>(
      (s) => s.providerConfigs[key],
    );
    return saved ??
        read<SettingsProvider>().getProviderConfig(
          key,
          defaultName: defaultName,
        );
  }
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';

void main() {
  test(
    'mini_apps spec is discoverable and complete without app data access',
    () async {
      var loads = 0;
      final store = MiniAppStore(
        root: () async {
          loads++;
          throw const MiniAppException(
            'unexpected_io',
            'Specification must not read app data.',
          );
        },
      );
      final result =
          jsonDecode(
                await MiniAppDataTool(store: store).execute({'action': 'spec'}),
              )
              as Map;
      expect(result['ok'], true);
      expect(loads, 0);
      final spec = result['specification'] as Map;
      for (final section in [
        'manifest',
        'executors',
        'expressions',
        'components',
        'bindings',
        'deviceHandlers',
        'permissions',
        'examples',
        'limits',
      ]) {
        expect(spec.containsKey(section), true, reason: section);
      }
      expect(MiniAppDataTool.actions, contains('spec'));
      expect(
        MiniAppDataTool.definition['function']['description'],
        contains('spec'),
      );
    },
  );
}

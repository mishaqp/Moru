import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/asr/sherpa_model_manager.dart';
import 'package:Kelivo/features/settings/utils/sherpa_model_l10n.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'speech model names and descriptions are Russian without changing runtime metadata',
    () async {
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final originals = [
        for (final model in SherpaModelCatalog.models)
          (
            model.id,
            model.archiveUri,
            model.archiveRoot,
            model.requiredFiles.toList(),
          ),
      ];
      for (final model in SherpaModelCatalog.models) {
        expect(model.localizedName(ru), matches(RegExp('[А-Яа-яЁё]')));
        expect(model.localizedDescription(ru), matches(RegExp('[А-Яа-яЁё]')));
        expect(
          model.localizedDescription(ru),
          isNot(matches(RegExp('[\u4e00-\u9fff]'))),
        );
      }
      for (var i = 0; i < originals.length; i++) {
        final model = SherpaModelCatalog.models[i];
        expect(model.id, originals[i].$1);
        expect(model.archiveUri, originals[i].$2);
        expect(model.archiveRoot, originals[i].$3);
        expect(model.requiredFiles, originals[i].$4);
      }
    },
  );

  test(
    'speech model descriptions support English and preserve Chinese catalog presentation',
    () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      for (final model in SherpaModelCatalog.models) {
        expect(
          model.localizedDescription(en),
          isNot(matches(RegExp('[\u4e00-\u9fff]'))),
        );
        expect(model.localizedDescription(en), contains('English'));
        expect(model.localizedName(zh), model.name);
        expect(model.localizedDescription(zh), model.description);
      }
    },
  );

  for (final locale in ['ru', 'en']) {
    testWidgets(
      'code-fence fallback uses $locale while explicit language stays unchanged',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harness = await createBusinessTestHarness(
          initial: {'app_locale_v1': locale},
        );
        final settings = SettingsProvider(harness.preferences);
        await settings.loaded;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: settings,
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: MarkdownWithCodeHighlight(
                    text: '```\nplain sample\n```\n\n```python\nprint(42)\n```',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(locale == 'ru' ? 'Код' : 'Code'), findsWidgets);
        expect(find.text('python'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

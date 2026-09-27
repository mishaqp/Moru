import 'package:Kelivo/features/settings/search/settings_search_index.dart';
import 'package:Kelivo/l10n/app_localizations_en.dart';
import 'package:Kelivo/l10n/app_localizations_zh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final index = SettingsSearchIndex(en);

  test('exact setting names rank first; all query words must match', () {
    expect(
      index.search(en.displaySettingsPageShowToolCardsTitle).first.id,
      'displaySettingsPageShowToolCardsTitle',
    );
    expect(
      index.search('  font   size ').first.id,
      'displaySettingsPageChatFontSizeTitle',
    );
    expect(index.search('font impossiblequery'), isEmpty);
    expect(index.search(' \n\t '), isEmpty);
    expect(index.search('x' * 20000), isEmpty);
  });

  test('indexes English, simplified and traditional titles in any locale', () {
    final chinese = SettingsSearchIndex(AppLocalizationsZh());
    final traditional = SettingsSearchIndex(AppLocalizationsZhHant());
    for (final candidate in [index, chinese, traditional]) {
      expect(
        candidate.search('language').map((e) => e.id),
        contains('displaySettingsPageLanguageTitle'),
      );
      expect(
        candidate.search('語言').map((e) => e.id),
        contains('displaySettingsPageLanguageTitle'),
      );
      expect(
        candidate.search('字体').map((e) => e.id),
        contains('displaySettingsPageChatFontSizeTitle'),
      );
      expect(candidate.search('ａｐｉ　ｋｅｙ').first.id, 'providers');
      expect(
        candidate.search('毛玻璃').first.destination,
        SettingsSearchDestination.messageStyle,
      );
    }
  });

  test('runtime availability matches the settings surfaces', () {
    Set<String> ids({bool logs = false, bool dynamicColor = false}) =>
        SettingsSearchIndex(
          en,
          logsEnabled: logs,
          dynamicColorSupported: dynamicColor,
        ).entries.map((entry) => entry.id).toSet();
    expect(ids(), contains('scheduledTasks'));
    expect(ids(), isNot(contains('logs')));
    expect(ids(), isNot(contains('hotkeys')));
    expect(
      ids(logs: true, dynamicColor: true),
      containsAll([
        'scheduledTasks',
        'logs',
        'themeSettingsPageUseDynamicColorTitle',
      ]),
    );
  });

  test(
    'entries have stable unique ids, paths and localized destination labels',
    () {
      {
        final candidate = SettingsSearchIndex(en);
        expect(
          candidate.entries.map((e) => e.id).toSet().length,
          candidate.entries.length,
        );
        expect(candidate.suggestions, hasLength(6));
        final item = candidate.entries.firstWhere(
          (e) => e.id == 'displaySettingsPageShowToolCardsTitle',
        );
        expect(item.path, [
          'Settings',
          en.settingsPageDisplay,
          en.displaySettingsPageChatItemDisplayTitle,
        ]);
        expect(item.targetLabel, en.displaySettingsPageShowToolCardsTitle);
      }
    },
  );
}

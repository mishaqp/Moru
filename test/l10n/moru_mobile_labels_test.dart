import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remaining Android labels are localized without changing technical values', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(ru.moruSecondsShort(2), '2 с');
    expect(en.moruSecondsShort(2), '2s');
    expect(ru.moruProviderWebsitePrefix, 'Сайт: ');
    expect(en.moruProviderWebsitePrefix, 'Website: ');
    const source = 'https://example.com/script.js:42';
    expect(ru.moruConsoleSource(source), 'Источник: $source');
    expect(en.moruConsoleSource(source), 'Source: $source');
    for (final notice in [
      ru.moruProviderTensdaqNotice,
      ru.moruProviderSiliconFlowNotice,
      ru.moruProviderSuixiangNotice,
      ru.moruProviderMaruCodeNotice,
    ]) {
      expect(notice, matches(RegExp('[А-Яа-яЁё]')));
      expect(notice, isNot(matches(RegExp('[\u4e00-\u9fff]'))));
    }
    for (final value in ['Codex', 'Claude Code', 'GPT Image', '0.25x', '1.5x', '1:1']) {
      expect(ru.moruProviderMaruCodeNotice, contains(value));
    }
  });
}

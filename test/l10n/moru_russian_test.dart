import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Russian is supported without removing English or Chinese', () {
    for (final locale in [
      const Locale('ru'),
      const Locale('en'),
      const Locale('zh'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      expect(AppLocalizations.delegate.isSupported(locale), isTrue);
    }
  });

  test('RU covers settings, workspace, skills, memory and OAuth', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(ru.displaySettingsPageLanguageTitle, 'Язык приложения');
    expect(ru.workspacesTitle, 'Рабочие пространства');
    expect(ru.skillsTitle, 'Навыки');
    expect(ru.terminalTitle, 'Терминал');
    expect(ru.memorySettingsProfileTitle, 'Профиль пользователя');
    expect(ru.scheduledTasksTitle, 'Задачи по расписанию');
    expect(ru.toolSchemaSettingsPageTitle, 'Описания инструментов');
    expect(ru.oauthLoginTo('ChatGPT'), 'Войти в ChatGPT');
    expect(
      ru.modelDetailSheetModelIdDisabledHint('gpt-technical-id'),
      'gpt-technical-id',
    );
  });

  test('RU count grammar handles zero and compound numbers', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    for (final entry in {
      0: '0 результатов',
      1: '1 результат',
      2: '2 результата',
      5: '5 результатов',
      11: '11 результатов',
      21: '21 результат',
      22: '22 результата',
      25: '25 результатов',
      101: '101 результат',
    }.entries) {
      expect(ru.settingsSearchResultCount(entry.key), entry.value);
    }
    expect(ru.localSnapshotKeepValue(1), '1 копия');
    expect(ru.localSnapshotKeepValue(2), '2 копии');
    expect(ru.localSnapshotKeepValue(5), '5 копий');
    expect(ru.localSnapshotKeepValue(21), '21 копия');
    expect(ru.localSnapshotUsage(0, '12 MB'), 'Нет копий · 12 MB');
    expect(ru.localSnapshotCopyContents(22, 105), '22 чата · 105 сообщений');
    expect(ru.askUserCardQuestionCount(3), 'Задать 3 вопроса');
  });

  testWidgets('RU/EN switch does not keep stale strings', (tester) async {
    Future<void> showLocale(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) =>
                Scaffold(body: Text(AppLocalizations.of(context)!.skillsTitle)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await showLocale(const Locale('ru'));
    expect(find.text('Навыки'), findsOneWidget);
    await showLocale(const Locale('en'));
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Навыки'), findsNothing);
    await showLocale(const Locale('ru'));
    expect(find.text('Навыки'), findsOneWidget);
  });
}

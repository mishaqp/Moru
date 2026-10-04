# Опоры для локализации

## Генерация и CI

- [l10n.yaml](../../../l10n.yaml) задаёт `arb-dir: lib/l10n`, шаблон `app_en.arb`, output `app_localizations.dart` и `untranslated-messages-file: desiredFileName.txt` в корне репозитория.
- В [app_localizations_zh.dart](../../../lib/l10n/app_localizations_zh.dart) находятся `AppLocalizationsZh`, `AppLocalizationsZhHans` и `AppLocalizationsZhHant`; отдельных tracked Dart-файлов для Hans/Hant нет.
- [README → Contributing](../../../README.md#-contributing) требует `flutter gen-l10n` и generated outputs вместе с ARB. Команды общего набора сверяй по [AGENTS.md](../../../AGENTS.md#pre-commit-checklist), где форматируются только изменённые Dart-файлы.
- [`pr-check.yml`](../../../.github/workflows/pr-check.yml) проверяет чистый diff после генерации и новые untranslated. Скрипт [.github/scripts/check_no_new_untranslated.py](../../../.github/scripts/check_no_new_untranslated.py) принимает два JSON-отчёта: `python3 .github/scripts/check_no_new_untranslated.py <base-report> <head-report>`. Оба отчёта должны быть получены `flutter gen-l10n` для соответствующих ревизий; текущий отчёт — `desiredFileName.txt`.
- [`moru-android.yml`](../../../.github/workflows/moru-android.yml) также генерирует l10n и проверяет `git diff --exit-code -- pubspec.lock lib/l10n` перед анализом и тестами.

## Целевые проверки

- [tool/check_moru_ru.py](../../../tool/check_moru_ru.py): набор EN/RU ключей, пустые значения, имена ICU arguments и placeholder metadata. Исключения уже заданы в [moru_ru_technical_allowlist.json](../../../tool/moru_ru_technical_allowlist.json); добавляй туда только требуемые технические строки.
- [moru_catalog_validator_test.dart](../../../test/l10n/moru_catalog_validator_test.dart) включает исходный RU validator и его Python regression tests в `flutter test` CI.
- [moru_russian_test.dart](../../../test/l10n/moru_russian_test.dart): поддержка RU/EN/ZH, русские числительные и смена RU/EN без старых подписей. Команда целевого прогона при разрешённых Flutter-тестах: `flutter test test/l10n/moru_russian_test.dart`.
- Если новая строка меняет поведение виджета или подстановку, проверь затронутый UI-тест; одним source validator нельзя подтвердить размещение текста на экране.

## Проверенные PR

- [PR #95](https://github.com/mishaqp/Moru/pull/95): новые строки управления MCP, все пять ARB и четыре generated Dart-файла.
- [PR #98](https://github.com/mishaqp/Moru/pull/98): новые ключи лимитов расходов во всех пяти ARB, генерация и отсутствие новых untranslated.
- [PR #99](https://github.com/mishaqp/Moru/pull/99): дополнительные подписи управления MCP с синхронным изменением ARB и generated outputs.
- [PR #100](https://github.com/mishaqp/Moru/pull/100): изменение сообщений расходов и новые подстановки, `flutter gen-l10n` для en/ru/zh/zh_Hans/zh_Hant.

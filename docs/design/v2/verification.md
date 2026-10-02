# Проверки дизайн-пакета Moru v2

База: `af795269974fb38aa474ffd6afec537885ab17cb`, `claude/moru-v0-1-16-audit-s69yji`. Проверки выполнены в cloud-среде 1–2 октября 2026 года. Product tree идентичен базе: не изменены `lib/`, `test/`, `integration_test/`, `android/`, `pubspec.yaml`, зависимости или ARB. Рабочая ветка — `codex/moru-v2-design`.

## Чеклист AGENTS.md

Сначала выполнены `git fetch`, checkout указанной базы, `bash tool/codex_cloud_setup.sh`; каждый Flutter/Dart shell использовал `source "$HOME/.moru-toolchains/activate.sh"`. Версии: Flutter **3.44.9**, Dart **3.12.2**, SDK установлен вне репозитория.

| Команда | Результат |
|---|---|
| Format изменённых Dart | Изменённых Dart нет; форматировать неизменённый `lib/` запрещает отдельная оговорка AGENTS.md. |
| `dart analyze --fatal-infos lib test integration_test` | Exit 0, **No issues found!** |
| `flutter test --reporter expanded` | Exit 0, **+6990: All tests passed!**; без skip/retry/ослабления тестов. |
| `python3 -m unittest discover -s tool -p 'test_android_only_policy.py' -v` | Exit 0, **8 tests, OK** |
| `python3 -m unittest discover -s tool -p 'test_verify_apk_arm64.py' -v` | Exit 0, **6 tests, OK** |
| `python3 -m unittest discover -s tool -p 'test_verify_release_keep_rules.py' -v` | Exit 0, **3 tests, OK** |
| `git diff --check` / staged diff check | Без ошибок whitespace |
| Product-tree diff относительно базы | Пустой; все добавления в `docs/design/v2/` |

Эти Python suites проверяют policy и верификаторы на fixtures. Здесь **не собирался APK и не проверялась подпись настоящего APK**: AGENTS.md оставляет cloud APK builds CI. Версия не повышена, поскольку пользователь явно ограничил изменения `docs/`.

## Макеты

`build_mockups.py` создал **42 отдельных HTML**, по два для каждого из 21 сценария. `render_mockups.py` загрузил точные HTML-байты через Playwright `set_content` в headless `/usr/bin/chromium`, заблокировал внешние запросы, дождался embedded font. `file://` навигация в cloud Chromium запрещена административной policy; `set_content` не меняет HTML или viewport и не требует сервера. На локальном компьютере сами HTML открываются обычным способом.

Финальный [render-report.json](render-report.json): **42 passed / 0 failed**. На каждом экране проверены:

- `.phone` ровно 390×844 и PNG ровно 780×1688, DPR 2;
- отсутствие горизонтального переполнения;
- реальные размеры интерактивных button/input/textarea/select targets ≥48×48;
- загрузка встроенного Manrope, включая русские символы и веса 400/700/800;
- доступность нижних controls при вертикальной прокрутке;
- отсутствие внешних assets и ошибок JavaScript/Chromium.

Доска [board.png](board.png) собрана из этих PNG, пары расположены светлая→тёмная. Проверены вручную главная, корень настроек, работа агента, изменения файлов, плавающий браузер и общая доска. Повторный рендер исходных 40 экранов до последнего расширения давал одинаковые SHA-256; финальный отчёт содержит хеши каждого из 42 HTML/PNG для сверки.

Независимое ревью проверяло базовый текстовый контраст и интерактивный Appearance: тема/акцент, Glass brightness, системный/ручной режим, размер обеих ролей сообщения, исходный Markdown, model/language selection, reasoning summary, browser transitions. Найденные ошибки были исправлены; подробности финального ревью — [review.md](review.md).

Проверка HTML не заменяет TalkBack, системную nonlinear типографику Flutter, измерения blur/scroll на GPU, OEM-размещение уведомлений и реальный ACP/OAuth/Linux. Для этих случаев критерии перечислены в плане будущих PR в README; результатов устройства мы не заявляем.

## Полнота аудита и документация

Settings audit: **26/26** root controls, **200/200** persistence keys (с выделением служебных/legacy), **119/119** pages-файлов в 19 features. Поисковых типов данных 26, обычный selector предлагает 25 плюс отдельно разблокируемый Kelivo. Rendering-map, широкие Android keyboard settings и migration-readers проверены по исходникам.

Проверены 653 локальные Markdown-ссылки на файлы; пропусков нет. Диапазоны `файл:строка` также проверены. Точная карта leaves находится в `audit-settings.md`; runtime и theme документы содержат конкретные примеры и ограничения, а не только перечень папок.

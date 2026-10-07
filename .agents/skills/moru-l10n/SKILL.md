---
name: moru-l10n
description: Use when adding or changing Moru UI text or repairing missing or incorrect translations.
---

# Локализация интерфейса

Инструкции пользователя имеют приоритет над этим скилом; соблюдай заданные границы правки и проверок.
Общие требования локализации — [AGENTS.md → Architecture](../../../AGENTS.md#architecture); сборка и проверки — [Pre-commit checklist](../../../AGENTS.md#pre-commit-checklist).

- [ ] Найди существующий ключ и его UI-вызовы; при новом сообщении выбери ключ по соседнему экрану. Источник шаблона задаёт [l10n.yaml](../../../l10n.yaml), не generated Dart.
- [ ] Правь нужные исходники: [app_en.arb](../../../lib/l10n/app_en.arb), [app_ru.arb](../../../lib/l10n/app_ru.arb), [app_zh.arb](../../../lib/l10n/app_zh.arb), [app_zh_Hans.arb](../../../lib/l10n/app_zh_Hans.arb), [app_zh_Hant.arb](../../../lib/l10n/app_zh_Hant.arb). Новый ключ добавляй во все пять; при точечной правке русского сохраняй EN/ZH.
- [ ] Сохрани имена и типы placeholders, их metadata, ICU plural/select и смысл сообщения. Для русских числительных учитывай one/few/many/other; проверяй 0, 1, 2, 5, 11 и 21 там, где меняется форма счёта.
- [ ] Подключи строку через `AppLocalizations.of(context)`; не зашивай перевод в widget. При изменении подписи настройки сверяй её поиск по [moru-setting](../moru-setting/SKILL.md).
- [ ] Для изменений русского каталога используй существующую проверку `python3 tool/check_moru_ru.py` из корня, если она разрешена заданием; [валидатор](../../../tool/check_moru_ru.py) проверяет ключи, placeholders и технические исключения.
- [ ] После изменения ARB выполни `flutter gen-l10n`, если запуск Flutter разрешён. Если запрещён, укажи, что генерация и её проверки остаются невыполненными; не редактируй generated-файлы вручную.
- [ ] После генерации проверь корневой `desiredFileName.txt`: это JSON-отчёт из `l10n.yaml`, он игнорируется [`.gitignore`](../../../.gitignore) и не tracked. Проверяй новые untranslated относительно базы PR, а не требуй очистить весь прежний список.
- [ ] Включи изменённые generated outputs в набор для коммита вместе с ARB: [app_localizations.dart](../../../lib/l10n/app_localizations.dart), [app_localizations_en.dart](../../../lib/l10n/app_localizations_en.dart), [app_localizations_ru.dart](../../../lib/l10n/app_localizations_ru.dart), [app_localizations_zh.dart](../../../lib/l10n/app_localizations_zh.dart). Коммит выполняй только в разрешённых заданием границах; `desiredFileName.txt` в него не входит.
- [ ] Сверь CI: [`pr-check.yml`](../../../.github/workflows/pr-check.yml) запускает `flutter gen-l10n` и `git diff --exit-code -- lib/l10n`, затем сравнивает untranslated базы и PR. Команда сравнения и целевые тесты — в [references.md](references.md).
- [ ] Проверь сообщение в его UI-контексте: длина, переносы, вставленные значения и смена локали. Выполни разрешённые целевые проверки; в результате отдельно назови проверенные языки, генерацию и untranslated.

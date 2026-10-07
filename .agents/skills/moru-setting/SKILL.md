---
name: moru-setting
description: Use when adding or changing a persisted user-facing setting in Moru.
---

# Пользовательская настройка

Инструкции пользователя имеют приоритет над этим скилом; соблюдай заданные границы правки и проверок.
Общие требования: [Moru product scope](../../../AGENTS.md#moru-product-scope--read-first), [Architecture](../../../AGENTS.md#architecture), [UI guidelines](../../../AGENTS.md#ui-guidelines).

- [ ] Найди ближайшую аналогичную настройку в [SettingsProvider](../../../lib/core/providers/settings_provider.dart) и её реальный экран; меняй существующий путь.
- [ ] Свяжи постоянный ключ, начальное поле/default, getter, `_load()` и setter. Учитывай валидацию, запись, `notifyListeners()` и применение к сервису; дождись `loaded` перед проверкой загрузки.
- [ ] Выбери хранилище по существующей классификации: [BusinessPreferences](../../../lib/core/database/business_preferences.dart) для бизнес-настроек, `SharedPreferences` для `localOnly`-ключей. Сверь [BusinessKeyRegistry](../../../lib/core/database/business_settings_router.dart) и [BackupPortability](../../../lib/core/database/backup_portability.dart): device-bound ключ может оставаться в SQLite, но исключаться из backup.
- [ ] Новый default применяется при отсутствующем ключе. Сохранённые значения, включая явный `false`, оставь как выбрал пользователь; не добавляй миграцию явных настроек без такого задания.
- [ ] Проверь backup через `DataSync.exportBusinessSettingsFrom()` в [data_sync.dart](../../../lib/core/services/backup/data_sync.dart) и [BackupSettingsValidator](../../../lib/core/services/backup/backup_settings_validator.dart). Обычные preference-ключи экспортируются общим snapshot, включая неизвестные; отдельный реестр экспорта не нужен. Локальные, discarded и device-bound ключи фильтруются.
- [ ] Добавь новое состояние в `SettingsProvider.copyWith()`, если оно должно сохраняться в копии. Для визуальной настройки обнови соответствующее превью и проверь совпадение с реальным результатом: [message_style_preview.dart](../../../lib/features/settings/pages/message_style_preview.dart), [BackgroundStatusPreview](../../../lib/features/settings/widgets/background_status_preview.dart).
- [ ] Для доступной из UI настройки проверь [SettingsSearchIndex](../../../lib/features/settings/search/settings_search_index.dart): стабильный id, локализованные title/targetLabel, destination и доступность. Сверь открытие пункта в [settings_search_page.dart](../../../lib/features/settings/pages/settings_search_page.dart).
- [ ] Для новых подписей используй [moru-l10n](../moru-l10n/SKILL.md). Общие компоненты и адаптацию экрана выбирай по [moru-ui](../moru-ui/SKILL.md), если задача меняет UI.
- [ ] При изменении сохранения проверь целевым тестом: default без ключа, setter → новый provider → `loaded`, сохранённые `true`/`false`, `copyWith()`. Если меняется переносимость, проверь export/restore. Готовые опоры и сценарии — в [references.md](references.md).
- [ ] Выполни разрешённые заданием проверки из [Pre-commit checklist](../../../AGENTS.md#pre-commit-checklist); не расширяй их вопреки инструкции пользователя. В результате назови default, сохранение, backup, поиск и превью, которые проверены.

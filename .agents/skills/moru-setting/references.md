# Опоры для изменения настройки

## Хранение и переносимость

- [SettingsProvider](../../../lib/core/providers/settings_provider.dart): конструктор принимает `BusinessPreferences`; `loaded` ждёт `_load()`. `setSpendLimits()` сохраняет `spend_limits_v1`, затем обновляет состояние и уведомляет подписчиков; поле также переносится в `copyWith()`.
- `setRequestLogEnabled()` и `setContextLogEnabled()` в том же файле используют бизнес-хранилище; `setFlutterLogEnabled()` использует локальный `SharedPreferences`. Наличие настройки в одном provider не означает одинаковую переносимость.
- [BusinessSettingsRouter / BusinessKeyRegistry](../../../lib/core/database/business_settings_router.dart): `classify()` различает `localOnly`, `discarded`, `preference` и `unknownPreference`; `exportSnapshot()` включает весь `snapshot.preferences`. Новому обычному ключу не требуется отдельная запись в экспортном allowlist.
- [BackupPortability](../../../lib/core/database/backup_portability.dart) исключает `devicePreferenceKeys`; [BackupSettingsValidator.shouldIgnore()](../../../lib/core/services/backup/backup_settings_validator.dart) фильтрует локальные/discarded/device-bound ключи. `DataSync.exportBusinessSettingsFrom()` применяет оба механизма.

## Проверки по изменённому контракту

- [settings_provider_spend_limits_test.dart](../../../test/settings_provider_spend_limits_test.dart): default-off, setter, повторная загрузка нового provider, `copyWith()`; [business_test_harness.dart](../../../test/support/business_test_harness.dart) даёт SQLite и отдельные `initial`/`localInitial`.
- [settings_provider_logging_test.dart](../../../test/settings_provider_logging_test.dart): отсутствие ключа и сохранённые `true`/`false`, применение к логгерам без миграции выбора.
- [data_sync_business_database_test.dart](../../../test/core/services/backup/data_sync_business_database_test.dart): общая упаковка/восстановление бизнес-данных, неизвестный portable key; Flutter-log и transient restore ключи исключены.
- [settings_search_index_test.dart](../../../test/features/settings/search/settings_search_index_test.dart): уникальные id, путь, переведённый destination/targetLabel и доступность.
- [background_status_preview_test.dart](../../../test/features/settings/widgets/background_status_preview_test.dart) и [display_settings_page_test.dart](../../../test/features/settings/pages/display_settings_page_test.dart): опоры для соответствующего UI. Выбирай тест по реальному поведению изменённой настройки.

## Проверенные PR

- [PR #94](https://github.com/mishaqp/Moru/pull/94): переключатели журналов, default-off только для несохранённого выбора; provider, экран, поиск и тест сохранённых значений.
- [PR #98](https://github.com/mishaqp/Moru/pull/98): необязательные лимиты в `SettingsProvider`, форма в Статистике и проверка сохранения/повторной загрузки.

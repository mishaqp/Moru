# Аудит настроек Moru для v2

Срез кода: `af795269974fb38aa474ffd6afec537885ab17cb`, ветка `claude/moru-v0-1-16-audit-s69yji`. Это инвентарь и предложение информационной архитектуры; код и сохранённые значения не изменяются. Точные русские подписи взяты из `lib/l10n/app_ru.arb`, идентификаторы помогают сверять другие локали. Пути в столбце «Стало» — предложение, не уже реализованные маршруты.

Область: все **44 файла** `lib/features/settings/pages`, пользовательские и внутренние ключи `SettingsProvider`, корневые настройки связанных features, полный реестр **119 файлов pages в 19 features**. Вспомогательные `part of`, табы и layouts перечислены, но не считаются самостоятельными экранами. Повторяющиеся действия редакторов (сохранить, отменить, удалить, сбросить, тест, импорт/экспорт, reorder) сгруппированы явно; сами параметры перечислены отдельно.

Moru — Android arm64. `AGENTS.md:3-26` сохраняет PRoot, terminal/PTY, STDIO MCP и wide Android layouts. `desktop` в имени файла не доказывает мёртвый код: `HomeDesktopScaffold` используется на широком Android. Реальные nonmobile ветки и prefs отдельно отмечены ниже.

## Восемь разделов

| Раздел | Первый уровень | Глубже, для редких параметров |
|---|---|---|
| Внешний вид | Цветовой режим, тема, стиль сообщений, шрифты, Код и Markdown | Стекло, палитры, формулы, детальная геометрия |
| Модели и подключения | Подключения, модели по умолчанию | Ключи, подписки/OAuth, группы, баланс, custom request, proxy, Поисковые сервисы, MCP |
| Чаты и ответы | Отправка, ответы, заголовки, подсказки | Контекст, регенерация, видимость сообщений/карточки, быстрые фразы, автоповтор запросов |
| Ассистенты и агенты | Ассистенты, ACP агенты | Промпты, локальные инструменты, навыки, книга мира, health |
| Рабочая область и инструменты | Рабочие области, Linux-среда, браузер, расписания, мои приложения | Mounts, PRoot args/env/mirrors, schemas/approval, web host |
| Голос | Озвучивание и распознавание, выбранный сервис | Сетевой TTS/ASR editor, голос/формат/модель, playback policy |
| Данные и память | Память, профиль, резервные копии, хранилище, статистика | Legacy migration, prompts, trace, cleanup, WebDAV/S3, retention |
| Приложение | Язык, вибро, фон и уведомления, о приложении | Android permissions, channels/battery/autostart, диагностика/логи |

## Полная корневая карта: 26 из 26 строк

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Управление телефоном · `phoneControlTitle` | `navigation` | [settings_page.dart:179](../../../lib/features/settings/pages/settings_page.dart#L179) | Рабочая область и инструменты → Управление телефоном |
| Цветовой режим · `settingsPageColorMode` | `DisplaySettingsPage` | [settings_page.dart:187](../../../lib/features/settings/pages/settings_page.dart#L187) | Внешний вид → Режим |
| Внешний вид и поведение · `settingsPageDisplay` | `DisplaySettingsPage` | [settings_page.dart:195](../../../lib/features/settings/pages/settings_page.dart#L195) | Внешний вид; поведение → Чаты и ответы; язык/вибро/фон → Приложение |
| Ассистент · `settingsPageAssistant` | `AssistantSettingsPage` | [settings_page.dart:208](../../../lib/features/settings/pages/settings_page.dart#L208) | Ассистенты и агенты → Ассистенты |
| Модель по умолчанию · `settingsPageDefaultModel` | `DefaultModelPage` | [settings_page.dart:227](../../../lib/features/settings/pages/settings_page.dart#L227) | Модели и подключения → Модели по умолчанию |
| Провайдеры · `settingsPageProviders` | `ProvidersPage` | [settings_page.dart:238](../../../lib/features/settings/pages/settings_page.dart#L238) | Модели и подключения → Подключения |
| Поиск · `settingsPageSearch` | `SearchServicesPage` | [settings_page.dart:249](../../../lib/features/settings/pages/settings_page.dart#L249) | Модели и подключения → Дополнительно → Поисковые сервисы |
| Синтез речи · `settingsPageTts` | `TtsServicesPage` | [settings_page.dart:262](../../../lib/features/settings/pages/settings_page.dart#L262) | Голос → Сервисы TTS и ASR |
| MCP · `settingsPageMcp` | `McpPage` | [settings_page.dart:273](../../../lib/features/settings/pages/settings_page.dart#L273) | Модели и подключения → Дополнительно → MCP |
| Агенты · `agentsTitle` | `AgentsPage` | [settings_page.dart:285](../../../lib/features/settings/pages/settings_page.dart#L285) | Ассистенты и агенты → Агенты |
| Браузер · `settingsPageBrowser` | `BrowserSettingsPage` | [settings_page.dart:296](../../../lib/features/settings/pages/settings_page.dart#L296) | Рабочая область и инструменты → Браузер |
| Рабочее пространство и среда · `settingsPageWorkspace` | `WorkspaceSettingsPage` | [settings_page.dart:310](../../../lib/features/settings/pages/settings_page.dart#L310) | Рабочая область и инструменты → Рабочие области и Linux |
| Задачи по расписанию · `scheduledTasksTitle` | `ScheduledTasksPage` | [settings_page.dart:324](../../../lib/features/settings/pages/settings_page.dart#L324) | Рабочая область и инструменты → Задачи по расписанию |
| Мои приложения · `miniAppsTitle` | `MiniAppsPage` | [settings_page.dart:337](../../../lib/features/settings/pages/settings_page.dart#L337) | Рабочая область и инструменты → Мои приложения; тот же каталог в нижней навигации |
| Веб-сервер · `miniAppsWebTitle` | `MiniAppWebPage` | [settings_page.dart:346](../../../lib/features/settings/pages/settings_page.dart#L346) | Рабочая область и инструменты → Мои приложения → Веб-сервер |
| Навыки · `settingsPageSkills` | `SkillsPage` | [settings_page.dart:356](../../../lib/features/settings/pages/settings_page.dart#L356) | Ассистенты и агенты → Навыки |
| Книга мира · `settingsPageWorldBook` | `WorldBookPage` | [settings_page.dart:367](../../../lib/features/settings/pages/settings_page.dart#L367) | Ассистенты и агенты → Книга мира |
| Память · `settingsPageMemory` | `MemorySettingsPage` | [settings_page.dart:378](../../../lib/features/settings/pages/settings_page.dart#L378) | Данные и память → Память |
| Быстрая фраза · `settingsPageQuickPhrase` | `QuickPhrasesPage` | [settings_page.dart:391](../../../lib/features/settings/pages/settings_page.dart#L391) | Чаты и ответы → Быстрые фразы |
| Добавление инструкций · `settingsPageInstructionInjection` | `InstructionInjectionPage` | [settings_page.dart:402](../../../lib/features/settings/pages/settings_page.dart#L402) | Ассистенты и агенты → Добавление инструкций |
| Сетевой прокси · `settingsPageNetworkProxy` | `NetworkProxyPage` | [settings_page.dart:415](../../../lib/features/settings/pages/settings_page.dart#L415) | Модели и подключения → Дополнительно → Сетевой прокси |
| Резервное копирование · `settingsPageBackup` | `BackupPage` | [settings_page.dart:432](../../../lib/features/settings/pages/settings_page.dart#L432) | Данные и память → Резервные копии |
| Хранилище чатов · `settingsPageChatStorage` | `StorageSpacePage` | [settings_page.dart:443](../../../lib/features/settings/pages/settings_page.dart#L443) | Данные и память → Хранилище |
| Статистика · `settingsPageStatistics` | `StatsPage` | [settings_page.dart:460](../../../lib/features/settings/pages/settings_page.dart#L460) | Данные и память → Статистика |
| Журналы · `settingsPageLogs` | `LogViewerPage` | [settings_page.dart:474](../../../lib/features/settings/pages/settings_page.dart#L474) | Приложение → Диагностика → Журналы |
| Инструменты и разрешения · `toolSchemaSettingsPageTitle` | `ToolSchemaSettingsPage` | [settings_page.dart:486](../../../lib/features/settings/pages/settings_page.dart#L486) | Рабочая область и инструменты → Инструменты и разрешения |

Условия видимости: управление телефоном и агенты/расписания/mini apps показываются на Android (`settings_page.dart:174,280,320,333`), браузер — при `BrowserAgentTool.supported` (`:291`), журналы — при хотя бы одном `requestLogEnabled / flutterLogEnabled / contextLogEnabled` (`:467`). Эти условия — не отдельные переключатели. Корень сейчас имеет «Общие», «Модели и сервисы», «Данные» и безымянную нижнюю карточку (`:172,221,426,455`).

## Фон и уведомления: текущие Android параметры и системные действия

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Фоновая генерация · `backgroundAndroidEnabled` | `mobileBackground.androidEnabled` | [mobile_background_settings_page.dart:135](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L135) | Приложение → Фон и уведомления |
| Уведомления задач · `backgroundNotifications` | `mobileBackground.notificationsEnabled` | [mobile_background_settings_page.dart:143](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L143) | Приложение → Фон и уведомления |
| Конфиденциальность статуса задач · `backgroundPrivacy` | `mobileBackground.privacyMode` | [mobile_background_settings_page.dart:156](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L156) | Приложение → Фон и уведомления |
| Плавающий статус задач · `backgroundOverlay` | `mobileBackground.overlayEnabled` | [mobile_background_settings_page.dart:169](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L169) | Приложение → Фон и уведомления |
| Обновляемые уведомления · `backgroundLiveUpdates` | `mobileBackground.liveUpdatesEnabled` | [mobile_background_settings_page.dart:182](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L182) | Приложение → Фон и уведомления |
| Длительность показа завершённого статуса · `backgroundFinishVisibility` | `mobileBackground.completionVisibility` | [mobile_background_settings_page.dart:192](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L192) | Приложение → Фон и уведомления |
| Внешний вид плавающего окна · `backgroundOverlayAppearance` | `BackgroundOverlaySettingsPage` | [mobile_background_settings_page.dart:228](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L228) | Приложение → Фон и уведомления → Внешний вид плавающего окна |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Разрешение на уведомления · `backgroundNotificationsPermission` | `permission notifications` | [mobile_background_settings_page.dart:245](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L245) | Приложение → Фон и уведомления → Разрешения Android |
| Канал уведомлений о завершении · `backgroundCompletionChannel` | `open channels` | [mobile_background_settings_page.dart:251](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L251) | Приложение → Фон и уведомления → Разрешения Android |
| Канал уведомлений о текущих задачах · `backgroundOngoingChannel` | `open ongoingChannel` | [mobile_background_settings_page.dart:257](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L257) | Приложение → Фон и уведомления → Разрешения Android |
| Оптимизация батареи · `backgroundBatteryOptimization` | `open battery` | [mobile_background_settings_page.dart:263](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L263) | Приложение → Фон и уведомления → Разрешения Android |
| Ожидание с низким энергопотреблением · `backgroundLowPowerStandby` | `open power` | [mobile_background_settings_page.dart:270](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L270) | Приложение → Фон и уведомления → Разрешения Android |
| Автозапуск и работа в фоне · `backgroundAutostart` | `open autostart` | [mobile_background_settings_page.dart:278](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L278) | Приложение → Фон и уведомления → Разрешения Android |

Отдельная строка «Системные настройки приложения» (`backgroundSystemSettings`) открывает настройки приложения через `_open('app')` ([mobile_background_settings_page.dart:296](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L296)) → «Приложение → Фон и уведомления → Разрешения Android». Также отдельные системные действия Overlay и Live Updates (`:284-295`) ведут в Android настройки, а не меняют preference. Выбор завершения: immediately / oneMinute / fiveMinutes / untilForeground (`:95-104`); status/active tasks/foreground service/overlay/live update/last error — только диагностика (`:302-319`). Appearance окна полностью перечислен вместе с display controls ниже.

## Сеть, повтор запросов, браузер, схемы и управление телефоном

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Включить прокси · `networkProxyEnableLabel` | `globalProxyEnabled` | [network_proxy_page.dart:122](../../../lib/features/settings/pages/network_proxy_page.dart#L122) | Модели и подключения → Дополнительно → Сетевой прокси |
| Тип прокси · `networkProxyType` | `globalProxyType (http/https/socks5)` | [network_proxy_page.dart:143](../../../lib/features/settings/pages/network_proxy_page.dart#L143) | Модели и подключения → Дополнительно → Сетевой прокси |
| Сервер · `networkProxyServerHost` | `globalProxyHost` | [network_proxy_page.dart:157](../../../lib/features/settings/pages/network_proxy_page.dart#L157) | Модели и подключения → Дополнительно → Сетевой прокси |
| Порт · `networkProxyPort` | `globalProxyPort` | [network_proxy_page.dart:168](../../../lib/features/settings/pages/network_proxy_page.dart#L168) | Модели и подключения → Дополнительно → Сетевой прокси |
| Имя пользователя · `networkProxyUsername` | `globalProxyUsername` | [network_proxy_page.dart:180](../../../lib/features/settings/pages/network_proxy_page.dart#L180) | Модели и подключения → Дополнительно → Сетевой прокси |
| Пароль · `networkProxyPassword` | `globalProxyPassword` | [network_proxy_page.dart:191](../../../lib/features/settings/pages/network_proxy_page.dart#L191) | Модели и подключения → Дополнительно → Сетевой прокси |
| Исключения прокси · `networkProxyBypassLabel` | `globalProxyBypass` | [network_proxy_page.dart:203](../../../lib/features/settings/pages/network_proxy_page.dart#L203) | Модели и подключения → Дополнительно → Сетевой прокси |
| URL для проверки · `networkProxyTestUrlHint` | `_testUrlCtl — временный URL теста` | [network_proxy_page.dart:246](../../../lib/features/settings/pages/network_proxy_page.dart#L246) | Модели и подключения → Дополнительно → Сетевой прокси |
| Проверить · `networkProxyTestButton` | `_test — операция` | [network_proxy_page.dart:256](../../../lib/features/settings/pages/network_proxy_page.dart#L256) | Модели и подключения → Дополнительно → Сетевой прокси |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Включить автоповтор · `autoRetryEnableLabel` | `autoRetryOptions.enabled` | [auto_retry_page.dart:162](../../../lib/features/settings/pages/auto_retry_page.dart#L162) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Максимум повторов · `autoRetryMaxRetries` | `autoRetryOptions.maxRetries` | [auto_retry_page.dart:178](../../../lib/features/settings/pages/auto_retry_page.dart#L178) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Начальная задержка (мс) · `autoRetryInitialDelay` | `autoRetryOptions.initialDelayMs` | [auto_retry_page.dart:193](../../../lib/features/settings/pages/auto_retry_page.dart#L193) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Множитель задержки · `autoRetryMultiplier` | `autoRetryOptions.multiplier` | [auto_retry_page.dart:208](../../../lib/features/settings/pages/auto_retry_page.dart#L208) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Максимальная задержка (мс) · `autoRetryMaxDelay` | `autoRetryOptions.maxDelayMs` | [auto_retry_page.dart:224](../../../lib/features/settings/pages/auto_retry_page.dart#L224) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Случайный разброс · `autoRetryJitter` | `autoRetryOptions.jitter` | [auto_retry_page.dart:239](../../../lib/features/settings/pages/auto_retry_page.dart#L239) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Повторять при сетевых ошибках · `autoRetryOnNetworkError` | `autoRetryOptions.retryOnNetworkError` | [auto_retry_page.dart:246](../../../lib/features/settings/pages/auto_retry_page.dart#L246) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Коды состояния для повтора · `autoRetryStatusCodes` | `autoRetryOptions.retryStatusCodes` | [auto_retry_page.dart:256](../../../lib/features/settings/pages/auto_retry_page.dart#L256) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Ключевые слова для повтора · `autoRetryKeywords` | `autoRetryOptions.retryKeywords` | [auto_retry_page.dart:285](../../../lib/features/settings/pages/auto_retry_page.dart#L285) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| Ключевые слова для остановки · `autoRetryStopKeywords` | `autoRetryOptions.stopKeywords` | [auto_retry_page.dart:317](../../../lib/features/settings/pages/auto_retry_page.dart#L317) | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |

Для списков retry есть добавить/удалить chip; restore defaults у keywords/stop keywords (`auto_retry_page.dart:254-344,460`). Пункт переносится из Display в «Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов»; правила ошибок сохраняются без изменения данных.
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Я понимаю риск — разрешать всё · `toolApprovalsFullTrustTitle` | `toolAutoApproveAll` | [tool_schema_settings_page.dart:128](../../../lib/features/settings/pages/tool_schema_settings_page.dart#L128) | Рабочая область и инструменты → Инструменты и разрешения |
| Восстановить все исходные значения · `toolSchemaSettingsResetAll` | `resetAllToolSchemaOverrides` | [tool_schema_settings_page.dart:69](../../../lib/features/settings/pages/tool_schema_settings_page.dart#L69) | Рабочая область и инструменты → Инструменты и разрешения → Описания инструментов |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Описание · `toolSchemaSettingsDescriptionLabel` | `toolSchemaOverrides[tool].description` | [tool_schema_editor_form.dart:155](../../../lib/features/settings/widgets/tool_schema_editor_form.dart#L155) | Рабочая область и инструменты → Инструменты и разрешения → Описания инструментов → Инструмент |
| Описания параметров ({count}) · `toolSchemaSettingsParamDescriptions` | `toolSchemaOverrides[tool].paramDescriptions[param]` | [tool_schema_editor_form.dart:178](../../../lib/features/settings/widgets/tool_schema_editor_form.dart#L178) | Рабочая область и инструменты → Инструменты и разрешения → Описания инструментов → Инструмент |
| Восстановить исходное · `toolSchemaSettingsResetDefault` | `restore defaults — операция` | [tool_schema_editor_form.dart:215](../../../lib/features/settings/widgets/tool_schema_editor_form.dart#L215) | Рабочая область и инструменты → Инструменты и разрешения → Описания инструментов → Инструмент |

Все строки каталога генерируются из `BuiltInToolCatalog.entries` (`tool_schema_settings_page.dart:87-93,198-202`; `lib/core/services/tools/built_in_tool_catalog.dart:34`), группы search / memory / local / workspace (`:165-169`). Это параметризованный редактор для каждого существующего инструмента, а не четыре отдельных preferences. Save/back редактора (`tool_schema_editor_page.dart:49-81`) сохраняются.

### 15 существующих переключателей действий браузера

`BrowserSettingsPage` показывает trust banner только как статус (`:96-100`); переключатель доверия находится в `ToolSchemaSettingsPage:128-146`. Каждая строка ниже вызывает `setBrowserActionEnabled(id,value)` и меняет `disabledBrowserActions` (`browser_settings_page.dart:256-288`).

| Было: action id / группа | Код группы | Стало |
|---|---|---|
| `open` · Навигация | [browser_settings_page.dart:31](../../../lib/features/settings/pages/browser_settings_page.dart#L31) | Рабочая область и инструменты → Браузер → Доступные действия → Навигация |
| `back` · Навигация | [browser_settings_page.dart:31](../../../lib/features/settings/pages/browser_settings_page.dart#L31) | Рабочая область и инструменты → Браузер → Доступные действия → Навигация |
| `forward` · Навигация | [browser_settings_page.dart:31](../../../lib/features/settings/pages/browser_settings_page.dart#L31) | Рабочая область и инструменты → Браузер → Доступные действия → Навигация |
| `reload` · Навигация | [browser_settings_page.dart:31](../../../lib/features/settings/pages/browser_settings_page.dart#L31) | Рабочая область и инструменты → Браузер → Доступные действия → Навигация |
| `scroll` · Навигация | [browser_settings_page.dart:31](../../../lib/features/settings/pages/browser_settings_page.dart#L31) | Рабочая область и инструменты → Браузер → Доступные действия → Навигация |
| `observe` · Чтение | [browser_settings_page.dart:36](../../../lib/features/settings/pages/browser_settings_page.dart#L36) | Рабочая область и инструменты → Браузер → Доступные действия → Чтение |
| `read` · Чтение | [browser_settings_page.dart:36](../../../lib/features/settings/pages/browser_settings_page.dart#L36) | Рабочая область и инструменты → Браузер → Доступные действия → Чтение |
| `wait_for` · Чтение | [browser_settings_page.dart:36](../../../lib/features/settings/pages/browser_settings_page.dart#L36) | Рабочая область и инструменты → Браузер → Доступные действия → Чтение |
| `click` · Взаимодействие | [browser_settings_page.dart:41](../../../lib/features/settings/pages/browser_settings_page.dart#L41) | Рабочая область и инструменты → Браузер → Доступные действия → Взаимодействие |
| `type` · Взаимодействие | [browser_settings_page.dart:41](../../../lib/features/settings/pages/browser_settings_page.dart#L41) | Рабочая область и инструменты → Браузер → Доступные действия → Взаимодействие |
| `submit` · Взаимодействие | [browser_settings_page.dart:41](../../../lib/features/settings/pages/browser_settings_page.dart#L41) | Рабочая область и инструменты → Браузер → Доступные действия → Взаимодействие |
| `press_key` · Взаимодействие | [browser_settings_page.dart:41](../../../lib/features/settings/pages/browser_settings_page.dart#L41) | Рабочая область и инструменты → Браузер → Доступные действия → Взаимодействие |
| `eval_js` · Дополнительно | [browser_settings_page.dart:46](../../../lib/features/settings/pages/browser_settings_page.dart#L46) | Рабочая область и инструменты → Браузер → Доступные действия → Дополнительно |
| `done` · Дополнительно | [browser_settings_page.dart:46](../../../lib/features/settings/pages/browser_settings_page.dart#L46) | Рабочая область и инструменты → Браузер → Доступные действия → Дополнительно |
| `close` · Дополнительно | [browser_settings_page.dart:46](../../../lib/features/settings/pages/browser_settings_page.dart#L46) | Рабочая область и инструменты → Браузер → Доступные действия → Дополнительно |

**Пробел текущего покрытия:** каталог `lib/features/home/services/browser_agent_actions.dart:31-245` содержит 27 действий. `screenshot / collect / outline / wait_stable / tabs / new_tab / switch_tab / close_tab / set_mode / hover / fetch / export_cookies` отсутствуют в этих 15 UI toggles; нельзя выдавать их за уже существующие пункты. В новом редакторе можно вывести реальный каталог, если это отдельно войдёт в реализацию.
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Служба специальных возможностей · `phoneControlAccessibilityService` | `native availability/status` | [phone_control_settings_page.dart:172](../../../lib/features/settings/pages/phone_control_settings_page.dart#L172) | Рабочая область и инструменты → Управление телефоном |
| Открыть настройки специальных возможностей · `phoneControlOpenSettings` | `Android accessibility settings — операция` | [phone_control_settings_page.dart:187](../../../lib/features/settings/pages/phone_control_settings_page.dart#L187) | Рабочая область и инструменты → Управление телефоном |
| Разрешить этому ассистенту использовать управление телефоном · `phoneControlEnableAssistant` | `requestEnable route → pop(true); условная операция` | [phone_control_settings_page.dart:221](../../../lib/features/settings/pages/phone_control_settings_page.dart#L221) | Ассистенты и агенты → Ассистент → Инструменты → Управление телефоном |

## Память: глобальные настройки, содержимое и диагностика

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Использовать старую память · `legacyMemoryModeTitle` | `legacyMemoryMode` | [memory_settings_page.dart:84](../../../lib/features/settings/pages/memory_settings_page.dart#L84) | Данные и память → Память → Дополнительно → Режим памяти |
| Язык промптов · `memorySettingsPromptLangSection` | `memoryPromptLang = auto / zh / en` | [memory_settings_page.dart:98](../../../lib/features/settings/pages/memory_settings_page.dart#L98) | Данные и память → Память → Дополнительно → Язык промптов |
| Модель обработки · `memorySettingsModelTitle` | `memoryModelProvider / memoryModelId` | [memory_settings_page.dart:148](../../../lib/features/settings/pages/memory_settings_page.dart#L148) | Данные и память → Память → Модель |
| Включить рассуждения · `memorySettingsThinkingTitle` | `memoryModelThinkingEnabled` | [memory_settings_page.dart:164](../../../lib/features/settings/pages/memory_settings_page.dart#L164) | Данные и память → Память → Модель → Дополнительно |
| Записей каждого типа в контексте · `memorySettingsInjectionMaxItemsTitle` | `memoryInjectionMaxItems` | [memory_settings_page.dart:181](../../../lib/features/settings/pages/memory_settings_page.dart#L181) | Данные и память → Память → Дополнительно → Внедрение |
| Список записей памяти · `memorySettingsEntriesTitle` | `MemoryEntriesPage` | [memory_settings_page.dart:209](../../../lib/features/settings/pages/memory_settings_page.dart#L209) | Данные и память → Память → Записи |
| Профиль пользователя · `memorySettingsProfileTitle` | `UserProfilePage` | [memory_settings_page.dart:214](../../../lib/features/settings/pages/memory_settings_page.dart#L214) | Данные и память → Профиль пользователя |
| Старые записи (только чтение) · `memorySettingsLegacyTitle` | `LegacyMemoryPage` | [memory_settings_page.dart:128](../../../lib/features/settings/pages/memory_settings_page.dart#L128) | Данные и память → Память → Дополнительно → Старая память |
| Трассировка обработки · `memoryTraceSettingsTitle` | `MemoryTracePage` | [memory_settings_page.dart:224](../../../lib/features/settings/pages/memory_settings_page.dart#L224) | Данные и память → Память → Дополнительно → Трассировка |
| О памяти · `memorySettingsAboutTitle` | `MemoryAboutPage` | [memory_settings_page.dart:235](../../../lib/features/settings/pages/memory_settings_page.dart#L235) | Данные и память → Память → Справка |
| Старые правила памяти · `memorySettingsLegacyPromptTitle` | `legacyMemoryPromptZh / En` | [memory_settings_page.dart:117](../../../lib/features/settings/pages/memory_settings_page.dart#L117) | Данные и память → Память → Дополнительно → Промпты |
| Правила памяти · `memoryPromptEditRulesTitle` | `memoryRulesPromptZh / En` | [memory_settings_page.dart:423](../../../lib/features/settings/pages/memory_settings_page.dart#L423) | Данные и память → Память → Дополнительно → Промпты |
| Отбор для памяти · `memoryPromptEditGateTitle` | `memoryGatePromptZh / En` | [memory_settings_page.dart:428](../../../lib/features/settings/pages/memory_settings_page.dart#L428) | Данные и память → Память → Дополнительно → Промпты |
| Извлечение · `memoryPromptEditExtractTitle` | `memoryExtractPromptZh / En` | [memory_settings_page.dart:433](../../../lib/features/settings/pages/memory_settings_page.dart#L433) | Данные и память → Память → Дополнительно → Промпты |
| Умное добавление · `memoryPromptEditSmartAddTitle` | `memorySmartAddPromptZh / En + memorySmartAddBatchPromptZh / En` | [memory_settings_page.dart:438](../../../lib/features/settings/pages/memory_settings_page.dart#L438) | Данные и память → Память → Дополнительно → Промпты |
| Формирование профиля · `memoryPromptEditDistillTitle` | `memoryProfileDistillPromptZh / En` | [memory_settings_page.dart:443](../../../lib/features/settings/pages/memory_settings_page.dart#L443) | Данные и память → Память → Дополнительно → Промпты |
| Миграция старых данных · `memoryPromptEditMigrateTitle` | `memoryMigratePromptZh / En` | [memory_settings_page.dart:448](../../../lib/features/settings/pages/memory_settings_page.dart#L448) | Данные и память → Память → Дополнительно → Промпты |

Legacy mode переключает состав экрана (`memory_settings_page.dart:110-134,136-241,248`); это режим данных, не nonmobile UI. В новом режиме «Промпты» содержит 6 редакторов; smart-add имеет отдельные per-item и batch поля (`:421-450,667-676`). Reset/save для каждого редактора (`:703-722`) сохраняются. Лимит внедрения имеет 5/10/20/30 и пользовательское число (`:254-283`); usage per-request/today только read-only (`:1151-1173`).
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Записывать трассировки обработки · `memoryTraceToggleTitle` | `memoryTraceEnabled` | [memory_trace_page.dart:72](../../../lib/features/settings/pages/memory_trace_page.dart#L72) | Данные и память → Память → Дополнительно → Трассировка |
| Очистить · `memoryTraceClearAction` | `recorder.clear — операция` | [memory_trace_page.dart:88](../../../lib/features/settings/pages/memory_trace_page.dart#L88) | Данные и память → Память → Дополнительно → Трассировка |

Трассы: открыть запуск, раскрыть шаг/мутацию, prompt/response/parsed, before/after, copy (`memory_trace_page.dart:118,467-488,553-565,669,700`). Записи: scope, assistant, type, status фильтры; поиск; добавить; batch delete (`memory_entries_page.dart:168-289,345-346`). Detail/edit/delete записи находятся в используемых Memory widgets, а не отдельных pages; остаются в «Память → Записи». Legacy: поиск, export all, миграция (`legacy_memory_page.dart:62-76,248`); в миграции model, target global/assistant, content preserve/organize, batch size, run/close (`:601-773`) → «Память → Дополнительно → Старая память». MemoryAbout — семь справочных секций, preferences нет (`memory_about_page.dart:50-74`). UserProfile поля/действия перечислены в display agent inventory ниже, назначение → «Данные и память → Профиль».


### Запись памяти: поля редактора и действия

| Было: точная подпись / ключ | Поле / действие | Код | Стало |
|---|---|---|---|
| Введите содержимое записи · `memoryEntryContentHint` | `MemoryEntry.content; поле без label, с hint` | [memory_ui.dart:1064](../../../lib/features/settings/widgets/memory_ui.dart#L1064) | Данные и память → Память → Записи → Запись |
| Тип · `memoryEntryTypeLabel` | `MemoryEntry.type = identity / workflow / voice / instruction` | [memory_ui.dart:1076](../../../lib/features/settings/widgets/memory_ui.dart#L1076) | Данные и память → Память → Записи → Запись |
| Область · `memoryEntryScopeLabel` | `MemoryEntry.scope = global / assistant` | [memory_ui.dart:1090](../../../lib/features/settings/widgets/memory_ui.dart#L1090) | Данные и память → Память → Записи → Запись |
| Ассистент · `memoryUiAssistantLabel` | `MemoryEntry.assistantId; условный picker` | [memory_ui.dart:1109](../../../lib/features/settings/widgets/memory_ui.dart#L1109) | Данные и память → Память → Записи → Запись |
| В архив · `memoryEntryActionArchive` | `archive — операция` | [memory_ui.dart:1304](../../../lib/features/settings/widgets/memory_ui.dart#L1304) | Данные и память → Память → Записи → Запись |
| Восстановить · `memoryEntryActionRestore` | `restore — операция` | [memory_ui.dart:1310](../../../lib/features/settings/widgets/memory_ui.dart#L1310) | Данные и память → Память → Записи → Запись |
| Удалить · `memoryEntryActionDelete` | `hardDelete — операция` | [memory_ui.dart:1315](../../../lib/features/settings/widgets/memory_ui.dart#L1315) | Данные и память → Память → Записи → Запись |
| Очистить · `memoryOrphanCleanupButton` | `deleteOrphanAssistantMemories — операция` | [memory_ui.dart:1561](../../../lib/features/settings/widgets/memory_ui.dart#L1561) | Данные и память → Память → Записи → Дополнительно |

Редактор глобального экрана разрешает выбирать ассистента (`memory_entries_page.dart:129-134`); поле появляется при assistant scope (`memory_ui.dart:1107-1118`). Архивация/восстановление/удаление доступны через long press и на Android (`:1427-1430`), несмотря на имя DesktopContextMenu. Orphan cleanup показывается через banner (`memory_entries_page.dart:350`) и удаляет память удалённых ассистентов (`memory_ui.dart:1560-1573`).

## Голос: параметры воспроизведения, TTS и ASR

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Автоматически озвучивать ответы ассистента · `ttsSettingsAutoPlayTitle` | `ttsAutoPlayAssistantReplies` | [tts_settings_page.dart:61](../../../lib/features/settings/pages/tts_settings_page.dart#L61) | Голос → Озвучивание → Поведение |
| Повторно использовать готовое аудио · `ttsSettingsCacheReplayTitle` | `TtsProvider.cacheNetworkAudioForReplay` | [tts_settings_page.dart:72](../../../lib/features/settings/pages/tts_settings_page.dart#L72) | Голос → Озвучивание → Поведение |
| Выбор текста · `ttsSettingsTextSelectionSection` | `ttsTextSelectionMode (fullText/quotedOnly/outsideParentheses/italicOnly/nonItalic)` | [tts_settings_page.dart:86](../../../lib/features/settings/pages/tts_settings_page.dart#L86) | Голос → Озвучивание → Поведение |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Движок · `ttsServicesPageEngineLabel` | `TtsProvider.engineId` | [tts_system_config_sheet.dart:55](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L55) | Голос → Озвучивание → Системный TTS |
| Язык · `ttsServicesPageLanguageLabel` | `TtsProvider.languageTag` | [tts_system_config_sheet.dart:80](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L80) | Голос → Озвучивание → Системный TTS |
| Темп речи · `ttsServicesPageSpeechRateLabel` | `TtsProvider.speechRate` | [tts_system_config_sheet.dart:92](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L92) | Голос → Озвучивание → Системный TTS |
| Высота голоса · `ttsServicesPagePitchLabel` | `TtsProvider.pitch` | [tts_system_config_sheet.dart:113](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L113) | Голос → Озвучивание → Системный TTS |

Список TTS: system service select (`tts_services_page.dart:116-123`), выбранный network service (`tts_network_list.dart:107-109`), добавить (`tts_services_page.dart:252-263`), редактор/тест/удалить/reorder (`tts_network_list.dart:16-24,27-36,145-176`), общий playback editor (`tts_services_page.dart:49-61`). Весь network service хранится в `ttsServices`, выбор в `selectedTtsServiceId`; системные engine/language/rate/pitch принадлежат `TtsProvider`, не SettingsProvider.
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Провайдер · `ttsServicesDialogProviderType` | `TtsServiceOptions.kind (NetworkTtsKind)` | [tts_network_editor.dart:258](../../../lib/features/settings/pages/tts_network_editor.dart#L258) | Голос → Озвучивание → Сервис → Подключение |
| Имя · `ttsServicesFieldNameLabel` | `ttsServices[id].name` | [tts_network_editor.dart:276](../../../lib/features/settings/pages/tts_network_editor.dart#L276) | Голос → Озвучивание → Сервис → Подключение |
| API-ключ · `ttsServicesFieldApiKeyLabel` | `ttsServices[id].apiKey` | [tts_network_editor.dart:281](../../../lib/features/settings/pages/tts_network_editor.dart#L281) | Голос → Озвучивание → Сервис → Подключение |
| ID рабочего пространства · `ttsServicesFieldWorkspaceIdLabel` | `ttsServices[id].workspaceId (qwenAudio)` | [tts_network_editor.dart:287](../../../lib/features/settings/pages/tts_network_editor.dart#L287) | Голос → Озвучивание → Сервис → Дополнительно |
| Базовый URL API · `ttsServicesFieldBaseUrlLabel` | `ttsServices[id].baseUrl` | [tts_network_editor.dart:288](../../../lib/features/settings/pages/tts_network_editor.dart#L288) | Голос → Озвучивание → Сервис → Подключение |
| Модель · `ttsServicesFieldModelLabel` | `model / ElevenLabsTtsOptions.modelId` | [tts_network_editor.dart:299](../../../lib/features/settings/pages/tts_network_editor.dart#L299) | Голос → Озвучивание → Сервис → Подключение |
| Образец аудио (data URI WAV/MP3) · `ttsServicesFieldReferenceAudioLabel` | `MimoTtsOptions.voice; reference audio URI/data URI в clone mode` | [tts_network_editor.dart:309](../../../lib/features/settings/pages/tts_network_editor.dart#L309) | Голос → Озвучивание → Сервис → Дополнительно |
| Голос · `ttsServicesFieldVoiceLabel` | `ttsServices[id].voice / voiceName` | [tts_system_config_sheet.dart:457](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L457) | Голос → Озвучивание → Сервис → Подключение |
| ID голоса · `ttsServicesFieldVoiceIdLabel` | `ttsServices[id].voiceId / referenceId` | [tts_system_config_sheet.dart:463](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L463) | Голос → Озвучивание → Сервис → Подключение |
| Выбрать образец аудио · `ttsServicesFieldChooseReferenceAudioButton` | `ttsServices[id].pick audio data URI — операция` | [tts_network_editor.dart:321](../../../lib/features/settings/pages/tts_network_editor.dart#L321) | Голос → Озвучивание → Сервис → Дополнительно |
| Эмоция · `ttsServicesFieldEmotionLabel` | `ttsServices[id].emotion (MiniMax)` | [tts_network_editor.dart:329](../../../lib/features/settings/pages/tts_network_editor.dart#L329) | Голос → Озвучивание → Сервис → Дополнительно |
| Скорость · `ttsServicesFieldSpeedLabel` | `ttsServices[id].speed` | [tts_network_editor.dart:339](../../../lib/features/settings/pages/tts_network_editor.dart#L339) | Голос → Озвучивание → Сервис → Дополнительно |
| Громкость · `ttsServicesFieldVolumeLabel` | `ttsServices[id].volume` | [tts_network_editor.dart:347](../../../lib/features/settings/pages/tts_network_editor.dart#L347) | Голос → Озвучивание → Сервис → Дополнительно |
| Высота голоса · `ttsServicesFieldPitchLabel` | `ttsServices[id].pitch` | [tts_network_editor.dart:355](../../../lib/features/settings/pages/tts_network_editor.dart#L355) | Голос → Озвучивание → Сервис → Дополнительно |
| Приоритетный язык · `ttsServicesFieldLanguageBoostLabel` | `ttsServices[id].languageBoost` | [tts_network_editor.dart:361](../../../lib/features/settings/pages/tts_network_editor.dart#L361) | Голос → Озвучивание → Сервис → Дополнительно |
| Формат аудио · `ttsServicesFieldFormatLabel` | `ttsServices[id].format` | [tts_network_editor.dart:366](../../../lib/features/settings/pages/tts_network_editor.dart#L366) | Голос → Озвучивание → Сервис → Дополнительно |
| Частота дискретизации · `ttsServicesFieldSampleRateLabel` | `ttsServices[id].sampleRate` | [tts_network_editor.dart:373](../../../lib/features/settings/pages/tts_network_editor.dart#L373) | Голос → Озвучивание → Сервис → Дополнительно |
| Битрейт · `ttsServicesFieldBitrateLabel` | `ttsServices[id].bitrate` | [tts_network_editor.dart:382](../../../lib/features/settings/pages/tts_network_editor.dart#L382) | Голос → Озвучивание → Сервис → Дополнительно |
| Каналы · `ttsServicesFieldChannelLabel` | `ttsServices[id].channel` | [tts_network_editor.dart:391](../../../lib/features/settings/pages/tts_network_editor.dart#L391) | Голос → Озвучивание → Сервис → Дополнительно |
| Словарь произношения (по одной записи в строке) · `ttsServicesFieldPronunciationDictionaryLabel` | `ttsServices[id].pronunciationDictionary` | [tts_network_editor.dart:399](../../../lib/features/settings/pages/tts_network_editor.dart#L399) | Голос → Озвучивание → Сервис → Дополнительно |
| Тип языка · `ttsServicesFieldLanguageTypeLabel` | `ttsServices[id].languageType (Qwen)` | [tts_network_editor.dart:406](../../../lib/features/settings/pages/tts_network_editor.dart#L406) | Голос → Озвучивание → Сервис → Дополнительно |
| Язык · `ttsServicesFieldLanguageLabel` | `ttsServices[id].language` | [tts_network_editor.dart:414](../../../lib/features/settings/pages/tts_network_editor.dart#L414) | Голос → Озвучивание → Сервис → Дополнительно |
| Формат вывода · `ttsServicesFieldOutputFormatLabel` | `ElevenLabsTtsOptions.outputFormat / StepTtsOptions.responseFormat` | [tts_network_editor.dart:423](../../../lib/features/settings/pages/tts_network_editor.dart#L423) | Голос → Озвучивание → Сервис → Дополнительно |
| Описание стиля и голоса · `ttsServicesFieldInstructionLabel` | `ttsServices[id].instruction` | [tts_network_editor.dart:430](../../../lib/features/settings/pages/tts_network_editor.dart#L430) | Голос → Озвучивание → Сервис → Дополнительно |
| Потоковый режим · `ttsServicesFieldStreamingLabel` | `ttsServices[id].stream` | [tts_network_editor.dart:435](../../../lib/features/settings/pages/tts_network_editor.dart#L435) | Голос → Озвучивание → Сервис → Дополнительно |
| Оптимизировать предпросмотр текста · `ttsServicesFieldOptimizeTextPreviewLabel` | `ttsServices[id].optimizeTextPreview` | [tts_network_editor.dart:443](../../../lib/features/settings/pages/tts_network_editor.dart#L443) | Голос → Озвучивание → Сервис → Дополнительно |
| Регион · `ttsServicesFieldRegionLabel` | `ttsServices[id].region` | [tts_network_editor.dart:451](../../../lib/features/settings/pages/tts_network_editor.dart#L451) | Голос → Озвучивание → Сервис → Дополнительно |
| Температура · `ttsServicesFieldTemperatureLabel` | `ttsServices[id].temperature` | [tts_network_editor.dart:521](../../../lib/features/settings/pages/tts_network_editor.dart#L521) | Голос → Озвучивание → Сервис → Дополнительно |
| Top P · `ttsServicesFieldTopPLabel` | `ttsServices[id].topP` | [tts_network_editor.dart:528](../../../lib/features/settings/pages/tts_network_editor.dart#L528) | Голос → Озвучивание → Сервис → Дополнительно |
| Задержка · `ttsServicesFieldLatencyLabel` | `ttsServices[id].latency` | [tts_network_editor.dart:553](../../../lib/features/settings/pages/tts_network_editor.dart#L553) | Голос → Озвучивание → Сервис → Дополнительно |

Поля условные для выбранного `NetworkTtsKind`, а не видимы одновременно (`tts_network_editor.dart:285-553`); окончательные payload-классы создаются в `_buildOptions:693`. Дополнительные `_subtitleEnable` и дефолты не объявлены отдельными controls (`:173,758`) — не придумывать переключатель. Voice/voiceId подпись вычисляется в `tts_system_config_sheet.dart:457-479`. Save/add/back сгруппированы (`tts_network_editor.dart:219-241,568-570`).
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Имя · `asrServicesNameLabel` | `asrServices[id].name` | [asr_service_editor.dart:438](../../../lib/features/settings/widgets/asr_service_editor.dart#L438) | Голос → Распознавание → Сервис |
| API-ключ · `asrServicesApiKeyLabel` | `asrServices[id].apiKey` | [asr_service_editor.dart:477](../../../lib/features/settings/widgets/asr_service_editor.dart#L477) | Голос → Распознавание → Сервис |
| Адрес сервера · `asrServicesEndpointLabel` | `OpenAI/DashScope/Volcengine.websocketUrl / MiMo/Step.baseUrl / QwenAudio.workspaceId` | [asr_service_editor.dart:491](../../../lib/features/settings/widgets/asr_service_editor.dart#L491) | Голос → Распознавание → Сервис |
| ID ресурса · `asrServicesResourceIdLabel` | `asrServices[id].resourceId (Volcengine)` | [asr_service_editor.dart:498](../../../lib/features/settings/widgets/asr_service_editor.dart#L498) | Голос → Распознавание → Сервис |
| Модель · `asrServicesModelLabel` | `asrServices[id].model` | [asr_service_editor.dart:505](../../../lib/features/settings/widgets/asr_service_editor.dart#L505) | Голос → Распознавание → Сервис |
| Язык · `asrServicesLanguageLabel` | `asrServices[id].language / localeId` | [asr_service_editor.dart:511](../../../lib/features/settings/widgets/asr_service_editor.dart#L511) | Голос → Распознавание → Сервис |

Табличные подписи общие, а поля payload зависят от типа: `_endpointController` записывается в websocketUrl/baseUrl/workspaceId (`asr_service_editor.dart:319,342,363,377,398,418`); параметры sampleRate/VAD/prompt/etc, которые только сохраняются из initial, не являются controls (`:325-329,348-350`). ASR находится внутри `TtsServicesPage:223` через `AsrServicesSection`, поэтому root «Синтез речи» сейчас скрывает смысл распознавания. Тип сервиса, выбрать/добавить/редактировать/удалить/reorder (`asr_services_section.dart:66-136,147-148`); cloud fields (`asr_service_editor.dart:435-515`), system availability check (`:463-472`), local sherpaOnnx model download/cancel/use/delete + язык (`:444-459`; `asr_editor_widgets.dart:508-528`). Все сохраняются в «Голос → Распознавание». `desktop` branch этих widgets legacy nonmobile; TTS page использует mobile path.

## Хранилище, справочные и диагностические страницы

| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Изображения · `storageSpaceCategoryImages` | `StorageUsageCategoryKey` | [storage_space_page.dart:155](../../../lib/features/settings/pages/storage_space_page.dart#L155) | Данные и память → Хранилище → Изображения |
| Файлы · `storageSpaceCategoryFiles` | `StorageUsageCategoryKey` | [storage_space_page.dart:157](../../../lib/features/settings/pages/storage_space_page.dart#L157) | Данные и память → Хранилище → Файлы |
| История чатов · `storageSpaceCategoryChatData` | `StorageUsageCategoryKey` | [storage_space_page.dart:159](../../../lib/features/settings/pages/storage_space_page.dart#L159) | Данные и память → Хранилище → История чатов |
| История чатов (старая) · `storageSpaceCategoryLegacyChatData` | `StorageUsageCategoryKey` | [storage_space_page.dart:161](../../../lib/features/settings/pages/storage_space_page.dart#L161) | Данные и память → Хранилище → История чатов (старая) |
| Остатки восстановления · `storageSpaceCategoryRestoreTraces` | `StorageUsageCategoryKey` | [storage_space_page.dart:163](../../../lib/features/settings/pages/storage_space_page.dart#L163) | Данные и память → Хранилище → Остатки восстановления |
| Сохранённые старые базы · `storageSpaceCategoryDisplacedDatabases` | `StorageUsageCategoryKey` | [storage_space_page.dart:165](../../../lib/features/settings/pages/storage_space_page.dart#L165) | Данные и память → Хранилище → Сохранённые старые базы |
| Локальные копии · `localSnapshotSectionTitle` | `StorageUsageCategoryKey` | [storage_space_page.dart:167](../../../lib/features/settings/pages/storage_space_page.dart#L167) | Данные и память → Хранилище → Локальные копии |
| Ассистенты · `storageSpaceCategoryAssistantData` | `StorageUsageCategoryKey` | [storage_space_page.dart:169](../../../lib/features/settings/pages/storage_space_page.dart#L169) | Данные и память → Хранилище → Ассистенты |
| Кэш · `storageSpaceCategoryCache` | `StorageUsageCategoryKey` | [storage_space_page.dart:171](../../../lib/features/settings/pages/storage_space_page.dart#L171) | Данные и память → Хранилище → Кэш |
| Журналы · `storageSpaceCategoryLogs` | `StorageUsageCategoryKey` | [storage_space_page.dart:173](../../../lib/features/settings/pages/storage_space_page.dart#L173) | Данные и память → Хранилище → Журналы |
| Другое · `storageSpaceCategoryOther` | `StorageUsageCategoryKey` | [storage_space_page.dart:175](../../../lib/features/settings/pages/storage_space_page.dart#L175) | Данные и память → Хранилище → Другое |
| Файлы рабочего пространства · `storageSpaceCategoryWorkspaceFiles` | `StorageUsageCategoryKey` | [storage_space_page.dart:177](../../../lib/features/settings/pages/storage_space_page.dart#L177) | Данные и память → Хранилище → Файлы рабочего пространства |
| Изолированная среда · `storageSpaceCategorySandboxEnvironment` | `StorageUsageCategoryKey` | [storage_space_page.dart:179](../../../lib/features/settings/pages/storage_space_page.dart#L179) | Данные и память → Хранилище → Изолированная среда |
| Навыки · `storageSpaceCategorySkills` | `StorageUsageCategoryKey` | [storage_space_page.dart:181](../../../lib/features/settings/pages/storage_space_page.dart#L181) | Данные и память → Хранилище → Навыки |
| Файлы диалога · `storageSpaceCategorySessionFiles` | `StorageUsageCategoryKey` | [storage_space_page.dart:183](../../../lib/features/settings/pages/storage_space_page.dart#L183) | Данные и память → Хранилище → Файлы диалога |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Очистить кэш аватаров · `storageSpaceClearAvatarCacheButton` | `cleanup / navigation — операция` | [storage_category_page.dart:592](../../../lib/features/settings/pages/storage_category_page.dart#L592) | Данные и память → Хранилище → Категория |
| Очистить кэш · `storageSpaceClearCacheButton` | `cleanup / navigation — операция` | [storage_category_page.dart:599](../../../lib/features/settings/pages/storage_category_page.dart#L599) | Данные и память → Хранилище → Категория |
| Просмотреть журналы · `storageSpaceViewLogsButton` | `cleanup / navigation — операция` | [storage_category_page.dart:613](../../../lib/features/settings/pages/storage_category_page.dart#L613) | Данные и память → Хранилище → Категория |
| Очистить журналы · `storageSpaceClearLogsButton` | `cleanup / navigation — операция` | [storage_category_page.dart:623](../../../lib/features/settings/pages/storage_category_page.dart#L623) | Данные и память → Хранилище → Категория |
| Очистить старую историю чатов · `storageSpaceClearLegacyChatDataButton` | `cleanup / navigation — операция` | [storage_category_page.dart:633](../../../lib/features/settings/pages/storage_category_page.dart#L633) | Данные и память → Хранилище → Категория |
| Очистить остатки восстановления · `storageSpaceClearRestoreTracesButton` | `cleanup / navigation — операция` | [storage_category_page.dart:641](../../../lib/features/settings/pages/storage_category_page.dart#L641) | Данные и память → Хранилище → Категория |
| Удалить старые базы · `storageSpaceClearDisplacedDatabasesButton` | `cleanup / navigation — операция` | [storage_category_page.dart:649](../../../lib/features/settings/pages/storage_category_page.dart#L649) | Данные и память → Хранилище → Категория |
| Управление копиями · `localSnapshotManageCopies` | `cleanup / navigation — операция` | [storage_category_page.dart:659](../../../lib/features/settings/pages/storage_category_page.dart#L659) | Данные и память → Хранилище → Категория |
| Управление рабочими пространствами · `workspaceEntryManage` | `cleanup / navigation — операция` | [storage_category_page.dart:668](../../../lib/features/settings/pages/storage_category_page.dart#L668) | Данные и память → Хранилище → Категория |
| Окружение · `workspaceEnvTitle` | `cleanup / navigation — операция` | [storage_category_page.dart:675](../../../lib/features/settings/pages/storage_category_page.dart#L675) | Данные и память → Хранилище → Категория |
| Управление навыками · `storageSpaceManageSkills` | `cleanup / navigation — операция` | [storage_category_page.dart:682](../../../lib/features/settings/pages/storage_category_page.dart#L682) | Данные и память → Хранилище → Категория |
| Удалить файлы удалённых диалогов · `storageSessionFilesCleanOrphans` | `cleanup / navigation — операция` | [storage_category_page.dart:689](../../../lib/features/settings/pages/storage_category_page.dart#L689) | Данные и память → Хранилище → Категория |

Дополнительно category detail: refresh (`storage_category_page.dart:457`), clear других/system cache, экспорт старого Hive файла, очистка fonts/local models (`:827-878`; local models здесь — retired leftovers, не новый LLM feature). Upload manager: select all/clear selection/delete, source filter и sort (`storage_upload_manager.dart:246-259,388-413`); экспорт/просмотр вложения и связь с чатами сохраняются в соответствующих категориях. Preferences здесь нет: это операции над данными.
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Сохранять вывод ответа · `logSettingsSaveOutput` | `logSaveOutput` | [log_viewer_page.dart:3022](../../../lib/features/settings/pages/log_viewer_page.dart#L3022) | Приложение → Диагностика → Журналы → Настройки хранения |
| Пропускать большие данные · `logSettingsElidePayloads` | `logElideLargePayloads` | [log_viewer_page.dart:3065](../../../lib/features/settings/pages/log_viewer_page.dart#L3065) | Приложение → Диагностика → Журналы → Настройки хранения |
| Автоудаление · `logSettingsAutoDelete` | `logAutoDeleteDays` | [log_viewer_page.dart:3097](../../../lib/features/settings/pages/log_viewer_page.dart#L3097) | Приложение → Диагностика → Журналы → Настройки хранения |
| Максимальный размер журналов · `logSettingsMaxSize` | `logMaxSizeMB` | [log_viewer_page.dart:3123](../../../lib/features/settings/pages/log_viewer_page.dart#L3123) | Приложение → Диагностика → Журналы → Настройки хранения |
| Было: точный label / l10n key | Ключ / объект | Было: код | Стало: путь |
|---|---|---|---|
| Журнал контекста · `contextLogSettingTitle` | `contextLogEnabled` | [about_page.dart:151](../../../lib/features/settings/pages/about_page.dart#L151) | Приложение → Диагностика → Логирование |
| Журнал запросов · `requestLogSettingTitle` | `requestLogEnabled` | [about_page.dart:222](../../../lib/features/settings/pages/about_page.dart#L222) | Приложение → Диагностика → Логирование |
| Журнал Flutter · `flutterLogSettingTitle` | `flutterLogEnabled` | [about_page.dart:293](../../../lib/features/settings/pages/about_page.dart#L293) | Приложение → Диагностика → Логирование |
| Версия · `aboutPageVersion` | `package info; tap7 → logging sheet` | [about_page.dart:477](../../../lib/features/settings/pages/about_page.dart#L477) | Приложение → О приложении |
| Системная · `aboutPageSystem` | `read-only platform` | [about_page.dart:487](../../../lib/features/settings/pages/about_page.dart#L487) | Приложение → О приложении |
| Сайт · `aboutPageWebsite` | `external URL` | [about_page.dart:496](../../../lib/features/settings/pages/about_page.dart#L496) | Приложение → О приложении |
| GitHub · `aboutPageGithub` | `external URL` | [about_page.dart:508](../../../lib/features/settings/pages/about_page.dart#L508) | Приложение → О приложении |
| Лицензия · `aboutPageLicense` | `external URL` | [about_page.dart:515](../../../lib/features/settings/pages/about_page.dart#L515) | Приложение → О приложении |
| Присоединиться к группе QQ · `aboutPageJoinQQGroup` | `QQ join sheet` | [about_page.dart:524](../../../lib/features/settings/pages/about_page.dart#L524) | Приложение → О приложении |
| Присоединиться к Discord · `aboutPageJoinDiscord` | `external URL` | [about_page.dart:531](../../../lib/features/settings/pages/about_page.dart#L531) | Приложение → О приложении |

About скрывает существующие controls: 7 taps имени → `unlockKelivoSearch` (`about_page.dart:63-82`); 7 taps версии → три log flags (`:87-104,184-190,255-261,326-332`); long press logo → Debug (`:416`). В v2 диагностика должна иметь явный глубокий маршрут. Viewer сохраняет tabs запрос/контекст/Flutter, refresh, открыть файл, export/copy, load more/expand (`log_viewer_page.dart:181-260,512,644,815-820,869,1301`). Debug имеет 4 действия создания тестовых разговоров: oversized / many messages / mixed Markdown / long reasoning (`debug_page.dart:175-214`) → «Приложение → Диагностика → Тестовые данные». Sponsor: Afdian и WeChat (`sponsor_page.dart:103,115`), ссылки открываются внешним приложением; More: заголовок `LLM排行榜`, ссылки `LMArena` / `LiveBench` (`more_page.dart:36-49,92`), не preferences → «Приложение → О приложении → Поддержка/Ссылки». SettingsSearch: transient query/results/deep navigation (`settings_search_page.dart:171`), не отдельный раздел preferences; старые l10n synonyms и target anchors сохранить в индексе.

## Полный инвентарь Display, тем, стиля, шрифтов, изображений и профиля

`SP` = `SettingsProvider`. Все пути страниц ниже относительно `lib/features/settings/pages/`; persist keys — точные business-preference keys.

Во всех проверенных файлах отсутствуют `isDesktop`, `Platform`, `kIsWeb` и отдельные nonmobile layouts. Это текущий Android/mobile UI. `desktopFontFamilySystemDefault` и `desktopFontFamilyMonospaceDefault` — оставшиеся имена **l10n**, используемые в mobile, а не desktop controls. `Ios*` — названия общих Flutter widgets, также используемых на Android.

Предлагаемое распределение: темы/шрифты/стили и рендеринг кода/Markdown/формул → **Внешний вид**; генерация, ввод, изображение, видимость и карточки → **Чаты и ответы**; язык, виброотклик, запуск, боковая навигация и фоновые задачи → **Приложение**; профиль → **Данные и память**; повтор запросов → **Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов**. В этой группе файлов нет самостоятельных пунктов разделов «Ассистенты и агенты», «Рабочая область и инструменты», «Голос».

**DisplaySettingsPage — все входы текущей страницы**

| Источник | Точная подпись · l10n | Действие / состояние | Предложенный путь |
|---|---|---|---|
| [display_settings_page.dart:82](../../../lib/features/settings/pages/display_settings_page.dart#L82) | Настройки темы · `displaySettingsPageThemeSettingsTitle` | `ThemeSettingsPage`; detail `themePaletteId` | Внешний вид / Тема |
| [display_settings_page.dart:92](../../../lib/features/settings/pages/display_settings_page.dart#L92) | Стекло · `glassThemeTitle` | `GlassThemeSettingsPage`; `glassTheme` | Внешний вид / Стекло |
| [display_settings_page.dart:112](../../../lib/features/settings/pages/display_settings_page.dart#L112) | Язык приложения · `displaySettingsPageLanguageTitle` | language sheet; `appLocale`, `isFollowingSystemLocale` | Приложение / Язык |
| [display_settings_page.dart:145](../../../lib/features/settings/pages/display_settings_page.dart#L145) | Отображение сообщений · `displaySettingsPageChatItemDisplayTitle` | `ChatItemDisplaySettingsPage` | Чаты и ответы → Видимость сообщений / Карточки |
| [display_settings_page.dart:156](../../../lib/features/settings/pages/display_settings_page.dart#L156) | Настройки отображения содержимого · `displaySettingsPageRenderingSettingsTitle` | `RenderingSettingsPage` | Внешний вид → Код и Markdown |
| [display_settings_page.dart:167](../../../lib/features/settings/pages/display_settings_page.dart#L167) | Поведение и запуск · `displaySettingsPageBehaviorStartupTitle` | `BehaviorStartupSettingsPage` | Разделить между Чаты и ответы / Поведение и Приложение / Запуск и навигация |
| [display_settings_page.dart:178](../../../lib/features/settings/pages/display_settings_page.dart#L178) | Обработка изображений · `imageSettingsPageTitle` | `ImageSettingsPage` | Чаты и ответы / Изображения |
| [display_settings_page.dart:187](../../../lib/features/settings/pages/display_settings_page.dart#L187) | Стиль сообщений · `messageStyleSettingsPageTitle` | `MessageStyleSettingsPage` | Внешний вид / Стиль сообщений |
| [display_settings_page.dart:198](../../../lib/features/settings/pages/display_settings_page.dart#L198) | Автоповтор запросов · `settingsPageAutoRetry` | `AutoRetryPage` | Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов |
| [display_settings_page.dart:207](../../../lib/features/settings/pages/display_settings_page.dart#L207) | Виброотклик · `displaySettingsPageHapticsSettingsTitle` | `HapticsSettingsPage` | Приложение / Виброотклик |
| [display_settings_page.dart:218](../../../lib/features/settings/pages/display_settings_page.dart#L218) | Фоновые задачи · `backgroundSettingsTitle` | `MobileBackgroundSettingsPage` | Приложение / Фон и уведомления |
| [display_settings_page.dart:229](../../../lib/features/settings/pages/display_settings_page.dart#L229) | Шрифт приложения · `displaySettingsPageAppFontTitle` | app font sheet | Внешний вид / Шрифты |
| [display_settings_page.dart:259](../../../lib/features/settings/pages/display_settings_page.dart#L259) | Шрифт кода · `displaySettingsPageCodeFontTitle` | code font sheet | Внешний вид / Шрифты |
| [display_settings_page.dart:289](../../../lib/features/settings/pages/display_settings_page.dart#L289) | Размер шрифта чата · `displaySettingsPageChatFontSizeTitle` | font scale sheet | Внешний вид / Шрифты |
| [display_settings_page.dart:306](../../../lib/features/settings/pages/display_settings_page.dart#L306) | Задержка возврата автопрокрутки · `displaySettingsPageAutoScrollIdleTitle` | autoscroll sheet | Чаты и ответы / Прокрутка |
| [display_settings_page.dart:335](../../../lib/features/settings/pages/display_settings_page.dart#L335) | Непрозрачность затемнения фона чата · `displaySettingsPageChatBackgroundMaskTitle` | mask slider sheet | Внешний вид / Фон чата |
| [display_settings_page.dart:354](../../../lib/features/settings/pages/display_settings_page.dart#L354) | Непрозрачность фона поля ввода · `displaySettingsPageChatInputBackgroundOpacityTitle` | light + dark opacity sheet | Внешний вид / Поле ввода |

**Display sheets и persist**

| Источник | Подпись · ключ / варианты | SP property / setter | Persist key | Предложенный путь |
|---|---|---|---|---|
| [display_settings_page.dart:398](../../../lib/features/settings/pages/display_settings_page.dart#L398) | Google Fonts · `googleFontsTitle` | `showGoogleFontsPicker(forCode:…)` | через выбранный app/code font | Внешний вид / Шрифты / Выбор |
| [display_settings_page.dart:404](../../../lib/features/settings/pages/display_settings_page.dart#L404) | Выбрать локальный файл · `fontPickerChooseLocalFile` | `setAppFontFromLocal`, `setCodeFontFromLocal`; picker `.ttf/.otf` | `display_app_font_family_v1`, `display_app_font_local_path_v1`, `display_app_font_local_alias_v1`; аналогично `code` | Внешний вид / Шрифты / Выбор |
| [display_settings_page.dart:410](../../../lib/features/settings/pages/display_settings_page.dart#L410) | Сбросить настройки шрифтов · `displaySettingsPageFontResetLabel` | `clearAppFont` или `clearCodeFont`, только выбранная цель | удаляет соответствующие три font keys | Внешний вид / Шрифты / Выбор |
| [display_settings_page.dart:467](../../../lib/features/settings/pages/display_settings_page.dart#L467)/:473/:479/:485/:491 | Системная / Русский / Китайский (упрощённый) / Китайский (традиционный) / Английский · `settingsPageSystemMode`, `moruLanguageRussian`, `displaySettingsPageLanguageChineseLabel`, `languageDisplayTraditionalChinese`, `displaySettingsPageLanguageEnglishLabel` | `setAppLocaleFollowSystem`, `setAppLocale`; tags `system`, `ru`, `zh_CN`, `zh_Hant`, `en_US` | `app_locale_v1` | Приложение / Язык |
| [display_settings_page.dart:588](../../../lib/features/settings/pages/display_settings_page.dart#L588)/:621 | Размер, 50–150%, шаг 5%; label родитель :289 | `chatFontScale` / `setChatFontScale` | `display_chat_font_scale_v1` | Внешний вид / Шрифты |
| [display_settings_page.dart:689](../../../lib/features/settings/pages/display_settings_page.dart#L689) | Автопрокрутка вниз · `displaySettingsPageAutoScrollEnableTitle` | `autoScrollEnabled` / `setAutoScrollEnabled` | `display_auto_scroll_enabled_v1` | Чаты и ответы / Прокрутка |
| [display_settings_page.dart:742](../../../lib/features/settings/pages/display_settings_page.dart#L742)/:776 | Задержка 2–64 с, шаг 2; label родитель :306, hint `displaySettingsPageAutoScrollIdleSubtitle` | `autoScrollIdleSeconds` / `setAutoScrollIdleSeconds` | `display_auto_scroll_idle_seconds_v1` | Чаты и ответы / Прокрутка |
| [display_settings_page.dart:881](../../../lib/features/settings/pages/display_settings_page.dart#L881)/:914 | Затемнение 0–200%, шаг 5%; label родитель :335 | `chatBackgroundMaskStrength` / `setChatBackgroundMaskStrength` | `display_chat_background_mask_strength_v1` | Внешний вид / Фон чата / Дополнительно |
| [display_settings_page.dart:963](../../../lib/features/settings/pages/display_settings_page.dart#L963)/:971/:1046/:1077 | Светлая / Тёмная · `settingsPageLightMode`, `settingsPageDarkMode`; каждая 0–100%, шаг 5% | `chatInputBackgroundOpacityFor(brightness)` / `setChatInputBackgroundOpacity` | `display_chat_input_background_opacity_light_v1`, `display_chat_input_background_opacity_dark_v1` | Внешний вид / Поле ввода / Дополнительно |

Font setters: SP :1872/:1903; clear :1934/:1947; locale :2192/:2201; scale/scroll/mask/opacity :5114/:5126/:5137/:5152/:5181.

**Отображение сообщений — все 13 switches**

| display_chat_item_page.dart | Подпись · ключ | SP property | Persist key |
|---|---|---|---|
| [display_chat_item_page.dart:49](../../../lib/features/settings/pages/display_chat_item_page.dart#L49) | Показывать аватар пользователя · `displaySettingsPageShowUserAvatarTitle` | `showUserAvatar` | `display_show_user_avatar_v1` |
| [display_chat_item_page.dart:58](../../../lib/features/settings/pages/display_chat_item_page.dart#L58) | Показывать имя пользователя · `displaySettingsPageShowUserNameTitle` | `showUserName` | `display_show_user_name_v1` |
| [display_chat_item_page.dart:67](../../../lib/features/settings/pages/display_chat_item_page.dart#L67) | Показывать время сообщений пользователя · `displaySettingsPageShowUserTimestampTitle` | `showUserTimestamp` | `display_show_user_timestamp_v1` |
| [display_chat_item_page.dart:76](../../../lib/features/settings/pages/display_chat_item_page.dart#L76) | Действия под сообщениями пользователя · `displaySettingsPageShowUserMessageActionsTitle` | `showUserMessageActions` | `display_show_user_message_actions_v1` |
| [display_chat_item_page.dart:86](../../../lib/features/settings/pages/display_chat_item_page.dart#L86) | Значок модели в чате · `displaySettingsPageChatModelIconTitle` | `showModelIcon` | `display_show_model_icon_v1` |
| [display_chat_item_page.dart:95](../../../lib/features/settings/pages/display_chat_item_page.dart#L95) | Аватар ассистента в заголовке чата · `displaySettingsPageUseNewAssistantAvatarUxTitle` | `useNewAssistantAvatarUx` | `display_use_new_assistant_avatar_ux_v1` |
| [display_chat_item_page.dart:105](../../../lib/features/settings/pages/display_chat_item_page.dart#L105) | Показывать название модели · `displaySettingsPageShowModelNameTitle` | `showModelName` | `display_show_model_name_v1` |
| [display_chat_item_page.dart:114](../../../lib/features/settings/pages/display_chat_item_page.dart#L114) | Показывать время ответов модели · `displaySettingsPageShowModelTimestampTitle` | `showModelTimestamp` | `display_show_model_timestamp_v1` |
| [display_chat_item_page.dart:123](../../../lib/features/settings/pages/display_chat_item_page.dart#L123) | Провайдер после названия модели · `displaySettingsPageShowProviderInChatMessageTitle` | `showProviderInChatMessage` | `display_show_provider_in_chat_message_v1` |
| [display_chat_item_page.dart:133](../../../lib/features/settings/pages/display_chat_item_page.dart#L133) | Статистика токенов и контекста · `displaySettingsPageShowTokenStatsTitle` | `showTokenStats` | `display_show_token_stats_v1` |
| [display_chat_item_page.dart:142](../../../lib/features/settings/pages/display_chat_item_page.dart#L142) | Показывать карточки рассуждений · `displaySettingsPageShowThinkingCardsTitle` | `showThinkingCards` | `display_show_thinking_cards_v1` |
| [display_chat_item_page.dart:152](../../../lib/features/settings/pages/display_chat_item_page.dart#L152) | Показывать карточки инструментов · `displaySettingsPageShowToolCardsTitle` | `showToolCards` | `display_show_tool_cards_v1` |
| [display_chat_item_page.dart:162](../../../lib/features/settings/pages/display_chat_item_page.dart#L162) | Показывать файлы под ответами · `displaySettingsPageShowProducedFilesTitle` | `showProducedFiles` | `display_show_produced_files_v1` |

Переключатели видимости → **Чаты и ответы → Видимость сообщений**; thinking/tool/produced-files switches → **Чаты и ответы → Карточки**. Редкие timestamp/provider/avatar switches можно собрать в «Видимость сообщений → Дополнительно». Setter соответствует `set<Property>`; SP :4644–4898. Нынешний UI использует отдельные name/time prefs; старые `display_show_model_name_timestamp_v1` и `display_show_user_name_timestamp_v1` здесь не controls.

**Отображение содержимого — все controls**

| display_rendering_page.dart | Подпись · ключ | SP property | Persist key |
|---|---|---|---|
| [display_rendering_page.dart:44](../../../lib/features/settings/pages/display_rendering_page.dart#L44) | Формулы внутри $...$ · `displaySettingsPageEnableDollarLatexTitle` | `enableDollarLatex` | `display_enable_dollar_latex_v1` |
| [display_rendering_page.dart:53](../../../lib/features/settings/pages/display_rendering_page.dart#L53) | Отображение формул · `displaySettingsPageEnableMathTitle` | `enableMathRendering` | `display_enable_math_rendering_v1` |
| [display_rendering_page.dart:62](../../../lib/features/settings/pages/display_rendering_page.dart#L62) | Markdown в сообщениях пользователя · `displaySettingsPageEnableUserMarkdownTitle` | `enableUserMarkdown` | `display_enable_user_markdown_v1` |
| [display_rendering_page.dart:71](../../../lib/features/settings/pages/display_rendering_page.dart#L71) | Markdown в рассуждениях · `displaySettingsPageEnableReasoningMarkdownTitle` | `enableReasoningMarkdown` | `display_enable_reasoning_markdown_v1` |
| [display_rendering_page.dart:81](../../../lib/features/settings/pages/display_rendering_page.dart#L81) | Markdown в сообщениях ассистента · `displaySettingsPageEnableAssistantMarkdownTitle` | `enableAssistantMarkdown` | `display_enable_assistant_markdown_v1` |
| [display_rendering_page.dart:91](../../../lib/features/settings/pages/display_rendering_page.dart#L91) | Автоматически сворачивать блоки кода · `displaySettingsPageAutoCollapseCodeBlockTitle` | `autoCollapseCodeBlock` | `display_auto_collapse_code_block_v1` |
| [display_rendering_page.dart:102](../../../lib/features/settings/pages/display_rendering_page.dart#L102) | Порог автосворачивания · `displaySettingsPageAutoCollapseCodeBlockLinesTitle`; 1–999 строк, появляется при предыдущем switch | `autoCollapseCodeBlockLines` | `display_auto_collapse_code_block_lines_v1` |
| [display_rendering_page.dart:116](../../../lib/features/settings/pages/display_rendering_page.dart#L116) | Перенос строк в блоках кода на телефоне · `displaySettingsPageMobileCodeBlockWrapTitle` | `mobileCodeBlockWrap` | `display_mobile_code_block_wrap_v1` |

Все → **Внешний вид → Код и Markdown**; формулы и Markdown по ролям можно глубже в «Дополнительно». Setter SP :5206–5250/:5385–5407.

**Поведение и запуск — все controls**

| display_behavior_page.dart | Подпись · ключ | SP property | Persist key | Предложенный путь |
|---|---|---|---|---|
| [display_behavior_page.dart:61](../../../lib/features/settings/pages/display_behavior_page.dart#L61) | Автоматически сворачивать рассуждения · `displaySettingsPageAutoCollapseThinkingTitle` | `autoCollapseThinking` | `display_auto_collapse_thinking_v1` | Чаты и ответы / Карточки |
| [display_behavior_page.dart:70](../../../lib/features/settings/pages/display_behavior_page.dart#L70) | Сворачивать этапы рассуждений · `displaySettingsPageCollapseThinkingStepsTitle` | `collapseThinkingSteps` | `display_collapse_thinking_steps_v1` | Чаты и ответы / Карточки / Дополнительно |
| [display_behavior_page.dart:80](../../../lib/features/settings/pages/display_behavior_page.dart#L80) | Показывать сводку результатов инструментов · `displaySettingsPageShowToolResultSummaryTitle` | `showToolResultSummary` | `display_show_tool_result_summary_v1` | Чаты и ответы / Карточки |
| [display_behavior_page.dart:90](../../../lib/features/settings/pages/display_behavior_page.dart#L90) | Скрывать изображения в результатах инструментов · `displaySettingsPageHideToolResultImagesTitle` | `hideToolResultImages` | `display_hide_tool_result_images_v1` | Чаты и ответы / Карточки / Дополнительно |
| [display_behavior_page.dart:99](../../../lib/features/settings/pages/display_behavior_page.dart#L99) | Вставлять подсказки без отправки · `displaySettingsPageInsertSuggestionOnlyTitle` | `insertSuggestionOnTapOnly` | `suggestion_insert_on_tap_only_v1` | Чаты и ответы / Ввод |
| [display_behavior_page.dart:109](../../../lib/features/settings/pages/display_behavior_page.dart#L109) | Сворачивать длинные сообщения · `displaySettingsPageCollapseLongUserMessagesTitle` | `collapseLongUserMessages` | `display_collapse_long_user_messages_v1` | Чаты и ответы / Длинные сообщения |
| [display_behavior_page.dart:120](../../../lib/features/settings/pages/display_behavior_page.dart#L120) | Порог сворачивания · `displaySettingsPageCollapseLongUserMessagesCharsTitle`; 50–100000 симв., условный | `collapseLongUserMessageChars` | `display_collapse_long_user_message_chars_v1` | Чаты и ответы / Длинные сообщения |
| [display_behavior_page.dart:137](../../../lib/features/settings/pages/display_behavior_page.dart#L137) | Удалять сообщения ниже при повторной генерации · `displaySettingsPageRegenerateDeleteTrailingMessagesTitle` | `regenerateDeleteTrailingMessages` | `display_regenerate_delete_trailing_messages_v1` | Чаты и ответы / Повторная генерация |
| [display_behavior_page.dart:147](../../../lib/features/settings/pages/display_behavior_page.dart#L147) | Подтверждать повторную генерацию · `displaySettingsPageShowRegenerateConfirmDialogTitle` | `showRegenerateConfirmDialog` | `display_show_regenerate_confirm_dialog_v1` | Чаты и ответы / Повторная генерация |
| [display_behavior_page.dart:157](../../../lib/features/settings/pages/display_behavior_page.dart#L157) | Сохранять версии сообщений при создании ветки · `displaySettingsPageForkKeepMessageVersionsTitle` | `forkKeepMessageVersions` | `chat_fork_keep_message_versions_v1` | Чаты и ответы / Редактирование и ветки |
| [display_behavior_page.dart:168](../../../lib/features/settings/pages/display_behavior_page.dart#L168) | Сохранять рассуждения и инструменты при редактировании ответа · `displaySettingsPageEditAssistantKeepThinkingToolCardsTitle` | `keepThinkingAndToolCardsWhenEditingAssistant` | `chat_edit_assistant_keep_thinking_tool_cards_v1` | Чаты и ответы / Редактирование и ветки / Дополнительно |
| [display_behavior_page.dart:180](../../../lib/features/settings/pages/display_behavior_page.dart#L180) | Показывать обновления · `displaySettingsPageShowUpdatesTitle` | `showAppUpdates` | `display_show_app_updates_v1` | Приложение / Обновления |
| [display_behavior_page.dart:190](../../../lib/features/settings/pages/display_behavior_page.dart#L190) | Не выключать экран во время генерации · `displaySettingsPageKeepScreenOnDuringGenerationTitle` | `keepScreenOnDuringGeneration` | `display_keep_screen_on_during_generation_v1` | Приложение / Экран и питание |
| [display_behavior_page.dart:202](../../../lib/features/settings/pages/display_behavior_page.dart#L202) | Кнопки навигации по сообщениям · `displaySettingsPageMessageNavButtonsTitle` | `mobileMessageNavButtonsMode` / `setMobileMessageNavButtonsMode` | `display_mobile_message_nav_buttons_mode_v1` | Чаты и ответы / Прокрутка |
| [display_settings_widgets.dart:351](../../../lib/features/settings/pages/display_settings_widgets.dart#L351)/:358/:365 | Всегда / При прокрутке / Никогда не показывать · `displaySettingsPageMessageNavButtonsModeAlways`, `displaySettingsPageMessageNavButtonsModeScroll`, `displaySettingsPageMessageNavButtonsModeNever` | значения `always`, `scroll`, `never` | тот же key | Чаты и ответы / Прокрутка |
| [display_behavior_page.dart:218](../../../lib/features/settings/pages/display_behavior_page.dart#L218) | Миниатюры картинок в списке чатов · `displaySettingsPageSidebarThumbnailsTitle` | `sidebarThumbnails` | `sidebar_thumbnails_v1` | Внешний вид / Боковая панель |
| [display_behavior_page.dart:228](../../../lib/features/settings/pages/display_behavior_page.dart#L228) | Не закрывать боковую панель при выборе ассистента · `displaySettingsPageKeepSidebarOpenOnAssistantTapTitle` | `keepSidebarOpenOnAssistantTap` | `display_keep_sidebar_open_on_assistant_tap_v1` | Приложение / Навигация / Дополнительно |
| [display_behavior_page.dart:238](../../../lib/features/settings/pages/display_behavior_page.dart#L238) | Не закрывать боковую панель при выборе темы · `displaySettingsPageKeepSidebarOpenOnTopicTapTitle` | `keepSidebarOpenOnTopicTap` | `display_keep_sidebar_open_on_topic_tap_v1` | Приложение / Навигация / Дополнительно |
| [display_behavior_page.dart:248](../../../lib/features/settings/pages/display_behavior_page.dart#L248) | Не сворачивать список ассистентов при закрытии панели · `displaySettingsPageKeepAssistantListExpandedOnSidebarCloseTitle` | `keepAssistantListExpandedOnSidebarClose` | `display_keep_assistant_list_expanded_on_sidebar_close_v1` | Приложение / Навигация / Дополнительно |
| [display_behavior_page.dart:259](../../../lib/features/settings/pages/display_behavior_page.dart#L259) | Ярлыки в боковой панели · `sideDrawerShortcutsTitle` | `sidebarShortcuts`; `showSidebarShortcutPicker` → `setSidebarShortcuts` | `sidebar_shortcuts_v1` | Приложение / Навигация |
| [display_behavior_page.dart:267](../../../lib/features/settings/pages/display_behavior_page.dart#L267) | Новый чат при смене ассистента · `displaySettingsPageNewChatOnAssistantSwitchTitle` | `newChatOnAssistantSwitch` | `display_new_chat_on_assistant_switch_v1` | Чаты и ответы / Новые чаты |
| [display_behavior_page.dart:277](../../../lib/features/settings/pages/display_behavior_page.dart#L277) | Новый чат после удаления темы · `displaySettingsPageNewChatAfterDeleteTitle` | `newChatAfterDelete` | `display_new_chat_after_delete_v1` | Чаты и ответы / Новые чаты |
| [display_behavior_page.dart:286](../../../lib/features/settings/pages/display_behavior_page.dart#L286) | Новый чат при запуске · `displaySettingsPageNewChatOnLaunchTitle` | `newChatOnLaunch` | `display_new_chat_on_launch_v1` | Приложение / Запуск |
| [display_behavior_page.dart:295](../../../lib/features/settings/pages/display_behavior_page.dart#L295) | Отправлять по Enter · `displaySettingsPageEnterToSendTitle` | `enterToSendOnMobile` | `display_enter_to_send_on_mobile_v1` | Чаты и ответы / Ввод |
| [display_behavior_page.dart:304](../../../lib/features/settings/pages/display_behavior_page.dart#L304) | Вставлять длинный текст как файл · `displaySettingsPageLongPasteAsFileTitle` | `longPasteAsFile` | `display_long_paste_as_file_v1` | Чаты и ответы / Ввод |
| [display_behavior_page.dart:410](../../../lib/features/settings/pages/display_behavior_page.dart#L410) | Порог преобразования · `displaySettingsPageLongPasteAsFileThresholdTitle`; 1–999999 символов, условный | `longPasteAsFileThreshold` / `setLongPasteAsFileThreshold` | `display_long_paste_as_file_threshold_v1` | Чаты и ответы / Ввод / Дополнительно |

Setters SP :4784–4988, :5067, :5261, :5459/:5528–5614; suggestion setter отдельно :4010. Sidebar picker находится вне заданных файлов: `sidebar_bottom_bar.dart:277` — выбор pinned mini apps/bookmarks.

**Виброотклик**

| display_haptics_page.dart | Подпись · ключ | SP property | Persist key |
|---|---|---|---|
| [display_haptics_page.dart:42](../../../lib/features/settings/pages/display_haptics_page.dart#L42) | Общий виброотклик · `displaySettingsPageHapticsGlobalTitle` | `hapticsGlobalEnabled` | `display_haptics_global_enabled_v1` |
| [display_haptics_page.dart:51](../../../lib/features/settings/pages/display_haptics_page.dart#L51) | Виброотклик переключателей · `displaySettingsPageHapticsIosSwitchTitle` | `hapticsIosSwitch` | `display_haptics_ios_switch_v1` |
| [display_haptics_page.dart:60](../../../lib/features/settings/pages/display_haptics_page.dart#L60) | Виброотклик боковой панели · `displaySettingsPageHapticsOnSidebarTitle` | `hapticsOnDrawer` | `display_haptics_on_drawer_v1` |
| [display_haptics_page.dart:69](../../../lib/features/settings/pages/display_haptics_page.dart#L69) | Виброотклик элементов списка · `displaySettingsPageHapticsOnListItemTapTitle` | `hapticsOnListItemTap` | `display_haptics_on_list_item_tap_v1` |
| [display_haptics_page.dart:78](../../../lib/features/settings/pages/display_haptics_page.dart#L78) | Виброотклик карточек · `displaySettingsPageHapticsOnCardTapTitle` | `hapticsOnCardTap` | `display_haptics_on_card_tap_v1` |
| [display_haptics_page.dart:87](../../../lib/features/settings/pages/display_haptics_page.dart#L87) | Виброотклик при генерации · `displaySettingsPageHapticsOnGenerateTitle` | `hapticsOnGenerate` | `display_haptics_on_generate_v1` |

Все → **Приложение / Виброотклик**; отдельные события глубже после общего switch. SP :5448/:5471–5517.

**Тема / дополнительные параметры / Стекло**

| Источник | Подпись · ключ / варианты | SP действие / property | Persist | Предложенный путь |
|---|---|---|---|---|
| [theme_settings_page.dart:72](../../../lib/features/settings/pages/theme_settings_page.dart#L72) | Дополнительные настройки темы · `themeAdvancedSettingsPageTitle` | открывает `ThemeAdvancedSettingsPage` | — | Внешний вид / Тема / Дополнительно |
| [theme_settings_page.dart:97](../../../lib/features/settings/pages/theme_settings_page.dart#L97) | Системные динамические цвета · `themeSettingsPageUseDynamicColorTitle`; видим только `dynamicColorSupported` | `useDynamicColor` / `setUseDynamicColor` | `use_dynamic_color_v1` | Внешний вид / Тема |
| [theme_settings_page.dart:112](../../../lib/features/settings/pages/theme_settings_page.dart#L112) | Чистый фон · `themeSettingsPageUsePureBackgroundTitle` | `usePureBackground` / `setUsePureBackground` | `display_use_pure_background_v1` | Внешний вид / Тема |
| [theme_settings_page.dart:125](../../../lib/features/settings/pages/theme_settings_page.dart#L125)/:132 | Выбор встроенной палитры; labels ниже | `themePaletteId` / `setThemePalette(id)` | `theme_palette_v1` | Внешний вид / Тема |
| [theme_settings_page.dart:141](../../../lib/features/settings/pages/theme_settings_page.dart#L141) | Новая тема · `customThemeNewTheme` | `showCustomThemeEditor` → `saveCustomTheme` | `custom_themes_v1`, `custom_theme_selected_v1` | Внешний вид / Тема / Свои темы |
| [theme_settings_page.dart:150](../../../lib/features/settings/pages/theme_settings_page.dart#L150) | Импортировать тему · `customThemeImportTheme` | `showImportCustomThemeDialog` → `importCustomTheme` | те же custom theme keys | Внешний вид / Тема / Свои темы |
| [theme_settings_page.dart:193](../../../lib/features/settings/pages/theme_settings_page.dart#L193)/:198 | Сохранённая тема: `theme.name`, если пусто «Свой вариант» · `themeSettingsPageCustomPaletteName` | `selectCustomTheme(id)` | `custom_theme_selected_v1`, `theme_palette_v1='custom'` | Внешний вид / Тема / Свои темы |
| [theme_settings_page.dart:242](../../../lib/features/settings/pages/theme_settings_page.dart#L242) | Copy icon, **label/tooltip отсутствует** | `exportCustomThemeToClipboard` | нет | Внешний вид / Тема / Свои темы |
| [theme_settings_page.dart:243](../../../lib/features/settings/pages/theme_settings_page.dart#L243) | Edit icon, **label/tooltip отсутствует** | `showCustomThemeEditor(initial:…)` | `custom_themes_v1` | Внешний вид / Тема / Свои темы |
| [theme_settings_page.dart:244](../../../lib/features/settings/pages/theme_settings_page.dart#L244)/:179 | Delete icon без label; confirm «Удалить эту тему?» · `customThemeDeleteConfirm` | `deleteCustomTheme`; может сменить selection/default palette | custom keys + при необходимости `theme_palette_v1` | Внешний вид / Тема / Свои темы |
| [theme_advanced_settings_page.dart:42](../../../lib/features/settings/pages/theme_advanced_settings_page.dart#L42) | Многослойные поверхности (экспериментально) · `themeAdvancedSettingsPageUseLayeredSurfacesTitle` | `useLayeredSurfaces` / `setUseLayeredSurfaces` | `display_use_layered_surfaces_v1` | Внешний вид / Тема / Дополнительно |
| [theme_advanced_settings_page.dart:53](../../../lib/features/settings/pages/theme_advanced_settings_page.dart#L53) | Многослойные элементы панелей · `themeAdvancedSettingsPageUseLayeredSheetTilesTitle` | `useLayeredSheetTiles` / `setUseLayeredSheetTiles` | `display_use_layered_sheet_tiles_v1` | Внешний вид / Тема / Дополнительно |
| [glass_theme_settings_page.dart:67](../../../lib/features/settings/pages/glass_theme_settings_page.dart#L67) | Тема «Стекло» · `glassThemeEnable` | `glassTheme` / `setGlassTheme(on, accentLight, accentDark)` | `display_glass_theme_v1`, `display_glass_restore_v1`, message style keys | Внешний вид / Стекло |
| [glass_theme_settings_page.dart:83](../../../lib/features/settings/pages/glass_theme_settings_page.dart#L83) | Экономный режим · `glassEconomyTitle` | `glassEconomy` / `setGlassEconomy` | `display_glass_economy_v1` | Внешний вид / Стекло |

Встроенные варианты `ThemePalettes.all` (UI theme_settings_page.dart:125; exact label mapping palettes.dart:22):

| id | RU label · l10n |
|---|---|
| `default` | Стандартная · `moruPaletteDefault` |
| `blue` | Небесная синева · `moruPaletteBlue` |
| `green` | Бамбуковая зелень · `moruPaletteGreen` |
| `purple` | Аметистовый · `moruPalettePurple` |
| `yellow` | Янтарное золото · `moruPaletteYellow` |
| `smoky_rose` | Дымчатая роза · `moruPaletteSmokyRose` |
| `terracotta` | Терракота · `moruPaletteTerracotta` |
| `monochrome` | Морозный серый · `moruPaletteMonochrome` |
| `doc_theme` | Документ · `moruPaletteDocTheme` |

SP setters :2668–2692/:2718/:2809/:2816/:2879–2944. Glass — preset с snapshot: включение меняет message background style и role overrides; выключение восстанавливает snapshot. Это пересечение со «Стилем сообщений», не независимая вторая реализация.

**Стиль сообщений — все controls**

`U/A` ниже — `userChatBubbleStyleOverrides` / `assistantChatBubbleStyleOverrides`. Setter всех параметров `setChatBubbleStyleOverridesForRole(isUser,value)`; assistant JSON хранится в `chat_bubble_style_overrides_v1`, user JSON — в `chat_bubble_style_overrides_user_v1`. Точные поля JSON соответствуют `copyWith` ниже. Все → **Внешний вид / Стиль сообщений**, role/light-dark tuning глубже.

| message_style_settings_page.dart | Подпись · ключ | Property / действие | Условие / диапазон / persist |
|---|---|---|---|
| [message_style_settings_page.dart:53](../../../lib/features/settings/pages/message_style_settings_page.dart#L53)/:550 | Сбросить · `messageStyleSettingsPageReset` | `resetMessageStyleSettings` → `setChatBubbleStyleOverrides(empty)` | очищает assistant override + user split; confirm :530 `messageStyleSettingsPageResetConfirm`, cancel :542 `messageStyleSettingsPageCancel` |
| [message_style_settings_page.dart:136](../../../lib/features/settings/pages/message_style_settings_page.dart#L136) | По умолчанию · `displaySettingsPageChatMessageBackgroundDefault` | `setChatMessageBackgroundStyle(defaultStyle)` | `display_chat_message_background_style_v1='default'` |
| [message_style_settings_page.dart:146](../../../lib/features/settings/pages/message_style_settings_page.dart#L146) | Матовое стекло · `displaySettingsPageChatMessageBackgroundFrosted` | `setChatMessageBackgroundStyle(frosted)` | тот же key `frosted` |
| [message_style_settings_page.dart:156](../../../lib/features/settings/pages/message_style_settings_page.dart#L156) | Сплошной цвет · `displaySettingsPageChatMessageBackgroundSolid` | `setChatMessageBackgroundStyle(solid)` | тот же key `solid` |
| [message_style_settings_page.dart:169](../../../lib/features/settings/pages/message_style_settings_page.dart#L169) | Подгонять пузырь ассистента под содержимое · `messageStyleSettingsPageAssistantFitContent` | `assistantBubbleFitContent` / `setAssistantBubbleFitContent` | `display_assistant_bubble_fit_content_v1` |
| [message_style_settings_page.dart:176](../../../lib/features/settings/pages/message_style_settings_page.dart#L176) | Разделять абзацы на пузыри · `messageStyleSettingsPageAssistantSplitParagraphs` | `assistantBubbleSplitParagraphs` / `setAssistantBubbleSplitParagraphs` | `display_assistant_bubble_split_paragraphs_v1` |
| [message_style_settings_page.dart:361](../../../lib/features/settings/pages/message_style_settings_page.dart#L361)/:363 | Светлая / Тёмная · `messageStyleSettingsPageLight`, `messageStyleSettingsPageDark` | local `_editingDark` | preview/editor selection, не persist |
| [message_style_settings_page.dart:375](../../../lib/features/settings/pages/message_style_settings_page.dart#L375)/:377 | Пользователь / Ассистент · `messageStyleSettingsPageRoleUser`, `messageStyleSettingsPageRoleAssistant` | local `_editingUser` | только non-default, не persist |
| [message_style_settings_page.dart:198](../../../lib/features/settings/pages/message_style_settings_page.dart#L198) | Размытие · `messageStyleSettingsPageBlur` | U/A `.blurSigma` | только frosted; 0–30, шаг 1 |
| [message_style_settings_page.dart:225](../../../lib/features/settings/pages/message_style_settings_page.dart#L225) | Фон · `messageStyleSettingsPageBackgroundColor` | U/A `.backgroundArgbLight` / `.backgroundArgbDark` | color picker; выбранная светлая/тёмная |
| [message_style_settings_page.dart:244](../../../lib/features/settings/pages/message_style_settings_page.dart#L244) | Непрозрачность фона · `messageStyleSettingsPageBackgroundOpacity` | U/A `.frostedOpacity` или `.solidOpacity` | non-default; 0–100%, шаг 1 |
| [message_style_settings_page.dart:264](../../../lib/features/settings/pages/message_style_settings_page.dart#L264) | Рамка · `messageStyleSettingsPageBorderColor` | U/A `.borderArgbLight` / `.borderArgbDark` | color picker |
| [message_style_settings_page.dart:283](../../../lib/features/settings/pages/message_style_settings_page.dart#L283) | Непрозрачность рамки · `messageStyleSettingsPageBorderOpacity` | U/A `.borderOpacity` | non-default; 0–100%, шаг 1 |
| [message_style_settings_page.dart:300](../../../lib/features/settings/pages/message_style_settings_page.dart#L300) | Толщина рамки · `messageStyleSettingsPageBorderWidth` | U/A `.borderWidth` | non-default; 0–3, шаг 0.1 |
| [message_style_settings_page.dart:315](../../../lib/features/settings/pages/message_style_settings_page.dart#L315) | Текст · `messageStyleSettingsPageTextColor` | U/A `.textArgbLight` / `.textArgbDark` | color picker |
| [message_style_settings_page.dart:334](../../../lib/features/settings/pages/message_style_settings_page.dart#L334) | Радиус скругления · `messageStyleSettingsPageCornerRadius` | U/A `.cornerRadius` | non-default; 0–28, шаг 1 |

Важная неточность текущего UI: confirm «Сбросить **все** настройки стиля сообщений?» сбрасывает **только overrides**, не background style, fit-content/split-paragraph switches, Glass/economy. Код :70–75; SP :2976–2991. Эта находка передана `/root/theme_audit`.

`message_style_rows.dart` — reusable row/slider/segmented widgets, дополнительных самостоятельных controls нет. `message_style_preview.dart` — неинтерактивный preview: labels `messageStyleSettingsPagePreviewUser` :118, `messageStyleSettingsPagePreviewThinking` :150, `messageStyleSettingsPagePreviewAssistant` :179.

**Google Fonts picker — все controls**

| google_fonts_picker_page.dart | Подпись · ключ | Действие / persist | Предложенный путь |
|---|---|---|---|
| [google_fonts_picker_page.dart:214](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L214) | Закрыть · `statsPageClose` | pop, disabled при apply | Внешний вид / Шрифты / Google Fonts |
| [google_fonts_picker_page.dart:220](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L220)/:343 | Обновить список шрифтов · `googleFontsRefresh` | reload catalogue; retry при failure | тот же |
| [google_fonts_picker_page.dart:249](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L249) | Поиск · `settingsPageSearch`; hint «Поиск шрифтов или языков» · `googleFontsSearchHint` | local `_search`, не persist | тот же |
| [google_fonts_picker_page.dart:357](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L357)/:362 | Динамическое имя `font.family` + Download icon | выбирает/скачивает font для preview, ещё не SP change | тот же |
| [google_fonts_picker_page.dart:319](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L319) | Лицензия шрифта · `googleFontsLicense` | dialog с license, close :313 `statsPageClose` | тот же |
| [google_fonts_picker_page.dart:323](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L323) | Применить · `statsPageCustomRangeApply` | `onApply` → :20 `setCodeFontFromLocal` / :24 `setAppFontFromLocal`, передаёт license | font family/path/alias keys выше |

Установленные Google Fonts сохраняются как **локальные managed font files**, не legacy Google selection flag. `display_app_font_is_google_v1`, `display_code_font_is_google_v1` в SP :355–357 — только migration/read-once keys, picker их не пишет.

**Изображения — все controls**

| image_settings_page.dart | Подпись · ключ | SP property / setter | Persist key |
|---|---|---|---|
| [image_settings_page.dart:76](../../../lib/features/settings/pages/image_settings_page.dart#L76) | Обрезка изображений · `displaySettingsPageEnableImageCropperTitle` | `imageCropperEnabled` / `setImageCropperEnabled` | `image_cropper_enabled_v1` |
| [image_settings_page.dart:90](../../../lib/features/settings/pages/image_settings_page.dart#L90) | Отправлять Markdown-ссылки на изображения как изображения · `imageSettingsPageMarkdownImageLinksTitle` | `sendMarkdownImageLinksAsImages` / `setSendMarkdownImageLinksAsImages` | `send_markdown_image_links_as_images_v1` |
| [image_settings_page.dart:27](../../../lib/features/settings/pages/image_settings_page.dart#L27)/:392 | Исходное · `imageSettingsPageQualityOriginal` | `imageUploadQuality=original` / `setImageUploadQuality` | `image_upload_quality_v1` |
| [image_settings_page.dart:27](../../../lib/features/settings/pages/image_settings_page.dart#L27)/:393 | Высокое качество · `imageSettingsPageQualityHigh`; 2048 px, quality 90 | `imageUploadQuality=high` | тот же |
| [image_settings_page.dart:27](../../../lib/features/settings/pages/image_settings_page.dart#L27)/:394 | Сбалансированное · `imageSettingsPageQualityBalanced`; 1568 px, quality 85 | `imageUploadQuality=balanced` | тот же |
| [image_settings_page.dart:27](../../../lib/features/settings/pages/image_settings_page.dart#L27)/:395 | Экономия трафика · `imageSettingsPageQualitySaver`; 1024 px, quality 70 | `imageUploadQuality=saver` | тот же |
| [image_settings_page.dart:27](../../../lib/features/settings/pages/image_settings_page.dart#L27)/:396 | Свой вариант · `imageSettingsPageQualityCustom` | `imageUploadQuality=custom` | тот же |
| [image_settings_page.dart:231](../../../lib/features/settings/pages/image_settings_page.dart#L231)/:273 | Качество сжатия · `imageSettingsPageCustomQualityTitle`; 10–100, шаг 5, только custom | `imageCompressCustomQuality` / `setImageCompressCustomQuality` | `image_compress_custom_quality_v1` |
| [image_settings_page.dart:42](../../../lib/features/settings/pages/image_settings_page.dart#L42) | Сжимать прозрачные и анимированные изображения · `imageSettingsPageCompressTransparentTitle`; disabled при original | `imageCompressTransparentEnabled` / `setImageCompressTransparentEnabled` | `image_compress_transparent_enabled_v1` |

Все → **Чаты и ответы / Изображения**, последние два → «Сжатие / Дополнительно». SP :5299–5340.

**Android floating overlay appearance — все controls**

Все пишет `SP.mobileBackground` / `setMobileBackground` :3222, JSON preference **`mobile_background_settings_v1`**. Поля внешнего вида внутри JSON `overlayAppearance`; icons — sibling fields `overlayIconKind`, `overlayIconValue`. Сохранение дополнительно вызывает native coordinator `configure` (страница :50–54). Предложенный путь: **Приложение / Фон и уведомления / Плавающее окно / Внешний вид**; этот редкий редактор оправданно глубже, родитель должен содержать runtime/permissions.

| background_overlay_settings_page.dart | Подпись · ключ | JSON поле / действие |
|---|---|---|
| [background_overlay_settings_page.dart:207](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L207) | Карточка · `backgroundOverlayCard` | весь `overlayAppearance=BackgroundOverlayAppearance()` |
| [background_overlay_settings_page.dart:211](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L211) | Круглый значок · `backgroundOverlayCircle` | весь `overlayAppearance=BackgroundOverlayAppearance.circle` |
| [background_overlay_settings_page.dart:233](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L233) | Ширина · `backgroundOverlayWidth` | `overlayAppearance.width`, 48–400, шаг 1 |
| [background_overlay_settings_page.dart:241](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L241) | Высота · `backgroundOverlayHeight` | `.height`, 48–180, шаг 1 |
| [background_overlay_settings_page.dart:249](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L249) | Радиус скругления · `backgroundOverlayCornerRadius` | `.cornerRadius`, 0–90, шаг 1 |
| [background_overlay_settings_page.dart:257](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L257) | Размер значка · `backgroundOverlayIconSize` | `.iconSize`, 16–120, шаг 1 |
| [background_overlay_settings_page.dart:265](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L265) | Диаметр кольца прогресса · `backgroundOverlayProgressSize` | `.progressSize`, 20–140, шаг 1 |
| [background_overlay_settings_page.dart:273](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L273) | Толщина кольца прогресса · `backgroundOverlayProgressStroke` | `.progressStrokeWidth`, 1–12, шаг 0.5 |
| [background_overlay_settings_page.dart:291](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L291) | Показывать кольцо прогресса · `backgroundOverlayShowProgress` | `.showProgress` |
| [background_overlay_settings_page.dart:297](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L297) | Показывать заголовок · `backgroundOverlayShowTitle` | `.showTitle` |
| [background_overlay_settings_page.dart:303](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L303) | Показывать подзаголовок · `backgroundOverlayShowSubtitle` | `.showSubtitle` |
| [background_overlay_settings_page.dart:309](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L309) | Показывать прошедшее время · `backgroundOverlayShowTime` | `.showTime` |
| [background_overlay_settings_page.dart:315](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L315) | Показывать кнопку закрытия · `backgroundOverlayShowClose` | `.showClose` |
| [background_overlay_settings_page.dart:321](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L321) | Показывать фон · `backgroundOverlayShowBackground` | `.showBackground` |
| [background_overlay_settings_page.dart:327](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L327) | Показывать рамку · `backgroundOverlayShowBorder` | `.showBorder` |
| [background_overlay_settings_page.dart:342](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L342) | Выбрать изображение · `backgroundIconImage` | picker gallery; `overlayIconKind='image'`, `overlayIconValue=managed path` |
| [background_overlay_settings_page.dart:348](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L348) | Выбрать эмодзи · `backgroundIconEmoji` | emoji dialog; `overlayIconKind='emoji'`, `overlayIconValue=emoji` |
| [background_overlay_settings_page.dart:353](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L353) | Значок Moru · `backgroundIconDefault` | `overlayIconKind='app'`, `overlayIconValue=''` |
| [background_overlay_settings_page.dart:364](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L364) | Восстановить исходное оформление · `backgroundOverlayReset` | resets `overlayAppearance` только; выбранную icon не сбрасывает |

Preview показывает hint `backgroundOverlayPreviewHint` :187 «Перетащите для перемещения · Нажмите для открытия чата · Удерживайте для скрытия», но `BackgroundStatusPreview` на этой странице получает только appearance/artwork/text: это описание поведения native overlay, самостоятельных settings controls в preview здесь нет.

**Профиль пользователя — все controls**

Здесь **нет SettingsProvider**: `MemoryProviderV2.profileFields`, `putProfileField(key,value,MemorySource.manual)` / `removeProfileField(key)` (provider :227/:236). Persist source key **`user_profile_fields_v1`**, business entity table **`user_profile_field_rows`** (`business_data.dart:43–45`); repository :369/:399/:474/:489. Все → **Данные и память → Профиль пользователя**, свои поля — глубже.

| user_profile_page.dart | Подпись · ключ | Профиль / действие |
|---|---|---|
| [user_profile_page.dart:67](../../../lib/features/settings/pages/user_profile_page.dart#L67)/:173 | Предпочитаемое имя · `userProfilePreferredName` | field `preferred_name`, edit sheet |
| [user_profile_page.dart:69](../../../lib/features/settings/pages/user_profile_page.dart#L69)/:173 | Пол · `userProfileGender` | `gender`, edit sheet |
| [user_profile_page.dart:71](../../../lib/features/settings/pages/user_profile_page.dart#L71)/:173 | Местоимения · `userProfilePronouns` | `pronouns`, edit sheet |
| [user_profile_page.dart:73](../../../lib/features/settings/pages/user_profile_page.dart#L73)/:173 | Предпочитаемый язык · `userProfilePreferredLanguage` | `preferred_language`, edit sheet |
| [user_profile_page.dart:75](../../../lib/features/settings/pages/user_profile_page.dart#L75)/:173 | Часовой пояс · `userProfileTimezone` | `timezone`, edit sheet |
| [user_profile_page.dart:77](../../../lib/features/settings/pages/user_profile_page.dart#L77)/:173 | Род деятельности · `userProfileOccupation` | `occupation`, edit sheet |
| [user_profile_page.dart:79](../../../lib/features/settings/pages/user_profile_page.dart#L79)/:173 | Местоположение · `userProfileLocation` | `location`, edit sheet |
| [user_profile_page.dart:193](../../../lib/features/settings/pages/user_profile_page.dart#L193) | Свои сохранённые поля: динамический `custom.*` key | edit value существующего поля |
| [user_profile_page.dart:216](../../../lib/features/settings/pages/user_profile_page.dart#L216) | Добавить своё поле · `userProfileAddCustom` | new custom form |
| [user_profile_page.dart:299](../../../lib/features/settings/pages/user_profile_page.dart#L299) | Ключ · `memoryUiCustomKeyLabel`; hint `userProfileCustomKeyHint` | ввод ключа; только new custom; `custom.[A-Za-z0-9_-]{1,32}` |
| [user_profile_page.dart:307](../../../lib/features/settings/pages/user_profile_page.dart#L307) | Значение · `memoryUiValueLabel`; hint `userProfileCustomValueHint` | ввод value для любого profile field |
| [user_profile_page.dart:322](../../../lib/features/settings/pages/user_profile_page.dart#L322) | Сохранить · `userProfileSave` | put; пустое значение удаляет поле |
| [user_profile_page.dart:327](../../../lib/features/settings/pages/user_profile_page.dart#L327) | Очистить · `userProfileClear` | remove; только существующее непустое значение |
| :323 → [memory_ui.dart:887](../../../lib/features/settings/widgets/memory_ui.dart#L887) | Отмена · `homePageCancel` | dismiss sheet, без persist |

Для всех пустых profile rows detail «Не задано» (`userProfileEmptyValue` :176/:197).

Общие служебные controls: Back «Назад» (`settingsPageBackButton`) на display_settings :63, display_chat_item :31, display_rendering :26, display_behavior :43, display_haptics :24, theme :61, theme_advanced :24, glass :47, image :57, user_profile :30; overlay использует тот же ключ :143. Google picker использует Close, перечислен отдельно.

Наблюдения: текущий Display root имеет **17 разнотипных входов**, и часть названий скрывает несколько самостоятельных настроек; особенно «Поведение и запуск» содержит **26 controls** из двух разных будущих разделов. Theme custom row Copy/Edit/Delete лишены подписей/tooltip. Reset message style подтверждает «все», но меняет лишь overrides. Подробный аудит механики темы: [audit-theme.md](audit-theme.md).

## Связанные редакторы за пределами settings/pages

Таблица ниже сохраняет все буквальные `label`/`labelText` controls связанных редакторов, включая обычные действия и условные/legacy строки; это **surface inventory**, не утверждение, что каждый label — preference. Динамические каталоги, chips и кастомные заголовки дополнены отдельными примечаниями. Provider/search полная модель данных и подписки — в справочнике SettingsProvider ниже.

| Feature → стало | Было: файл | Точные labels / keys (в порядке первого появления) |
|---|---|---|
| agents → Ассистенты и агенты → Агенты | [agent_detail_page.dart:1](../../../lib/features/agents/pages/agent_detail_page.dart#L1) | Открыть веб-интерфейс (`agentsWebOpen`, L135)<br>Остановить (`agentsWebStop`, L162)<br>Отмена (`agentsCancel`, L204)<br>Начать чат (`agentsStartChat`, L228)<br>Проверить связь (`agentsCheck`, L237)<br>Удалить (`agentsRemove`, L252)<br>Удалить агента (`agentsCustomDelete`, L262) |
| agents → Ассистенты и агенты → Агенты | [agents_page.dart:1](../../../lib/features/agents/pages/agents_page.dart#L1) | Добавить своего агента (`agentsCustomAdd`, L95)<br>Название (`agentsCustomName`, L202)<br>Команда (`agentsCustomCommand`, L210) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_regex_tab.dart:1](../../../lib/features/assistant/pages/assistant_regex_tab.dart#L1) | Название правила (`assistantRegexNameLabel`, L800)<br>Регулярное выражение (`assistantRegexPatternLabel`, L806)<br>Строка замены (`assistantRegexReplacementLabel`, L811)<br>Пользователь (`assistantRegexScopeUser`, L828)<br>Ассистент (`assistantRegexScopeAssistant`, L846)<br>Только отображение (`assistantRegexScopeVisualOnly`, L868)<br>Только замена (`assistantRegexScopeReplaceOnly`, L879) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_basic_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart#L1) | Имя ассистента (`assistantEditAssistantNameLabel`, L146)<br>Температура (`assistantEditTemperatureTitle`, L167)<br>Top-p (`assistantEditTopPTitle`, L178)<br>Сообщения в контексте (`assistantEditContextMessagesTitle`, L189)<br>Бюджет рассуждений (`assistantEditThinkingBudgetTitle`, L200)<br>Максимум токенов (`assistantEditMaxTokensTitle`, L228)<br>Использовать аватар ассистента (`assistantEditUseAssistantAvatarTitle`, L240)<br>Использовать имя ассистента (`assistantEditUseAssistantNameTitle`, L250)<br>Потоковый вывод (`assistantEditStreamOutputTitle`, L261)<br>Выбрать изображение (`assistantEditChooseImageButton`, L494)<br>Очистить (`assistantEditClearButton`, L502) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_memory_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_memory_tab.dart#L1) | Использовать долговременную память (`assistantEditMemorySwitchTitle`, L201)<br>Автоупорядочивание памяти (`assistantEditAutoOrganizeTitle`, L220)<br>Разрешить вспоминать прошлые чаты (`assistantEditAllowPastRecallTitle`, L268)<br>Создавать сводки диалогов (`assistantEditGenerateSummaryTitle`, L292)<br>Изменить сводку (`assistantEditSummaryDialogTitle`, L581)<br>Ходы (`assistantEditOrganizeFrequencyCustomLabel`, L1010)<br>Упорядочивать каждые N ходов (`assistantEditOrganizeFrequencyTitle`, L1078)<br>Каждые {n} (`assistantEditOrganizeFrequencyOption`, L1085)<br>Свой вариант (`assistantEditOrganizeFrequencyCustomButton`, L1089)<br>Поиск повторов (`assistantEditDedupeModeTitle`, L1168)<br>Всегда общая (`assistantEditWriteScopeAlwaysGlobal`, L1207)<br>Всегда этот ассистент (`assistantEditWriteScopeAlwaysAssistant`, L1212)<br>Выбирает модель (по умолчанию — общая) (`assistantEditWriteScopeToolDefaultGlobal`, L1217)<br>Выбирает модель (по умолчанию — ассистент) (`assistantEditWriteScopeToolDefaultAssistant`, L1222)<br>Область записи памяти (`assistantEditWriteScopeTitle`, L1261)<br>Количество новых сообщений (`assistantEditRecentChatsSummaryFrequencyCustomLabel`, L1302)<br>Частота обновления сводки (`assistantEditRecentChatsSummaryFrequencyTitle`, L1366)<br>Каждые {count} (`assistantEditRecentChatsSummaryFrequencyOption`, L1372)<br>Свой вариант (`assistantEditRecentChatsSummaryFrequencyCustomButton`, L1376) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_memory_tab_legacy.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_memory_tab_legacy.dart#L1) | Отмена (`assistantEditEmojiDialogCancel`, L92)<br>Сохранить (`assistantEditEmojiDialogSave`, L102)<br>Использовать долговременную память (`assistantEditMemorySwitchTitle`, L168)<br>Сведения о последних чатах (`assistantEditRecentChatsSwitchTitle`, L180)<br>Количество новых сообщений (`assistantEditRecentChatsSummaryFrequencyCustomLabel`, L687)<br>Каждые {count} (`assistantEditRecentChatsSummaryFrequencyOption`, L817)<br>Свой вариант (`assistantEditRecentChatsSummaryFrequencyCustomButton`, L833) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_page.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_page.dart#L1) | Основное (`assistantEditPageBasicTab`, L105)<br>Промпты (`assistantEditPagePromptsTab`, L111)<br>Память (`assistantEditPageMemoryTab`, L117)<br>Локальные инструменты (`assistantEditPageLocalToolsTab`, L123)<br>Навыки (`skillsTab`, L129)<br>MCP (`assistantEditPageMcpTab`, L135)<br>Быстрая фраза (`assistantEditPageQuickPhraseTab`, L141)<br>Свой вариант (`assistantEditPageCustomTab`, L147)<br>Замены по регулярным выражениям (`assistantEditPageRegexTab`, L153)<br>Настройки списком разделов (`assistantEditOutlineModeTitle`, L755)<br>Имя ассистента (`assistantEditAssistantNameLabel`, L2023)<br>Использовать аватар ассистента (`assistantEditUseAssistantAvatarTitle`, L2410)<br>Использовать имя ассистента (`assistantEditUseAssistantNameTitle`, L2418)<br>Потоковый вывод (`assistantEditStreamOutputTitle`, L2426)<br>Выбрать изображение (`assistantEditChooseImageButton`, L2649)<br>Очистить (`assistantEditClearButton`, L2657)<br>Использовать эмодзи (`desktopAvatarMenuUseEmoji`, L2712)<br>Выбрать изображение… (`desktopAvatarMenuChangeFromImage`, L2728)<br>Ввести ссылку (`assistantEditAvatarEnterLink`, L2759)<br>Импортировать из QQ (`assistantEditAvatarImportQQ`, L2766)<br>Сбросить аватар (`desktopAvatarMenuReset`, L2773) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_prompt_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_prompt_tab.dart#L1) | Импортировать файл (`assistantEditSystemPromptImportButton`, L305)<br>Формат ISO 8601 (`assistantEditPromptIso8601Title`, L443)<br>Добавить сообщение пользователя (`assistantEditPresetAddUser`, L590)<br>Добавить сообщение ассистента (`assistantEditPresetAddAssistant`, L613)<br>Отмена (`assistantEditEmojiDialogCancel`, L825)<br>Сохранить (`assistantEditEmojiDialogSave`, L838) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_quick_phrase_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_quick_phrase_tab.dart#L1) | Добавить быструю фразу (`assistantEditAddQuickPhraseButton`, L89)<br>Заголовок (`quickPhraseTitleLabel`, L425)<br>Содержимое (`quickPhraseContentLabel`, L453)<br>Отмена (`quickPhraseCancelButton`, L484)<br>Сохранить (`quickPhraseSaveButton`, L496) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_edit_skills_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_skills_tab.dart#L1) | Управление навыками (`skillsOpenPage`, L164) |
| assistant → Ассистенты и агенты → Ассистент | [assistant_settings_page.dart:1](../../../lib/features/assistant/pages/assistant_settings_page.dart#L1) | Отмена (`assistantSettingsAddSheetCancel`, L506)<br>Сохранить (`assistantSettingsAddSheetSave`, L513) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [environment_download_page.dart:1](../../../lib/features/workspace/pages/environment_download_page.dart#L1) | Дистрибутив (`workspaceEnvDistribution`, L242)<br>Версия (`workspaceEnvSystemVersion`, L251)<br>Свой URL (`workspaceEnvDownloadCustom`, L300)<br>Выбрать архив rootfs (`workspaceEnvChooseImage`, L321) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [environment_variables_page.dart:1](../../../lib/features/workspace/pages/environment_variables_page.dart#L1) | Режим конфиденциальности (`workspaceEnvPrivacyMode`, L107)<br>Добавить переменную (`workspaceEnvVariableAdd`, L129)<br>Имя (`workspaceEnvVariableName`, L276)<br>Значение (`workspaceEnvVariableValue`, L287)<br>Примечание (необязательно) (`workspaceEnvVariableNote`, L295)<br>Удалить (`workspaceFilesDelete`, L314) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [external_mounts_page.dart:1](../../../lib/features/workspace/pages/external_mounts_page.dart#L1) | Добавить папку (`workspaceMountAdd`, L176)<br>Имя (`workspacesNameLabel`, L371)<br>Разрешить запись (`workspaceMountAllowWrite`, L382)<br>Просмотреть файлы (`workspaceMountBrowse`, L399)<br>Выбрать папку заново (`workspaceExternalReconnect`, L411)<br>Отключить папку (`workspaceMountUnmount`, L417) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [mirror_page.dart:1](../../../lib/features/workspace/pages/mirror_page.dart#L1) | Использовать зеркало (`workspaceEnvUseMirror`, L205)<br>Проверить скорость (`workspaceEnvSpeedTest`, L235) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [proot_options_page.dart:1](../../../lib/features/workspace/pages/proot_options_page.dart#L1) | Путь к оболочке (`workspaceEnvShellPath`, L76)<br>Дополнительные аргументы PRoot (`workspaceEnvProotArguments`, L90)<br>Сохранить источник (`workspaceEnvDownloadSave`, L109) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [workspace_files_desktop_layout.dart:1](../../../lib/features/workspace/pages/workspace_files_desktop_layout.dart#L1) | Открыть в системном терминале (`workspaceDeskOpenSystemTerminal`, L177)<br>Показать в файловом менеджере (`workspaceDeskReveal`, L184)<br>Настройки (`workspacesSettings`, L190)<br>Повторить (`workspaceFilesRetry`, L223) |
| workspace → Рабочая область и инструменты → Рабочие области и среда | [workspaces_page.dart:1](../../../lib/features/workspace/pages/workspaces_page.dart#L1) | Имя (`workspacesNameLabel`, L148)<br>Также удалить файлы (`workspacesDeleteAlsoFiles`, L178)<br>Переименовать (`workspaceFilesRename`, L206)<br>Настройки (`workspacesSettings`, L211)<br>Новое рабочее пространство (`workspaceMgmtNewWorkspace`, L290)<br>Управляемое рабочее пространство (`workspaceMgmtKindManagedTitle`, L554)<br>Импортировать из папки (`workspaceMgmtImportFromFolder`, L563)<br>Спрашивать перед выполнением команд Shell (`workspacesShellNeedsApproval`, L881)<br>Рабочий каталог по умолчанию (`workspacesDefaultCwd`, L888)<br>Отмена (`workspaceFilesCancel`, L916)<br>Сохранить (`workspaceFilesSave`, L922) |
| scheduled_tasks → Рабочая область и инструменты → Задачи по расписанию | [scheduled_task_editor_page.dart:1](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L1) | Имя (`scheduledTasksName`, L442)<br>Ассистент (`scheduledTasksAssistant`, L454)<br>Действие (`scheduledTasksMode`, L461)<br>Диалог (`scheduledTasksChat`, L483)<br>Вопрос для повторного выполнения (`scheduledTasksMessage`, L492)<br>Модель (`scheduledTasksModel`, L509)<br>Промпт (`scheduledTasksPrompt`, L525)<br>Время (`scheduledTasksTime`, L544)<br>Повтор (`scheduledTasksRepeat`, L554)<br>Включено (`scheduledTasksEnabled`, L600) |
| scheduled_tasks → Рабочая область и инструменты → Задачи по расписанию | [scheduled_tasks_page.dart:1](../../../lib/features/scheduled_tasks/pages/scheduled_tasks_page.dart#L1) | Запустить сейчас (`scheduledTasksRunNow`, L127)<br>История запусков (`scheduledTasksHistory`, L132)<br>Изменить задачу (`scheduledTasksEdit`, L138)<br>Удалить задачу (`scheduledTasksDelete`, L143)<br>Открыть диалог (`scheduledTasksOpenChat`, L209)<br>Будильники и напоминания (`scheduledTasksPermission`, L305)<br>Добавить задачу (`scheduledTasksAdd`, L336)<br>Фоновые задачи (`backgroundSettingsTitle`, L366) |
| backup → Данные и память → Резервные копии | [backup_page.dart:1](../../../lib/features/backup/pages/backup_page.dart#L1) | Отмена (`backupPageCancel`, L141)<br>ОК (`backupPageOK`, L148)<br>Чаты (`backupPageChatsLabel`, L307)<br>Файлы (`backupPageFilesLabel`, L323)<br>Настройки сервера WebDAV (`backupPageWebDavServerSettings`, L354)<br>Проверить (`backupPageTestConnection`, L362)<br>Восстановить (`backupPageRestore`, L384)<br>Создать копию (`backupPageBackupNow`, L764)<br>Настройки S3 (`backupPageS3ServerSettings`, L806)<br>Экспортировать в файл (`backupPageExportToFile`, L1257)<br>Импортировать резервную копию (`backupPageImportBackupFile`, L1264)<br>Импорт из Cherry Studio (`backupPageImportFromCherryStudio`, L1271)<br>Импорт из Chatbox (`backupPageImportFromChatbox`, L1278)<br>Хранить локальные копии (`localSnapshotEnabledTitle`, L1560)<br>Управление копиями (`localSnapshotManageCopies`, L1570)<br>Напоминать о создании копии (`backupReminderEnableTitle`, L1612)<br>Периодичность (`backupReminderFrequencyTitle`, L1638)<br>Время напоминания (`backupReminderTimeTitle`, L1649)<br>Последняя копия (`backupReminderLastBackupTitle`, L1673)<br>Следующее напоминание (`backupReminderNextReminderTitle`, L1683)<br>URL сервера WebDAV (`backupPageWebDavServerUrl`, L2553)<br>Имя пользователя (`backupPageUsername`, L2559)<br>Пароль (`backupPagePassword`, L2564)<br>Путь (`backupPagePath`, L2576)<br>User-Agent (`backupPageUserAgent`, L2582)<br>Сохранить (`backupPageSave`, L2599)<br>Адрес сервера (`backupPageS3Endpoint`, L2731)<br>Регион (`backupPageS3Region`, L2737)<br>Бакет (`backupPageS3Bucket`, L2743)<br>ID ключа доступа (`backupPageS3AccessKeyId`, L2748)<br>Секретный ключ доступа (`backupPageS3SecretAccessKey`, L2753)<br>Токен сессии (необязательно) (`backupPageS3SessionToken`, L2764)<br>Префикс (`backupPageS3Prefix`, L2775) |
| backup → Данные и память → Резервные копии | [local_snapshots_page.dart:1](../../../lib/features/backup/pages/local_snapshots_page.dart#L1) | Хранить локальные копии (`localSnapshotEnabledTitle`, L83)<br>Как часто (`localSnapshotIntervalTitle`, L92)<br>Количество хранимых копий (`localSnapshotKeepTitle`, L99)<br>Хранить копию за прошлую неделю (`localSnapshotKeepWeekly`, L106)<br>Хранить копию за прошлый месяц (`localSnapshotKeepMonthly`, L114)<br>Лимит места (`localSnapshotMaximumTitle`, L122)<br>Уведомлять о сохранении копии (`localSnapshotAnnounceTitle`, L131)<br>Сохранить копию сейчас (`localSnapshotTakeNow`, L150)<br>{count, plural, one{{count} копия} few{{count} копии} many{{count} копий} other{{count} копии}} (`localSnapshotKeepValue`, L226)<br>Отмена (`backupPageCancel`, L569)<br>Восстановить (`localSnapshotActionRestore`, L667)<br>Экспорт (`localSnapshotActionExport`, L676)<br>Удалить (`localSnapshotActionDelete`, L685) |
| mini_apps → Рабочая область и инструменты → Мои приложения | [mini_app_page.dart:1](../../../lib/features/mini_apps/pages/mini_app_page.dart#L1) | Версии (`miniAppsVersions`, L179)<br>Сервер (`miniAppsServer`, L185)<br>Фоновые задачи (`miniAppsJobs`, L190)<br>Журнал ошибок (`miniAppsErrors`, L195)<br>На рабочий стол (`miniAppsAddToHomeScreen`, L200) |
| mini_apps → Рабочая область и инструменты → Мои приложения | [mini_app_web_page.dart:1](../../../lib/features/mini_apps/pages/mini_app_web_page.dart#L1) | Порт (`miniAppsWebPort`, L135)<br>Только этот телефон (`miniAppsWebLocalhostOnly`, L155)<br>Требовать пароль (`miniAppsWebPasswordEnabled`, L168)<br>Запускать вместе с Moru (`miniAppsWebAutostart`, L187)<br>Пароль (`miniAppsWebPassword`, L197) |
| mini_apps → Рабочая область и инструменты → Мои приложения | [mini_apps_page.dart:1](../../../lib/features/mini_apps/pages/mini_apps_page.dart#L1) | Открыть (`miniAppsOpen`, L98)<br>На рабочий стол (`miniAppsAddToHomeScreen`, L103)<br>Версии (`miniAppsVersions`, L108)<br>Сервер (`miniAppsServer`, L114)<br>Фоновые задачи (`miniAppsJobs`, L119)<br>Журнал ошибок (`miniAppsErrors`, L124)<br>Поделиться (`miniAppsShare`, L129)<br>Удалить (`miniAppsDelete`, L134) |
| quick_phrase → Чаты и ответы → Быстрые фразы | [quick_phrases_page.dart:1](../../../lib/features/quick_phrase/pages/quick_phrases_page.dart#L1) | Заголовок (`quickPhraseTitleLabel`, L394)<br>Содержимое (`quickPhraseContentLabel`, L422)<br>Отмена (`quickPhraseCancelButton`, L451)<br>Сохранить (`quickPhraseSaveButton`, L458) |
| instruction_injection → Ассистенты и агенты → Добавление инструкций | [instruction_injection_page.dart:1](../../../lib/features/instruction_injection/pages/instruction_injection_page.dart#L1) | Имя (`instructionInjectionNameLabel`, L626)<br>Группа (`instructionInjectionGroupLabel`, L653)<br>Промпт (`instructionInjectionPromptLabel`, L682)<br>Отмена (`quickPhraseCancelButton`, L711)<br>Сохранить (`quickPhraseSaveButton`, L718) |
| world_book → Ассистенты и агенты → Книга мира | [world_book_page.dart:1](../../../lib/features/world_book/pages/world_book_page.dart#L1) | Нет записей (`worldBookNoEntriesHint`, L746)<br>Имя (`worldBookNameLabel`, L1153)<br>Описание (`worldBookDescriptionLabel`, L1161)<br>Включено (`worldBookEnabledLabel`, L1171)<br>Отмена (`worldBookCancel`, L1186)<br>Сохранить (`worldBookSave`, L1193)<br>Название записи (`worldBookEntryNameLabel`, L1717)<br>Запись включена (`worldBookEntryEnabledLabel`, L1723)<br>Содержимое (`worldBookEntryContentLabel`, L1733)<br>Всегда активно (`worldBookEntryAlwaysOnLabel`, L1747)<br>Использовать регулярные выражения (`worldBookEntryUseRegexLabel`, L1883)<br>Учитывать регистр (`worldBookEntryCaseSensitiveLabel`, L1888)<br>Глубина поиска (`worldBookEntryScanDepthLabel`, L1893)<br>Место вставки (`worldBookEntryInjectionPositionLabel`, L1917)<br>Глубина вставки (`worldBookEntryInjectDepthLabel`, L1924)<br>Роль вставки (`worldBookEntryInjectionRoleLabel`, L1931)<br>По приоритету (`worldBookEntryPriorityLabel`, L1936) |

Дополнение динамических controls: MCP server create/edit содержит name, transport (SSE/Streamable HTTP/STDIO), URL/headers либо command/args/env/cwd, enabled/connect/tools и per-tool enable; ниже источник и полный SettingsProvider inventory отделяют данные MCP от глобальных prefs. Workspace selectors/environment sheets строятся custom row widgets — реестр файлов ниже сохраняет их контекст; Linux runtime, root/chroot, install/update/remove и terminal остаются Android features. DefaultModelPage cards — chat/title/summary/suggestion/compress/translate/OCR и per-chat remembered model; title/summary/suggestion/compress/translate имеют prompts и thinking toggles (`default_model_page.dart:33-248,311-809,1164-1183`). Это не только один выбор default model.

## Полный файловый реестр lib/features/*/pages

Всего 119 файлов в 19 features. Количество — файловое, а не экранное. В каждой группе ниже перечислен **каждый** файл. `part` = часть библиотеки, `layout` = альтернативная компоновка, `page/widget` = декларация основного класса; вспомогательные классы внутри файла не повторяются.

| Feature (файлов) | Все файлы и declaration line |
|---|---|
| agents (2) | [agent_detail_page.dart:30](../../../lib/features/agents/pages/agent_detail_page.dart#L30) — `AgentDetailPage`<br>[agents_page.dart:19](../../../lib/features/agents/pages/agents_page.dart#L19) — `AgentsPage` |
| assistant (16) | [assistant_regex_tab.dart:18](../../../lib/features/assistant/pages/assistant_regex_tab.dart#L18) — `AssistantRegexTab`<br>[assistant_settings_edit_basic_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_custom_request_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_custom_request_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_local_tools_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_local_tools_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_mcp_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_mcp_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_memory_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_memory_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_memory_tab_legacy.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_memory_tab_legacy.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_page.dart:267](../../../lib/features/assistant/pages/assistant_settings_edit_page.dart#L267) — `AssistantSettingsEditPage`<br>[assistant_settings_edit_prompt_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_prompt_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_quick_phrase_tab.dart:1](../../../lib/features/assistant/pages/assistant_settings_edit_quick_phrase_tab.dart#L1) — `part → assistant_settings_edit_page.dart`<br>[assistant_settings_edit_skills_tab.dart:18](../../../lib/features/assistant/pages/assistant_settings_edit_skills_tab.dart#L18) — `AssistantSettingsEditSkillsTab`<br>[assistant_settings_page.dart:19](../../../lib/features/assistant/pages/assistant_settings_page.dart#L19) — `AssistantSettingsPage`<br>[health_data_settings_desktop_layout.dart:8](../../../lib/features/assistant/pages/health_data_settings_desktop_layout.dart#L8) — `HealthDataSettingsDesktopLayout; wide layout / legacy: см. ниже`<br>[health_data_settings_mobile_layout.dart:8](../../../lib/features/assistant/pages/health_data_settings_mobile_layout.dart#L8) — `HealthDataSettingsMobileLayout`<br>[health_data_settings_page.dart:12](../../../lib/features/assistant/pages/health_data_settings_page.dart#L12) — `HealthDataSettingsPage`<br>[tags_manager_page.dart:10](../../../lib/features/assistant/pages/tags_manager_page.dart#L10) — `TagsManagerPage` |
| backup (2) | [backup_page.dart:52](../../../lib/features/backup/pages/backup_page.dart#L52) — `BackupPage`<br>[local_snapshots_page.dart:30](../../../lib/features/backup/pages/local_snapshots_page.dart#L30) — `LocalSnapshotsPage` |
| chat (4) | [chat_archive_page.dart:25](../../../lib/features/chat/pages/chat_archive_page.dart#L25) — `ChatArchivePage`<br>[chat_history_page.dart:16](../../../lib/features/chat/pages/chat_history_page.dart#L16) — `ChatHistoryPage`<br>[html_preview_page.dart:5](../../../lib/features/chat/pages/html_preview_page.dart#L5) — `HtmlPreviewPage`<br>[image_viewer_page.dart:279](../../../lib/features/chat/pages/image_viewer_page.dart#L279) — `ImageViewerPage` |
| home (3) | [home_desktop_layout.dart:26](../../../lib/features/home/pages/home_desktop_layout.dart#L26) — `HomeDesktopScaffold; wide layout / legacy: см. ниже`<br>[home_mobile_layout.dart:32](../../../lib/features/home/pages/home_mobile_layout.dart#L32) — `HomeMobileScaffold`<br>[home_page.dart:70](../../../lib/features/home/pages/home_page.dart#L70) — `HomePage` |
| instruction_injection (1) | [instruction_injection_page.dart:20](../../../lib/features/instruction_injection/pages/instruction_injection_page.dart#L20) — `InstructionInjectionPage` |
| mcp (1) | [mcp_page.dart:19](../../../lib/features/mcp/pages/mcp_page.dart#L19) — `McpPage` |
| mini_apps (3) | [mini_app_page.dart:28](../../../lib/features/mini_apps/pages/mini_app_page.dart#L28) — `MiniAppPage`<br>[mini_app_web_page.dart:21](../../../lib/features/mini_apps/pages/mini_app_web_page.dart#L21) — `MiniAppWebPage`<br>[mini_apps_page.dart:20](../../../lib/features/mini_apps/pages/mini_apps_page.dart#L20) — `MiniAppsPage` |
| model (1) | [default_model_page.dart:17](../../../lib/features/model/pages/default_model_page.dart#L17) — `DefaultModelPage` |
| provider (13) | [multi_key_manager_page.dart:21](../../../lib/features/provider/pages/multi_key_manager_page.dart#L21) — `MultiKeyManagerPage`<br>[multi_key_manager_sheets.dart:1](../../../lib/features/provider/pages/multi_key_manager_sheets.dart#L1) — `part → multi_key_manager_page.dart`<br>[multi_key_manager_widgets.dart:1](../../../lib/features/provider/pages/multi_key_manager_widgets.dart#L1) — `part → multi_key_manager_page.dart`<br>[oauth_provider_detail_page.dart:48](../../../lib/features/provider/pages/oauth_provider_detail_page.dart#L48) — `OAuthProviderDetailPage`<br>[provider_balance_page.dart:15](../../../lib/features/provider/pages/provider_balance_page.dart#L15) — `ProviderBalancePage`<br>[provider_custom_request_page.dart:11](../../../lib/features/provider/pages/provider_custom_request_page.dart#L11) — `ProviderCustomRequestPage`<br>[provider_detail_model_card.dart:1](../../../lib/features/provider/pages/provider_detail_model_card.dart#L1) — `part → provider_detail_page.dart`<br>[provider_detail_page.dart:49](../../../lib/features/provider/pages/provider_detail_page.dart#L49) — `ProviderDetailPage`<br>[provider_detail_test_dialog.dart:1](../../../lib/features/provider/pages/provider_detail_test_dialog.dart#L1) — `part → provider_detail_page.dart`<br>[provider_detail_widgets.dart:1](../../../lib/features/provider/pages/provider_detail_widgets.dart#L1) — `part → provider_detail_page.dart`<br>[provider_groups_page.dart:13](../../../lib/features/provider/pages/provider_groups_page.dart#L13) — `ProviderGroupsPage`<br>[provider_network_page.dart:11](../../../lib/features/provider/pages/provider_network_page.dart#L11) — `ProviderNetworkPage`<br>[providers_page.dart:31](../../../lib/features/provider/pages/providers_page.dart#L31) — `ProvidersPage` |
| quick_phrase (1) | [quick_phrases_page.dart:13](../../../lib/features/quick_phrase/pages/quick_phrases_page.dart#L13) — `QuickPhrasesPage` |
| scan (1) | [qr_scan_page.dart:6](../../../lib/features/scan/pages/qr_scan_page.dart#L6) — `QrScanPage` |
| scheduled_tasks (2) | [scheduled_task_editor_page.dart:49](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L49) — `ScheduledTaskEditorPage`<br>[scheduled_tasks_page.dart:37](../../../lib/features/scheduled_tasks/pages/scheduled_tasks_page.dart#L37) — `ScheduledTasksPage` |
| search (3) | [search_api_keys_page.dart:19](../../../lib/features/search/pages/search_api_keys_page.dart#L19) — `SearchApiKeysPage`<br>[search_service_editor_page.dart:21](../../../lib/features/search/pages/search_service_editor_page.dart#L21) — `SearchServiceEditorResult`<br>[search_services_page.dart:17](../../../lib/features/search/pages/search_services_page.dart#L17) — `SearchServicesPage` |
| settings (44) | [about_page.dart:22](../../../lib/features/settings/pages/about_page.dart#L22) — `AboutPage`<br>[auto_retry_page.dart:17](../../../lib/features/settings/pages/auto_retry_page.dart#L17) — `AutoRetryPage`<br>[background_overlay_settings_page.dart:25](../../../lib/features/settings/pages/background_overlay_settings_page.dart#L25) — `BackgroundOverlaySettingsPage`<br>[browser_settings_page.dart:55](../../../lib/features/settings/pages/browser_settings_page.dart#L55) — `BrowserSettingsPage`<br>[debug_page.dart:13](../../../lib/features/settings/pages/debug_page.dart#L13) — `DebugPage`<br>[display_behavior_page.dart:1](../../../lib/features/settings/pages/display_behavior_page.dart#L1) — `part → display_settings_page.dart`<br>[display_chat_item_page.dart:1](../../../lib/features/settings/pages/display_chat_item_page.dart#L1) — `part → display_settings_page.dart`<br>[display_haptics_page.dart:1](../../../lib/features/settings/pages/display_haptics_page.dart#L1) — `part → display_settings_page.dart`<br>[display_rendering_page.dart:1](../../../lib/features/settings/pages/display_rendering_page.dart#L1) — `part → display_settings_page.dart`<br>[display_settings_page.dart:37](../../../lib/features/settings/pages/display_settings_page.dart#L37) — `DisplaySettingsPage`<br>[display_settings_widgets.dart:1](../../../lib/features/settings/pages/display_settings_widgets.dart#L1) — `part → display_settings_page.dart`<br>[glass_theme_settings_page.dart:16](../../../lib/features/settings/pages/glass_theme_settings_page.dart#L16) — `GlassThemeSettingsPage`<br>[google_fonts_picker_page.dart:34](../../../lib/features/settings/pages/google_fonts_picker_page.dart#L34) — `GoogleFontsPickerPage`<br>[image_settings_page.dart:14](../../../lib/features/settings/pages/image_settings_page.dart#L14) — `ImageSettingsPage`<br>[legacy_memory_page.dart:29](../../../lib/features/settings/pages/legacy_memory_page.dart#L29) — `LegacyMemoryPage`<br>[log_viewer_page.dart:29](../../../lib/features/settings/pages/log_viewer_page.dart#L29) — `LogViewerPage`<br>[memory_about_page.dart:9](../../../lib/features/settings/pages/memory_about_page.dart#L9) — `MemoryAboutPage`<br>[memory_entries_page.dart:15](../../../lib/features/settings/pages/memory_entries_page.dart#L15) — `MemoryEntriesPage`<br>[memory_settings_page.dart:32](../../../lib/features/settings/pages/memory_settings_page.dart#L32) — `MemorySettingsPage`<br>[memory_trace_page.dart:22](../../../lib/features/settings/pages/memory_trace_page.dart#L22) — `MemoryTracePage`<br>[message_style_preview.dart:1](../../../lib/features/settings/pages/message_style_preview.dart#L1) — `part → message_style_settings_page.dart`<br>[message_style_rows.dart:1](../../../lib/features/settings/pages/message_style_rows.dart#L1) — `part → message_style_settings_page.dart`<br>[message_style_settings_page.dart:29](../../../lib/features/settings/pages/message_style_settings_page.dart#L29) — `MessageStyleSettingsPage`<br>[mobile_background_settings_page.dart:18](../../../lib/features/settings/pages/mobile_background_settings_page.dart#L18) — `MobileBackgroundSettingsPage`<br>[more_page.dart:5](../../../lib/features/settings/pages/more_page.dart#L5) — `MorePage`<br>[network_proxy_page.dart:18](../../../lib/features/settings/pages/network_proxy_page.dart#L18) — `NetworkProxyPage`<br>[phone_control_settings_page.dart:14](../../../lib/features/settings/pages/phone_control_settings_page.dart#L14) — `PhoneControlSettingsPage`<br>[settings_page.dart:43](../../../lib/features/settings/pages/settings_page.dart#L43) — `SettingsPage`<br>[settings_search_page.dart:171](../../../lib/features/settings/pages/settings_search_page.dart#L171) — `SettingsSearchPage`<br>[sponsor_page.dart:13](../../../lib/features/settings/pages/sponsor_page.dart#L13) — `SponsorPage`<br>[storage_category_page.dart:1](../../../lib/features/settings/pages/storage_category_page.dart#L1) — `part → storage_space_page.dart`<br>[storage_space_page.dart:44](../../../lib/features/settings/pages/storage_space_page.dart#L44) — `StorageSpacePage`<br>[storage_space_widgets.dart:1](../../../lib/features/settings/pages/storage_space_widgets.dart#L1) — `part → storage_space_page.dart`<br>[storage_upload_manager.dart:1](../../../lib/features/settings/pages/storage_upload_manager.dart#L1) — `part → storage_space_page.dart`<br>[theme_advanced_settings_page.dart:12](../../../lib/features/settings/pages/theme_advanced_settings_page.dart#L12) — `ThemeAdvancedSettingsPage`<br>[theme_settings_page.dart:16](../../../lib/features/settings/pages/theme_settings_page.dart#L16) — `ThemeSettingsPage`<br>[tool_schema_editor_page.dart:9](../../../lib/features/settings/pages/tool_schema_editor_page.dart#L9) — `ToolSchemaEditorPage`<br>[tool_schema_settings_page.dart:16](../../../lib/features/settings/pages/tool_schema_settings_page.dart#L16) — `ToolSchemaSettingsPage`<br>[tts_network_editor.dart:1](../../../lib/features/settings/pages/tts_network_editor.dart#L1) — `part → tts_services_page.dart`<br>[tts_network_list.dart:1](../../../lib/features/settings/pages/tts_network_list.dart#L1) — `part → tts_services_page.dart`<br>[tts_services_page.dart:26](../../../lib/features/settings/pages/tts_services_page.dart#L26) — `TtsServicesPage`<br>[tts_settings_page.dart:14](../../../lib/features/settings/pages/tts_settings_page.dart#L14) — `TtsSettingsPage`<br>[tts_system_config_sheet.dart:1](../../../lib/features/settings/pages/tts_system_config_sheet.dart#L1) — `part → tts_services_page.dart`<br>[user_profile_page.dart:19](../../../lib/features/settings/pages/user_profile_page.dart#L19) — `UserProfilePage` |
| stats (1) | [stats_page.dart:30](../../../lib/features/stats/pages/stats_page.dart#L30) — `StatsPage` |
| translate (1) | [translate_page.dart:22](../../../lib/features/translate/pages/translate_page.dart#L22) — `TranslatePage` |
| workspace (19) | [environment_download_page.dart:33](../../../lib/features/workspace/pages/environment_download_page.dart#L33) — `EnvironmentDownloadPage`<br>[environment_page.dart:15](../../../lib/features/workspace/pages/environment_page.dart#L15) — `EnvironmentPage`<br>[environment_page_desktop_layout.dart:9](../../../lib/features/workspace/pages/environment_page_desktop_layout.dart#L9) — `EnvironmentPageDesktopLayout; wide layout / legacy: см. ниже`<br>[environment_page_mobile_layout.dart:9](../../../lib/features/workspace/pages/environment_page_mobile_layout.dart#L9) — `EnvironmentPageMobileLayout`<br>[environment_variables_page.dart:41](../../../lib/features/workspace/pages/environment_variables_page.dart#L41) — `EnvironmentVariablesPage`<br>[external_mounts_page.dart:73](../../../lib/features/workspace/pages/external_mounts_page.dart#L73) — `ExternalMountsPage`<br>[mirror_page.dart:21](../../../lib/features/workspace/pages/mirror_page.dart#L21) — `MirrorPage`<br>[proot_options_page.dart:12](../../../lib/features/workspace/pages/proot_options_page.dart#L12) — `ProotOptionsPage`<br>[rootfs_browser_page.dart:22](../../../lib/features/workspace/pages/rootfs_browser_page.dart#L22) — `RootfsBrowserPage`<br>[skills_page.dart:15](../../../lib/features/workspace/pages/skills_page.dart#L15) — `SkillsPage`<br>[skills_page_desktop_layout.dart:10](../../../lib/features/workspace/pages/skills_page_desktop_layout.dart#L10) — `SkillsPageDesktopLayout; wide layout / legacy: см. ниже`<br>[skills_page_mobile_layout.dart:10](../../../lib/features/workspace/pages/skills_page_mobile_layout.dart#L10) — `SkillsPageMobileLayout`<br>[workspace_files_desktop_layout.dart:22](../../../lib/features/workspace/pages/workspace_files_desktop_layout.dart#L22) — `WorkspaceFilesDesktopLayout; wide layout / legacy: см. ниже`<br>[workspace_files_mobile_layout.dart:18](../../../lib/features/workspace/pages/workspace_files_mobile_layout.dart#L18) — `WorkspaceFilesMobileLayout`<br>[workspace_files_page.dart:11](../../../lib/features/workspace/pages/workspace_files_page.dart#L11) — `WorkspaceFilesPage`<br>[workspace_settings_page.dart:21](../../../lib/features/workspace/pages/workspace_settings_page.dart#L21) — `WorkspaceSettingsPage`<br>[workspaces_desktop_layout.dart:7](../../../lib/features/workspace/pages/workspaces_desktop_layout.dart#L7) — `WorkspacesDesktopLayout; wide layout / legacy: см. ниже`<br>[workspaces_mobile_layout.dart:7](../../../lib/features/workspace/pages/workspaces_mobile_layout.dart#L7) — `WorkspacesMobileLayout`<br>[workspaces_page.dart:85](../../../lib/features/workspace/pages/workspaces_page.dart#L85) — `WorkspacesPage` |
| world_book (1) | [world_book_page.dart:24](../../../lib/features/world_book/pages/world_book_page.dart#L24) — `WorldBookPage` |

### Android/mobile и legacy nonmobile — не смешивать

| Семейство | Что реально видно в коде | Решение для v2 |
|---|---|---|
| Home | `HomeDesktopScaffold` в `home_desktop_layout.dart:26`; AGENTS явно сохраняет его для wide Android | Адаптация планшета/landscape остаётся Android scope |
| Workspace/environment/skills/health | `*_mobile_layout.dart` и `*_desktop_layout.dart` перечислены выше; часть страниц chooses dialogs/layouts по platform | Сначала mobile path; широкие Android layouts оценивать по реальному caller, не удалять по имени |
| Assistant regex | `AssistantRegexTab:18`, `AssistantRegexDesktopPane:217` в одном файле | Mobile controls сохранить; desktop pane legacy audit |
| ASR widgets | `asr_service_editor.dart:10` desktop sheet, `:32` mobile page; карты имеют `_buildDesktop:142` | В v2 — mobile route, schema/values общие |
| Scheduled tasks | Страницы сохраняют isDesktop branches; Android entry conditional в settings root | Android native scheduler/permissions сохраняются |
| Settings display/theme | Нет отдельной desktop оболочки; названия Ios* означают shared widgets, не iOS target | Все перечисленные mobile настройки доступны Android |
| SettingsProvider prefs с desktop* в имени | `desktopSendShortcut` действует на широком Android/hardware keyboard; `desktopMessageNavButtonsMode` сохранён без production-потребителя | Проверять реальный caller и width/platform условие; не выводить nonmobile-статус из имени |

## Выводы для новой структуры

1. Display сейчас смешивает тему, message rendering, chat behavior, retry, язык, haptics и background. Для поиска и discoverability нужны разные новые владельцы; детальные параметры сохраняются на вложенных страницах.
2. Voice root называется «Синтез речи», хотя содержит ASR. В новом разделе «Голос» два понятных направления: озвучивание и распознавание.
3. Подключения — это provider config, subscription/OAuth и multi-key state; нельзя заменить всё одиночным API-key field. MCP, search и network overrides тоже отдельные модели.
4. Память имеет global и per-assistant настройки, legacy/current режимы, prompts/profile/entries/trace. Migration и debug — редкие, но реальные пользовательские операции.
5. Tool full trust и browser action toggles находятся в разных местах; в разделе инструментов нужен явный общий путь к permission policy и доступным browser actions.
6. Runtime status, read-only info, editor action и persistent preference в этом аудите различаются. Новая IA не должна превращать показанный статус в выдуманный переключатель.

## Дополнение: вложенные параметры других providers

Цветовой режим в корне имеет три значения: Системная / Светлая / Тёмная (`settingsPageSystemMode`, `settingsPageLightMode`, `settingsPageDarkMode`; `settings_page.dart:82-103`) → «Внешний вид → Режим». PhoneControl refresh/native restricted-settings action (`phone_control_settings_page.dart:156,206-214`) сохраняются. Кнопка включения ассистента видна только при `requestEnable`, возвращает `true` вызывающему редактору (`:87-89`); сам экран не записывает настройку ассистента.

| Было: точный label / key | Объект / значение | Источник | Стало |
|---|---|---|---|
| Включено · `mcpServerEditSheetEnabledLabel` | `McpServerConfig.enabled` | [mcp_server_edit_sheet.dart:201](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L201) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Имя · `mcpServerEditSheetNameLabel` | `McpServerConfig.name` | [mcp_server_edit_sheet.dart:218](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L218) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Транспорт · `mcpServerEditSheetTransportLabel` | `McpTransport` | [mcp_server_edit_sheet.dart:244](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L244) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Команда · `mcpServerEditSheetStdioCommandLabel` | `command` | [mcp_server_edit_sheet.dart:256](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L256) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Рабочий каталог (необязательно) · `mcpServerEditSheetStdioWorkingDirectoryLabel` | `workingDirectory` | [mcp_server_edit_sheet.dart:265](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L265) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Аргументы · `mcpServerEditSheetStdioArgumentsLabel` | `args[]` | [mcp_server_edit_sheet.dart:315](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L315) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| URL сервера · `mcpServerEditSheetUrlLabel` | `url` | [mcp_server_edit_sheet.dart:287](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L287) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Имя · `mcpServerEditSheetStdioEnvNameLabel` | `env key` | [mcp_server_edit_sheet.dart:380](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L380) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Значение · `mcpServerEditSheetStdioEnvValueLabel` | `env value` | [mcp_server_edit_sheet.dart:391](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L391) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Имя заголовка · `mcpServerEditSheetHeaderNameLabel` | `headers name` | [mcp_server_edit_sheet.dart:381](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L381) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Значение заголовка · `mcpServerEditSheetHeaderValueLabel` | `headers value` | [mcp_server_edit_sheet.dart:392](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L392) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Импортировать из окружения · `mcpImportEnvironment` | `import environment vars — операция` | [mcp_server_edit_sheet.dart:282](../../../lib/features/mcp/widgets/mcp_server_edit_sheet.dart#L282) | Модели и подключения → Дополнительно → MCP → Сервер → Подключение |
| Привязать рабочее пространство (необязательно) · `mcpWorkspaceBindingLabel` | `McpServerConfig.workspaceId` | [mcp_workspace_binding_field.dart:41](../../../lib/features/mcp/widgets/mcp_workspace_binding_field.dart#L41) | Модели и подключения → Дополнительно → MCP → Сервер → Рабочая область |
| Тайм-аут вызова инструмента (секунды) · `mcpTimeoutSecondsLabel` | `McpProvider.requestTimeout; mcp_request_timeout_ms_v1` | [mcp_timeout_sheet.dart:75](../../../lib/features/mcp/widgets/mcp_timeout_sheet.dart#L75) | Модели и подключения → Дополнительно → MCP → Дополнительно → Тайм-аут |
| Дата · `scheduledTasksDate` | `ScheduledTask.onceDate` | [scheduled_task_editor_page.dart:569](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L569) | Рабочая область и инструменты → Задачи по расписанию → Задача |
| Дата начала · `scheduledTasksStartDate` | `ScheduledTask.startDate` | [scheduled_task_editor_page.dart:582](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L582) | Рабочая область и инструменты → Задачи по расписанию → Задача |
| Дата окончания · `scheduledTasksEndDate` | `ScheduledTask.endDate` | [scheduled_task_editor_page.dart:588](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L588) | Рабочая область и инструменты → Задачи по расписанию → Задача |
| Уведомления о результате · `scheduledTasksNotify` | `ScheduledTask.notify` | [scheduled_task_editor_page.dart:660](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L660) | Рабочая область и инструменты → Задачи по расписанию → Задача |
| Показывать текст результата в уведомлении · `scheduledTasksShowPreview` | `ScheduledTask.showPreview` | [scheduled_task_editor_page.dart:668](../../../lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart#L668) | Рабочая область и инструменты → Задачи по расписанию → Задача |
| Просмотр файловой системы · `workspaceEnvBrowseFiles` | `EnvironmentProvider / runtime operation` | [environment_pane.dart:464](../../../lib/features/workspace/widgets/environment/environment_pane.dart#L464) | Рабочая область и инструменты → Linux-среда → Дополнительно |
| Переменные окружения · `workspaceEnvVariablesTitle` | `EnvironmentProvider / runtime operation` | [environment_pane.dart:596](../../../lib/features/workspace/widgets/environment/environment_pane.dart#L596) | Рабочая область и инструменты → Linux-среда → Дополнительно |
| Заменить систему · `workspaceEnvReplaceSystem` | `EnvironmentProvider / runtime operation` | [environment_pane.dart:247](../../../lib/features/workspace/widgets/environment/environment_pane.dart#L247) | Рабочая область и инструменты → Linux-среда → Дополнительно |
| Найти быстрые зеркала · `workspaceEnvDetectFastMirrors` | `EnvironmentProvider / runtime operation` | [environment_pane.dart:1026](../../../lib/features/workspace/widgets/environment/environment_pane.dart#L1026) | Рабочая область и инструменты → Linux-среда → Дополнительно |

MCP хранится отдельно: `mcp_servers_v1` и `mcp_request_timeout_ms_v1` объявлены в `lib/core/providers/mcp_provider.dart:350-351`. Отдельные действия — импорт JSON, connect/disconnect, OAuth sign-in, details/errors, удалить/undo (`mcp_page.dart:79-113,355-386,449-496`), tools enable/disable через связанные widgets — сохраняются в editor. STDIO рабочая область, переменные и PRoot — Android функции. В расписании custom repeat имеет weekday selector (`scheduled_task_editor_page.dart:558-564`), once имеет дату, повторяемое — start/end dates; notify и showPreview отделены от глобальных background preferences.

## Полный справочник SettingsProvider и подключений

Репозиторий: `/workspace/Moru`; `SP:N` означает `lib/core/providers/settings_provider.dart:N`. Указаны точные ключи хранения, методы чтения и записи, включая составные свойства. Основное хранилище — SQLite `BusinessPreferences` (SP:802/SP:807); `display_chat_font_scale_v1` (SP:5119) и `flutter_log_enabled_v1` (SP:5643) используют локальный `SharedPreferences`. Доступность настроек проверена по обращениям в `lib/features`; поиск записывает несколько полей через `updateSettings(copyWith(...))` (SP:5762). Группировка ключей ниже служит инвентарём хранения и навигационной подсказкой; для отдельных appearance/sidebar параметров она шире окончательной IA. Авторитетный новый маршрут каждого пользовательского пункта — столбец «Стало: путь» в подробных таблицах выше и корневая карта README. Служебные и legacy ключи не становятся новыми строками Android UI.

Всего объявлено 200 ключей хранения. Константы-маркеры `retiredLocalModelProviderKey`, `providerUngroupedGroupKey`, значения по умолчанию и встроенные ID провайдеров не входят в счёт. Дополнительный старый ключ `theme_custom_surface_v1` удаляется при миграции (SP:2861).

### Внешний вид

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `display_enable_dollar_latex_v1` (`_displayEnableDollarLatexKey`, SP:276) | `enableDollarLatex:5205` | `setEnableDollarLatex:5206` | настройка Android |
| `display_enable_math_rendering_v1` (`_displayEnableMathRenderingKey`, SP:278) | `enableMathRendering:5216` | `setEnableMathRendering:5217` | настройка Android |
| `display_enable_user_markdown_v1` (`_displayEnableUserMarkdownKey`, SP:280) | `enableUserMarkdown:5227` | `setEnableUserMarkdown:5228` | настройка Android |
| `display_enable_reasoning_markdown_v1` (`_displayEnableReasoningMarkdownKey`, SP:282) | `enableReasoningMarkdown:5238` | `setEnableReasoningMarkdown:5239` | настройка Android |
| `display_enable_assistant_markdown_v1` (`_displayEnableAssistantMarkdownKey`, SP:284) | `enableAssistantMarkdown:5249` | `setEnableAssistantMarkdown:5250` | настройка Android |
| `display_mobile_code_block_wrap_v1` (`_displayMobileCodeBlockWrapKey`, SP:298) | `mobileCodeBlockWrap:5384` | `setMobileCodeBlockWrap:5385` | настройка Android |
| `display_auto_collapse_code_block_v1` (`_displayAutoCollapseCodeBlockKey`, SP:300) | `autoCollapseCodeBlock:5395` | `setAutoCollapseCodeBlock:5396` | настройка Android |
| `display_auto_collapse_code_block_lines_v1` (`_displayAutoCollapseCodeBlockLinesKey`, SP:302) | `autoCollapseCodeBlockLines:5406` | `setAutoCollapseCodeBlockLines:5407` | настройка Android |
| `theme_mode_v1` (`_themeModeKey`, SP:100) | `themeMode:492` | `setThemeMode:2656` | настройка Android |
| `theme_palette_v1` (`_themePaletteKey`, SP:125) | `themePaletteId:495` | `setThemePalette:2668` | настройка Android |
| `use_dynamic_color_v1` (`_useDynamicColorKey`, SP:126) | `useDynamicColor:497` | `setUseDynamicColor:2676` | настройка Android |
| `custom_themes_v1` (`_customThemesKey`, SP:127) | `customThemes:503` | `saveCustomTheme:2881`<br>`deleteCustomTheme:2899`<br>`importCustomTheme:2935` | настройка Android |
| `custom_theme_selected_v1` (`_customThemeSelectedKey`, SP:128) | `selectedCustomThemeId:506`<br>`selectedCustomTheme:507` | `selectCustomTheme:2919` | настройка Android |
| `theme_custom_seed_v1` (`_legacyCustomSeedColorKey`, SP:130) | — | — | только миграция старых данных |
| `theme_custom_primary_v1` (`_legacyCustomPrimaryOverrideKey`, SP:131) | — | — | только миграция старых данных |
| `display_chat_font_scale_v1` (`_displayChatFontScaleKey`, SP:265) | `chatFontScale:5113` | `setChatFontScale:5114` | настройка Android |
| `display_chat_background_mask_strength_v1` (`_displayChatBackgroundMaskStrengthKey`, SP:270) | `chatBackgroundMaskStrength:5151` | `setChatBackgroundMaskStrength:5152` | настройка Android |
| `display_chat_input_background_opacity_light_v1` (`_displayChatInputBackgroundOpacityLightKey`, SP:272) | `chatInputBackgroundOpacityLight:5171` | `setChatInputBackgroundOpacity:5181` | настройка Android |
| `display_chat_input_background_opacity_dark_v1` (`_displayChatInputBackgroundOpacityDarkKey`, SP:274) | `chatInputBackgroundOpacityDark:5173` | `setChatInputBackgroundOpacity:5181` | настройка Android |
| `display_use_pure_background_v1` (`_displayUsePureBackgroundKey`, SP:308) | `usePureBackground:518` | `setUsePureBackground:2684` | настройка Android |
| `display_use_layered_surfaces_v1` (`_displayUseLayeredSurfacesKey`, SP:310) | `useLayeredSurfaces:522` | `setUseLayeredSurfaces:2692` | настройка Android |
| `display_use_layered_sheet_tiles_v1` (`_displayUseLayeredSheetTilesKey`, SP:312) | `useLayeredSheetTiles:526` | `setUseLayeredSheetTiles:2816` | настройка Android |
| `display_glass_theme_v1` (`_displayGlassThemeKey`, SP:318) | `glassTheme:540` | `setGlassTheme:2718` | настройка Android |
| `display_glass_restore_v1` (`_displayGlassRestoreKey`, SP:319) | — | `setGlassTheme:2718` | служебный снимок для восстановления стеклянной темы |
| `display_glass_economy_v1` (`_displayGlassEconomyKey`, SP:320) | `glassEconomy:544` | `setGlassEconomy:2809` | настройка Android |
| `display_chat_message_background_style_v1` (`_displayChatMessageBackgroundStyleKey`, SP:321) | `chatMessageBackgroundStyle:2946` | `setChatMessageBackgroundStyle:2948` | настройка Android |
| `chat_bubble_style_overrides_v1` (`_chatBubbleStyleOverridesKey`, SP:323) | `chatBubbleStyleOverrides:2966`<br>`assistantChatBubbleStyleOverrides:2968` | `setChatBubbleStyleOverrides:2976`<br>`setChatBubbleStyleOverridesForRole:2994` | настройка Android |
| `chat_bubble_style_overrides_user_v1` (`_userChatBubbleStyleOverridesKey`, SP:325) | `userChatBubbleStyleOverrides:2970` | `setChatBubbleStyleOverrides:2976`<br>`setChatBubbleStyleOverridesForRole:2994` | настройка Android |
| `display_app_font_family_v1` (`_displayAppFontFamilyKey`, SP:351) | `appFontFamily:1830` | `setAppFontSystemFamily:1841`<br>`setAppFontFromLocal:1872`<br>`clearAppFont:1934` | настройка Android |
| `display_code_font_family_v1` (`_displayCodeFontFamilyKey`, SP:352) | `codeFontFamily:1831` | `setCodeFontSystemFamily:1857`<br>`setCodeFontFromLocal:1903`<br>`clearCodeFont:1947` | настройка Android |
| `display_app_font_is_google_v1` (`_legacyAppFontIsGoogleKey`, SP:355) | — | — | только миграция старых данных |
| `display_code_font_is_google_v1` (`_legacyCodeFontIsGoogleKey`, SP:357) | — | — | только миграция старых данных |
| `display_app_font_local_path_v1` (`_displayAppFontLocalPathKey`, SP:359) | `appFontFamily:1830`<br>`appFontLocalAlias:1832` | `setAppFontSystemFamily:1841`<br>`setAppFontFromLocal:1872`<br>`clearAppFont:1934` | настройка Android |
| `display_code_font_local_path_v1` (`_displayCodeFontLocalPathKey`, SP:361) | `codeFontFamily:1831`<br>`codeFontLocalAlias:1833` | `setCodeFontSystemFamily:1857`<br>`setCodeFontFromLocal:1903`<br>`clearCodeFont:1947` | настройка Android |
| `display_app_font_local_alias_v1` (`_displayAppFontLocalAliasKey`, SP:363) | `appFontLocalAlias:1832` | `setAppFontSystemFamily:1841`<br>`setAppFontFromLocal:1872`<br>`clearAppFont:1934` | служебный псевдоним выбранного шрифта |
| `display_code_font_local_alias_v1` (`_displayCodeFontLocalAliasKey`, SP:365) | `codeFontLocalAlias:1833` | `setCodeFontSystemFamily:1857`<br>`setCodeFontFromLocal:1903`<br>`clearCodeFont:1947` | служебный псевдоним выбранного шрифта |

### Модели и подключения

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `providers_order_v1` (`_providersOrderKey`, SP:70) | `providersOrder:453` | `setProvidersOrder:2301`<br>`moveProvider:2630` | настройка Android |
| `provider_groups_v1` (`_providerGroupsKey`, SP:71) | `providerGroups:463` | `createGroup:2428`<br>`renameGroup:2451`<br>`reorderProviderGroups:2473`<br>`reorderProviderGroupsWithUngrouped:2490`<br>`deleteGroup:2514` | настройка Android |
| `provider_group_map_v1` (`_providerGroupMapKey`, SP:73) | `groupIdForProvider:474`<br>`providerGroupingActive:480` | `setProviderGroup:2535`<br>`moveProvidersToGroup:2555`<br>`moveProvider:2630` | настройка Android |
| `provider_group_collapsed_v1` (`_providerGroupCollapsedKey`, SP:75) | `isGroupCollapsed:488` | `setGroupCollapsed:2612`<br>`toggleGroupCollapsed:2624` | сохранённая свёрнутость групп |
| `provider_ungrouped_position_v1` (`_providerUngroupedPositionKey`, SP:77) | `providerUngroupedDisplayIndex:464` | `reorderProviderGroupsWithUngrouped:2490` | настройка Android |
| `provider_configs_v1` (`_providerConfigsKey`, SP:101) | `providerConfigs:547`<br>`getProviderConfig:553` | `setProviderConfig:3243` | настройка Android |
| `pinned_models_v1` (`_pinnedModelsKey`, SP:102) | `pinnedModels:3621`<br>`isModelPinned:3622` | `togglePinModel:3624` | настройка Android |
| `selected_model_v1` (`_selectedModelKey`, SP:103) | `currentModelProvider:3639`<br>`currentModelId:3640`<br>`currentModelKey:3641` | `setCurrentModel:3645`<br>`resetCurrentModel:3653` | настройка Android |
| `global_proxy_enabled_v1` (`_globalProxyEnabledKey`, SP:391) | `globalProxyEnabled:779` | `setGlobalProxyEnabled:1622` | настройка Android |
| `global_proxy_type_v1` (`_globalProxyTypeKey`, SP:392) | `globalProxyType:780` | `setGlobalProxyType:1629` | настройка Android |
| `global_proxy_host_v1` (`_globalProxyHostKey`, SP:394) | `globalProxyHost:781` | `setGlobalProxyHost:1636` | настройка Android |
| `global_proxy_port_v1` (`_globalProxyPortKey`, SP:395) | `globalProxyPort:782` | `setGlobalProxyPort:1643` | настройка Android |
| `global_proxy_username_v1` (`_globalProxyUsernameKey`, SP:396) | `globalProxyUsername:783` | `setGlobalProxyUsername:1650` | настройка Android |
| `global_proxy_password_v1` (`_globalProxyPasswordKey`, SP:397) | `globalProxyPassword:784` | `setGlobalProxyPassword:1657` | настройка Android |
| `global_proxy_bypass_v1` (`_globalProxyBypassKey`, SP:398) | `globalProxyBypass:785` | `setGlobalProxyBypass:1668` | настройка Android |
| `search_services_v1` (`_searchServicesKey`, SP:374) | `searchServices:716` | `setSearchServices:5714` | настройка Android |
| `search_common_v1` (`_searchCommonKey`, SP:375) | `searchCommonOptions:719` | `setSearchCommonOptions:5730` | настройка Android |
| `search_selected_v1` (`_searchSelectedKey`, SP:376) | `searchServiceSelected:721` | `setSearchServices:5714`<br>`setSearchServiceSelected:5737` | настройка Android |
| `search_enabled_v1` (`_searchEnabledKey`, SP:377) | `searchEnabled:723` | `setSearchEnabled:5747` | скрытый старый общий поиск; интерфейс использует Assistant.searchEnabled |
| `search_auto_test_on_launch_v1` (`_searchAutoTestOnLaunchKey`, SP:378) | `searchAutoTestOnLaunch:725` | `setSearchAutoTestOnLaunch:5754` | настройка Android |

### Чаты и ответы

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `display_use_new_assistant_avatar_ux_v1` (`_displayUseNewAssistantAvatarUxKey`, SP:225) | `useNewAssistantAvatarUx:4875` | `setUseNewAssistantAvatarUx:4876` | настройка Android |
| `auto_retry_options` (`_autoRetryOptionsKey`, SP:401) | `autoRetryOptions:788` | `setAutoRetryOptions:1675` | настройка Android |
| `display_mobile_message_nav_buttons_mode_v1` (`_displayMobileMessageNavButtonsModeKey`, SP:223) | `mobileMessageNavButtonsMode:5064` | `setMobileMessageNavButtonsMode:5067` | настройка Android |
| `per_chat_model_enabled_v1` (`_perChatModelEnabledKey`, SP:104) | `perChatModelEnabled:3666` | `setPerChatModelEnabled:3668` | настройка Android |
| `title_model_v1` (`_titleModelKey`, SP:105) | `titleModelProvider:3680`<br>`titleModelId:3681`<br>`titleModelKey:3682` | `setTitleModel:3705`<br>`resetTitleModel:3715`<br>`disableTitleGeneration:3725` | настройка Android |
| `title_generation_enabled_v1` (`_titleGenerationEnabledKey`, SP:106) | `isTitleGenerationEnabled:3687` | `setTitleModel:3705`<br>`resetTitleModel:3715`<br>`disableTitleGeneration:3725` | настройка Android |
| `title_prompt_v1` (`_titlePromptKey`, SP:108) | `titlePrompt:3703` | `setTitlePrompt:3735`<br>`resetTitlePrompt:3742` | настройка Android |
| `ocr_model_v1` (`_ocrModelKey`, SP:109) | `ocrModelProvider:3812`<br>`ocrModelId:3813`<br>`ocrModelKey:3814` | `setOcrModel:3838`<br>`resetOcrModel:3846` | настройка Android |
| `ocr_prompt_v1` (`_ocrPromptKey`, SP:110) | `ocrPrompt:3833` | `setOcrPrompt:3856`<br>`resetOcrPrompt:3863` | настройка Android |
| `summary_model_v1` (`_summaryModelKey`, SP:111) | `summaryModelProvider:3880`<br>`summaryModelId:3881`<br>`summaryModelKey:3882` | `setSummaryModel:3908`<br>`resetSummaryModel:3916` | настройка Android |
| `summary_prompt_v1` (`_summaryPromptKey`, SP:112) | `summaryPrompt:3906` | `setSummaryPrompt:3924`<br>`resetSummaryPrompt:3931` | настройка Android |
| `suggestion_model_v1` (`_suggestionModelKey`, SP:113) | `suggestionModelProvider:3939`<br>`suggestionModelId:3940`<br>`suggestionModelKey:3942` | `setSuggestionModel:3968`<br>`resetSuggestionModel:3978`<br>`disableSuggestionGeneration:3988` | настройка Android |
| `suggestion_generation_enabled_v1` (`_suggestionGenerationEnabledKey`, SP:114) | `isSuggestionGenerationEnabled:3941` | `setSuggestionModel:3968`<br>`resetSuggestionModel:3978`<br>`disableSuggestionGeneration:3988` | настройка Android |
| `suggestion_prompt_v1` (`_suggestionPromptKey`, SP:116) | `suggestionPrompt:3964` | `setSuggestionPrompt:3998`<br>`resetSuggestionPrompt:4007` | настройка Android |
| `suggestion_insert_on_tap_only_v1` (`_suggestionInsertOnTapOnlyKey`, SP:117) | `insertSuggestionOnTapOnly:3966` | `setInsertSuggestionOnTapOnly:4010` | настройка Android |
| `compress_model_v1` (`_compressModelKey`, SP:119) | `compressModelProvider:4021`<br>`compressModelId:4022`<br>`compressModelKey:4023` | `setCompressModel:4062`<br>`resetCompressModel:4070` | настройка Android |
| `compress_prompt_v1` (`_compressPromptKey`, SP:120) | `compressPrompt:4051` | `setCompressPrompt:4078`<br>`resetCompressPrompt:4085` | настройка Android |
| `compress_limit_mode_v1` (`_compressLimitModeKey`, SP:121) | `compressLimitMode:4054` | `setCompressLimitMode:4088` | настройка Android |
| `compress_keep_user_messages_v1` (`_compressKeepUserMessagesKey`, SP:122) | `compressKeepUserMessages:4057` | `setCompressKeepUserMessages:4095` | настройка Android |
| `compress_max_chars_v1` (`_compressMaxCharsKey`, SP:124) | `compressMaxChars:4060` | `setCompressMaxChars:4106` | настройка Android |
| `thinking_budget_v1` (`_thinkingBudgetKey`, SP:133) | `thinkingBudget:4144` | `setThinkingBudget:4145` | настройка Android |
| `title_generation_thinking_enabled_v1` (`_titleGenerationThinkingEnabledKey`, SP:134) | `titleGenerationThinkingEnabled:4159` | `setTitleGenerationThinkingEnabled:4160`<br>`resetTitleGenerationThinkingEnabled:4168` | настройка Android |
| `summary_generation_thinking_enabled_v1` (`_summaryGenerationThinkingEnabledKey`, SP:136) | `summaryGenerationThinkingEnabled:4172` | `setSummaryGenerationThinkingEnabled:4174`<br>`resetSummaryGenerationThinkingEnabled:4181` | настройка Android |
| `suggestion_generation_thinking_enabled_v1` (`_suggestionGenerationThinkingEnabledKey`, SP:138) | `suggestionGenerationThinkingEnabled:4185` | `setSuggestionGenerationThinkingEnabled:4187`<br>`resetSuggestionGenerationThinkingEnabled:4197` | настройка Android |
| `compress_generation_thinking_enabled_v1` (`_compressGenerationThinkingEnabledKey`, SP:140) | `compressGenerationThinkingEnabled:4201` | `setCompressGenerationThinkingEnabled:4203`<br>`resetCompressGenerationThinkingEnabled:4210` | настройка Android |
| `translate_generation_thinking_enabled_v1` (`_translateGenerationThinkingEnabledKey`, SP:142) | `translateGenerationThinkingEnabled:4214` | `setTranslateGenerationThinkingEnabled:4216`<br>`resetTranslateGenerationThinkingEnabled:4223` | настройка Android |
| `ocr_generation_thinking_enabled_v1` (`_ocrGenerationThinkingEnabledKey`, SP:144) | `ocrGenerationThinkingEnabled:4227` | `setOcrGenerationThinkingEnabled:4228`<br>`resetOcrGenerationThinkingEnabled:4235` | настройка Android |
| `display_show_user_avatar_v1` (`_displayShowUserAvatarKey`, SP:184) | `showUserAvatar:4643` | `setShowUserAvatar:4644` | настройка Android |
| `display_show_model_icon_v1` (`_displayShowModelIconKey`, SP:185) | `showModelIcon:4696` | `setShowModelIcon:4697` | настройка Android |
| `display_show_model_name_timestamp_v1` (`_displayShowModelNameTimestampKey`, SP:186) | `showModelNameTimestamp:4707` | `setShowModelNameTimestamp:4708` | совместимость; интерфейс меняет отдельные showModelName/showModelTimestamp |
| `display_show_token_stats_v1` (`_displayShowTokenStatsKey`, SP:188) | `showTokenStats:4740` | `setShowTokenStats:4741` | настройка Android |
| `display_show_user_name_timestamp_v1` (`_displayShowUserNameTimestampKey`, SP:189) | `showUserNameTimestamp:4654` | `setShowUserNameTimestamp:4655` | совместимость; интерфейс меняет отдельные showUserName/showUserTimestamp |
| `display_show_user_name_v1` (`_displayShowUserNameKey`, SP:191) | `showUserName:4665` | `setShowUserName:4666` | настройка Android |
| `display_show_user_timestamp_v1` (`_displayShowUserTimestampKey`, SP:192) | `showUserTimestamp:4676` | `setShowUserTimestamp:4677` | настройка Android |
| `display_show_model_name_v1` (`_displayShowModelNameKey`, SP:194) | `showModelName:4718` | `setShowModelName:4719` | настройка Android |
| `display_show_model_timestamp_v1` (`_displayShowModelTimestampKey`, SP:195) | `showModelTimestamp:4729` | `setShowModelTimestamp:4730` | настройка Android |
| `display_show_user_message_actions_v1` (`_displayShowUserMessageActionsKey`, SP:197) | `showUserMessageActions:4686` | `setShowUserMessageActions:4687` | настройка Android |
| `display_show_thinking_cards_v1` (`_displayShowThinkingCardsKey`, SP:199) | `showThinkingCards:4751` | `setShowThinkingCards:4752` | настройка Android |
| `display_show_tool_cards_v1` (`_displayShowToolCardsKey`, SP:201) | `showToolCards:4762` | `setShowToolCards:4763` | настройка Android |
| `display_show_produced_files_v1` (`_displayShowProducedFilesKey`, SP:202) | `showProducedFiles:4773` | `setShowProducedFiles:4774` | настройка Android |
| `display_auto_collapse_thinking_v1` (`_displayAutoCollapseThinkingKey`, SP:204) | `autoCollapseThinking:4783` | `setAutoCollapseThinking:4784` | настройка Android |
| `display_collapse_thinking_steps_v1` (`_displayCollapseThinkingStepsKey`, SP:206) | `collapseThinkingSteps:4793` | `setCollapseThinkingSteps:4794` | настройка Android |
| `display_show_tool_result_summary_v1` (`_displayShowToolResultSummaryKey`, SP:208) | `showToolResultSummary:4803` | `setShowToolResultSummary:4804` | настройка Android |
| `display_hide_tool_result_images_v1` (`_displayHideToolResultImagesKey`, SP:210) | `hideToolResultImages:4813` | `setHideToolResultImages:4814` | настройка Android |
| `display_regenerate_delete_trailing_messages_v1` (`_displayRegenerateDeleteTrailingMessagesKey`, SP:212) | `regenerateDeleteTrailingMessages:4823` | `setRegenerateDeleteTrailingMessages:4825` | настройка Android |
| `display_show_regenerate_confirm_dialog_v1` (`_displayShowRegenerateConfirmDialogKey`, SP:214) | `showRegenerateConfirmDialog:4834` | `setShowRegenerateConfirmDialog:4835` | настройка Android |
| `chat_fork_keep_message_versions_v1` (`_chatForkKeepMessageVersionsKey`, SP:216) | `forkKeepMessageVersions:4844` | `setForkKeepMessageVersions:4845` | настройка Android |
| `chat_edit_assistant_keep_thinking_tool_cards_v1` (`_chatEditAssistantKeepThinkingToolCardsKey`, SP:218) | `keepThinkingAndToolCardsWhenEditingAssistant:4853` | `setKeepThinkingAndToolCardsWhenEditingAssistant:4855` | настройка Android |
| `display_show_provider_in_model_capsule_v1` (`_displayShowProviderInModelCapsuleKey`, SP:227) | `showProviderInModelCapsule:4886` | `setShowProviderInModelCapsule:4887` | скрыто; вызова записи в lib нет |
| `display_show_provider_in_chat_message_v1` (`_displayShowProviderInChatMessageKey`, SP:229) | `showProviderInChatMessage:4897` | `setShowProviderInChatMessage:4898` | настройка Android |
| `display_new_chat_on_assistant_switch_v1` (`_displayNewChatOnAssistantSwitchKey`, SP:252) | `newChatOnAssistantSwitch:4919` | `setNewChatOnAssistantSwitch:4920` | настройка Android |
| `display_new_chat_after_delete_v1` (`_displayNewChatAfterDeleteKey`, SP:256) | `newChatAfterDelete:4930` | `setNewChatAfterDelete:4931` | настройка Android |
| `display_enter_to_send_on_mobile_v1` (`_displayEnterToSendOnMobileKey`, SP:258) | `enterToSendOnMobile:4941` | `setEnterToSendOnMobile:4942` | настройка Android |
| `display_long_paste_as_file_v1` (`_displayLongPasteAsFileKey`, SP:260) | `longPasteAsFile:4968` | `setLongPasteAsFile:4969` | настройка Android |
| `display_long_paste_as_file_threshold_v1` (`_displayLongPasteAsFileThresholdKey`, SP:262) | `longPasteAsFileThreshold:4978` | `setLongPasteAsFileThreshold:4979` | настройка Android |
| `desktop_send_shortcut_v1` (`_desktopSendShortcutKey`, SP:264) | `desktopSendShortcut:4993` | `setDesktopSendShortcut:4994` | скрытая действующая настройка широкого Android/hardware keyboard (chat_input_bar.dart:1182–1214); setter UI нет |
| `display_auto_scroll_enabled_v1` (`_displayAutoScrollEnabledKey`, SP:266) | `autoScrollEnabled:5125` | `setAutoScrollEnabled:5126` | настройка Android |
| `display_auto_scroll_idle_seconds_v1` (`_displayAutoScrollIdleSecondsKey`, SP:268) | `autoScrollIdleSeconds:5136` | `setAutoScrollIdleSeconds:5137` | настройка Android |
| `sidebar_thumbnails_v1` (`_sidebarThumbnailsKey`, SP:286) | `sidebarThumbnails:5260` | `setSidebarThumbnails:5261` | настройка Android |
| `sidebar_folders_v1` (`_sidebarFoldersKey`, SP:287) | `sidebarFolders:5270` | `setSidebarFolders:5271` | настройка Android |
| `image_cropper_enabled_v1` (`_imageCropperEnabledKey`, SP:290) | `imageCropperEnabled:5298` | `setImageCropperEnabled:5299` | настройка Android |
| `image_upload_quality_v1` (`_imageUploadQualityKey`, SP:291) | `imageUploadQuality:5308` | `setImageUploadQuality:5309` | настройка Android |
| `image_compress_custom_quality_v1` (`_imageCompressCustomQualityKey`, SP:292) | `imageCompressCustomQuality:5317` | `setImageCompressCustomQuality:5318` | настройка Android |
| `image_compress_transparent_enabled_v1` (`_imageCompressTransparentEnabledKey`, SP:294) | `imageCompressTransparentEnabled:5327` | `setImageCompressTransparentEnabled:5328` | настройка Android |
| `send_markdown_image_links_as_images_v1` (`_sendMarkdownImageLinksAsImagesKey`, SP:296) | `sendMarkdownImageLinksAsImages:5339` | `setSendMarkdownImageLinksAsImages:5340` | настройка Android |
| `display_collapse_long_user_messages_v1` (`_displayCollapseLongUserMessagesKey`, SP:304) | `collapseLongUserMessages:5418` | `setCollapseLongUserMessages:5419` | настройка Android |
| `display_collapse_long_user_message_chars_v1` (`_displayCollapseLongUserMessageCharsKey`, SP:306) | `collapseLongUserMessageChars:5432` | `setCollapseLongUserMessageChars:5433` | настройка Android |
| `display_assistant_bubble_fit_content_v1` (`_displayAssistantBubbleFitContentKey`, SP:314) | `assistantBubbleFitContent:530` | `setAssistantBubbleFitContent:2700` | настройка Android |
| `display_assistant_bubble_split_paragraphs_v1` (`_displayAssistantBubbleSplitParagraphsKey`, SP:316) | `assistantBubbleSplitParagraphs:534` | `setAssistantBubbleSplitParagraphs:2707` | настройка Android |
| `sidebar_shortcuts_v1` (`_sidebarShortcutsKey`, SP:331) | `sidebarShortcuts:5601` | `setSidebarShortcuts:5603` | настройка Android |
| `translate_model_v1` (`_translateModelKey`, SP:368) | `translateModelProvider:3747`<br>`translateModelId:3748`<br>`translateModelKey:3749` | `setTranslateModel:3768`<br>`resetTranslateModel:3776` | настройка Android |
| `translate_prompt_v1` (`_translatePromptKey`, SP:369) | `translatePrompt:3764` | `setTranslatePrompt:3784`<br>`resetTranslatePrompt:3791` | настройка Android |
| `translate_target_lang_v1` (`_translateTargetLangKey`, SP:370) | `translateTargetLang:3766` | `setTranslateTargetLang:3793`<br>`resetTranslateTargetLang:3802` | настройка Android |
| `ocr_enabled_v1` (`_ocrEnabledKey`, SP:371) | `ocrEnabled:3836` | `resetOcrModel:3846`<br>`setOcrEnabled:3865` | настройка Android |
| `learning_mode_enabled_v1` (`_learningModeEnabledKey`, SP:372) | `learningModeEnabled:4115` | `setLearningModeEnabled:4116` | источник legacy-миграции в инструкции (instruction_injection_store.dart:15–16/71/75); отдельного текущего UI нет |
| `learning_mode_prompt_v1` (`_learningModePromptKey`, SP:373) | `learningModePrompt:4128` | `setLearningModePrompt:4129`<br>`resetLearningModePrompt:4138` | источник legacy-миграции в инструкции (instruction_injection_store.dart:15–16/71/75); отдельного текущего UI нет |

### Ассистенты и агенты

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `mobile_assistant_edit_tab_order_v1` (`_mobileAssistantEditTabOrderKey`, SP:332) | `mobileAssistantEditTabOrder:3185` | `setMobileAssistantEditTabOrder:3186` | настройка Android |
| `mobile_assistant_edit_tab_hidden_v1` (`_mobileAssistantEditTabHiddenKey`, SP:334) | `hiddenMobileAssistantEditTabs:3196` | `setHiddenMobileAssistantEditTabs:3198` | настройка Android |
| `mobile_assistant_detail_outline_enabled_v1` (`_mobileAssistantDetailOutlineEnabledKey`, SP:336) | `mobileAssistantDetailOutlineEnabled:3209` | `setMobileAssistantDetailOutlineEnabled:3211` | настройка Android |

### Рабочая область и инструменты

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `tool_schema_overrides_v1` (`_toolSchemaOverridesKey`, SP:327) | `toolSchemaOverrides:3041` | `setToolSchemaOverride:3066`<br>`setToolSchemaOverrideLive:3076`<br>`resetToolSchemaOverride:3088`<br>`resetAllToolSchemaOverrides:3092` | настройка Android |
| `tool_auto_approve_all_v1` (`_toolAutoApproveAllKey`, SP:328) | `toolAutoApproveAll:5572` | `setToolAutoApproveAll:5574` | настройка Android |
| `browser_disabled_actions_v1` (`_disabledBrowserActionsKey`, SP:329) | `disabledBrowserActions:5584` | `setBrowserActionEnabled:5586` | настройка Android |
| `mini_app_web_port_v1` (`_miniAppWebPortKey`, SP:383) | `miniAppWebPort:738` | `setMiniAppWeb:746` | настройка Android |
| `mini_app_web_localhost_only_v1` (`_miniAppWebLocalhostOnlyKey`, SP:384) | `miniAppWebLocalhostOnly:739` | `setMiniAppWeb:746` | настройка Android |
| `mini_app_web_password_enabled_v1` (`_miniAppWebPasswordEnabledKey`, SP:386) | `miniAppWebPasswordEnabled:740` | `setMiniAppWeb:746` | настройка Android |
| `mini_app_web_password_v1` (`_miniAppWebPasswordKey`, SP:388) | `miniAppWebPassword:741` | `setMiniAppWeb:746` | настройка Android |
| `mini_app_web_autostart_v1` (`_miniAppWebAutostartKey`, SP:389) | `miniAppWebAutostart:744` | `setMiniAppWeb:746` | настройка Android |

### Голос

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `tts_services_v1` (`_ttsServicesKey`, SP:403) | `ttsServices:418` | `setTtsServices:1723` | настройка Android |
| `tts_selected_service_id_v1` (`_ttsSelectedServiceIdKey`, SP:404) | `selectedTtsServiceId:419`<br>`selectedTtsService:429` | `setSelectedTtsServiceId:1748`<br>`setTtsServiceSelected:1742` | настройка Android |
| `tts_selected_v1` (`_ttsSelectedKey`, SP:406) | — | — | только миграция старых данных |
| `tts_auto_play_assistant_replies_v1` (`_ttsAutoPlayAssistantRepliesKey`, SP:407) | `ttsAutoPlayAssistantReplies:427` | `setTtsAutoPlayAssistantReplies:1768` | настройка Android |
| `tts_text_selection_mode_v1` (`_ttsTextSelectionModeKey`, SP:409) | `ttsTextSelectionMode:428` | `setTtsTextSelectionMode:1776` | настройка Android |
| `asr_services_v1` (`_asrServicesKey`, SP:410) | `asrServices:441` | `setAsrServices:1784` | настройка Android |
| `asr_selected_service_id_v1` (`_asrSelectedServiceIdKey`, SP:411) | `selectedAsrServiceId:442`<br>`selectedAsrService:443` | `setSelectedAsrServiceId:1800` | настройка Android |

### Данные и память

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `memory_model_v1` (`_memoryModelKey`, SP:146) | `memoryModelProvider:4241`<br>`memoryModelId:4242`<br>`memoryModelKey:4243` | `setMemoryModel:4333`<br>`resetMemoryModel:4341` | настройка Android |
| `memory_model_thinking_enabled_v1` (`_memoryModelThinkingEnabledKey`, SP:147) | `memoryModelThinkingEnabled:4249` | `setMemoryModelThinkingEnabled:4349` | настройка Android |
| `memory_prompt_lang_v1` (`_memoryPromptLangKey`, SP:149) | `memoryPromptLang:4253`<br>`resolvedMemoryPromptLang:4277` | `setMemoryPromptLang:4401` | настройка Android |
| `memory_trace_enabled_v1` (`_memoryTraceEnabledKey`, SP:150) | `memoryTraceEnabled:4257` | `setMemoryTraceEnabled:4358` | настройка Android |
| `memory_legacy_mode_v1` (`_legacyMemoryModeKey`, SP:151) | `legacyMemoryMode:4260` | `setLegacyMemoryMode:4366` | настройка Android |
| `memory_legacy_prompt_zh_v1` (`_legacyMemoryPromptZhKey`, SP:152) | `legacyMemoryPromptZh:4263` | `setLegacyMemoryPromptZh:4373`<br>`resetLegacyMemoryPromptZh:4384` | настройка Android |
| `memory_legacy_prompt_en_v1` (`_legacyMemoryPromptEnKey`, SP:153) | `legacyMemoryPromptEn:4266` | `setLegacyMemoryPromptEn:4387`<br>`resetLegacyMemoryPromptEn:4398` | настройка Android |
| `memory_rules_prompt_zh_v1` (`_memoryRulesPromptZhKey`, SP:154) | `memoryRulesPromptZh:4307` | `setMemoryRulesPromptZh:4410`<br>`resetMemoryRulesPromptZh:4570` | настройка Android |
| `memory_rules_prompt_en_v1` (`_memoryRulesPromptEnKey`, SP:155) | `memoryRulesPromptEn:4308` | `setMemoryRulesPromptEn:4418`<br>`resetMemoryRulesPromptEn:4572` | настройка Android |
| `memory_gate_prompt_zh_v1` (`_memoryGatePromptZhKey`, SP:156) | `memoryGatePromptZh:4309` | `setMemoryGatePromptZh:4426`<br>`resetMemoryGatePromptZh:4574` | настройка Android |
| `memory_gate_prompt_en_v1` (`_memoryGatePromptEnKey`, SP:157) | `memoryGatePromptEn:4310` | `setMemoryGatePromptEn:4432`<br>`resetMemoryGatePromptEn:4576` | настройка Android |
| `memory_extract_prompt_zh_v1` (`_memoryExtractPromptZhKey`, SP:158) | `memoryExtractPromptZh:4311` | `setMemoryExtractPromptZh:4438`<br>`resetMemoryExtractPromptZh:4578` | настройка Android |
| `memory_extract_prompt_en_v1` (`_memoryExtractPromptEnKey`, SP:159) | `memoryExtractPromptEn:4312` | `setMemoryExtractPromptEn:4449`<br>`resetMemoryExtractPromptEn:4580` | настройка Android |
| `memory_smart_add_prompt_zh_v1` (`_memorySmartAddPromptZhKey`, SP:160) | `memorySmartAddPromptZh:4313` | `setMemorySmartAddPromptZh:4460`<br>`resetMemorySmartAddPromptZh:4582` | настройка Android |
| `memory_smart_add_prompt_en_v1` (`_memorySmartAddPromptEnKey`, SP:162) | `memorySmartAddPromptEn:4314` | `setMemorySmartAddPromptEn:4471`<br>`resetMemorySmartAddPromptEn:4584` | настройка Android |
| `memory_smart_add_batch_prompt_zh_v1` (`_memorySmartAddBatchPromptZhKey`, SP:164) | `memorySmartAddBatchPromptZh:4315` | `setMemorySmartAddBatchPromptZh:4482`<br>`resetMemorySmartAddBatchPromptZh:4586` | настройка Android |
| `memory_smart_add_batch_prompt_en_v1` (`_memorySmartAddBatchPromptEnKey`, SP:166) | `memorySmartAddBatchPromptEn:4316` | `setMemorySmartAddBatchPromptEn:4493`<br>`resetMemorySmartAddBatchPromptEn:4588` | настройка Android |
| `memory_profile_distill_prompt_zh_v1` (`_memoryProfileDistillPromptZhKey`, SP:168) | `memoryProfileDistillPromptZh:4317` | `setMemoryProfileDistillPromptZh:4504`<br>`resetMemoryProfileDistillPromptZh:4590` | настройка Android |
| `memory_profile_distill_prompt_en_v1` (`_memoryProfileDistillPromptEnKey`, SP:170) | `memoryProfileDistillPromptEn:4318` | `setMemoryProfileDistillPromptEn:4515`<br>`resetMemoryProfileDistillPromptEn:4592` | настройка Android |
| `memory_migrate_prompt_zh_v1` (`_memoryMigratePromptZhKey`, SP:172) | `memoryMigratePromptZh:4319` | `setMemoryMigratePromptZh:4526`<br>`resetMemoryMigratePromptZh:4594` | настройка Android |
| `memory_migrate_prompt_en_v1` (`_memoryMigratePromptEnKey`, SP:173) | `memoryMigratePromptEn:4320` | `setMemoryMigratePromptEn:4537`<br>`resetMemoryMigratePromptEn:4596` | настройка Android |
| `memory_migration_batch_size_v1` (`_memoryMigrationBatchSizeKey`, SP:174) | `memoryMigrationBatchSize:4321` | `setMemoryMigrationBatchSize:4548` | настройка Android |
| `memory_injection_max_items_v1` (`_memoryInjectionMaxItemsKey`, SP:179) | `memoryInjectionMaxItems:4322` | `setMemoryInjectionMaxItems:4559` | настройка Android |
| `webdav_config_v1` (`_webDavConfigKey`, SP:380) | `webDavConfig:2236` | `setWebDavConfig:2237` | настройка Android |
| `s3_config_v1` (`_s3ConfigKey`, SP:381) | `s3Config:2245` | `setS3Config:2246` | настройка Android |

### Приложение

| Ключ хранения / объявление | Чтение (`identifier:line`) | Запись (`identifier:line`) | Статус |
|---|---|---|---|
| `display_show_message_nav_v1` (`_displayShowMessageNavKey`, SP:220) | `showMessageNavButtons:4864` | `setShowMessageNavButtons:4865` | совместимость; интерфейс выбирает mobileMessageNavButtonsMode |
| `display_desktop_message_nav_buttons_mode_v1` (`_displayDesktopMessageNavButtonsModeKey`, SP:221) | `desktopMessageNavButtonsMode:5006` | `setDesktopMessageNavButtonsMode:5009` | сохранённый legacy-параметр без production-потребителя и без текущего UI |
| `display_keep_screen_on_during_generation_v1` (`_displayKeepScreenOnDuringGenerationKey`, SP:243) | `keepScreenOnDuringGeneration:5458` | `setKeepScreenOnDuringGeneration:5459` | настройка Android |
| `display_keep_sidebar_open_on_assistant_tap_v1` (`_displayKeepSidebarOpenOnAssistantTapKey`, SP:246) | `keepSidebarOpenOnAssistantTap:5538` | `setKeepSidebarOpenOnAssistantTap:5539` | настройка Android |
| `display_keep_sidebar_open_on_topic_tap_v1` (`_displayKeepSidebarOpenOnTopicTapKey`, SP:248) | `keepSidebarOpenOnTopicTap:5549` | `setKeepSidebarOpenOnTopicTap:5550` | настройка Android |
| `display_keep_assistant_list_expanded_on_sidebar_close_v1` (`_displayKeepAssistantListExpandedOnSidebarCloseKey`, SP:250) | `keepAssistantListExpandedOnSidebarClose:5560` | `setKeepAssistantListExpandedOnSidebarClose:5562` | настройка Android |
| `display_new_chat_on_launch_v1` (`_displayNewChatOnLaunchKey`, SP:254) | `newChatOnLaunch:4908` | `setNewChatOnLaunch:4909` | настройка Android |
| `sidebar_collapsed_sections_v1` (`_sidebarCollapsedSectionsKey`, SP:288) | `sidebarCollapsedSections:5284` | `toggleSidebarSection:5285` | сохранённое состояние свёрнутости боковой панели |
| `request_log_enabled_v1` (`_requestLogEnabledKey`, SP:339) | `requestLogEnabled:5615` | `setRequestLogEnabled:5616` | настройка Android |
| `context_log_enabled_v1` (`_contextLogEnabledKey`, SP:340) | `contextLogEnabled:5626` | `setContextLogEnabled:5627` | настройка Android |
| `log_save_output_v1` (`_logSaveOutputKey`, SP:344) | `logSaveOutput:5658` | `setLogSaveOutput:5659` | настройка Android |
| `log_elide_large_payloads_v1` (`_logElideLargePayloadsKey`, SP:345) | `logElideLargePayloads:5670` | `setLogElideLargePayloads:5671` | настройка Android |
| `log_auto_delete_days_v1` (`_logAutoDeleteDaysKey`, SP:346) | `logAutoDeleteDays:5682` | `setLogAutoDeleteDays:5683` | настройка Android |
| `log_max_size_mb_v1` (`_logMaxSizeMBKey`, SP:347) | `logMaxSizeMB:5694` | `setLogMaxSizeMB:5695` | настройка Android |
| `display_haptics_on_generate_v1` (`_displayHapticsOnGenerateKey`, SP:231) | `hapticsOnGenerate:5447` | `setHapticsOnGenerate:5448` | настройка Android |
| `display_haptics_on_drawer_v1` (`_displayHapticsOnDrawerKey`, SP:233) | `hapticsOnDrawer:5470` | `setHapticsOnDrawer:5471` | настройка Android |
| `display_haptics_global_enabled_v1` (`_displayHapticsGlobalEnabledKey`, SP:235) | `hapticsGlobalEnabled:5481` | `setHapticsGlobalEnabled:5482` | настройка Android |
| `display_haptics_ios_switch_v1` (`_displayHapticsIosSwitchKey`, SP:237) | `hapticsIosSwitch:5494` | `setHapticsIosSwitch:5495` | настройка Android |
| `display_haptics_on_list_item_tap_v1` (`_displayHapticsOnListItemTapKey`, SP:239) | `hapticsOnListItemTap:5505` | `setHapticsOnListItemTap:5506` | настройка Android |
| `display_haptics_on_card_tap_v1` (`_displayHapticsOnCardTapKey`, SP:241) | `hapticsOnCardTap:5516` | `setHapticsOnCardTap:5517` | настройка Android |
| `display_show_app_updates_v1` (`_displayShowAppUpdatesKey`, SP:245) | `showAppUpdates:5527` | `setShowAppUpdates:5528` | настройка Android |
| `flutter_log_enabled_v1` (`_flutterLogEnabledKey`, SP:342) | `flutterLogEnabled:5638` | `setFlutterLogEnabled:5639` | настройка Android |
| `app_launch_count_v1` (`_appLaunchCountKey`, SP:348) | `appLaunchCount:791` | `incrementAppLaunchCount:5648` | служебный счётчик запусков |
| `mobile_background_settings_v1` (`_mobileBackgroundKey`, SP:349) | `mobileBackground:3220` | `setMobileBackground:3222` | настройка Android |
| `app_locale_v1` (`_appLocaleKey`, SP:367) | `appLocale:2187`<br>`isFollowingSystemLocale:2188`<br>`appLocaleForMaterialApp:2190` | `setAppLocale:2192`<br>`setAppLocaleFollowSystem:2201` | настройка Android |

### Страницы провайдеров: вложенные настройки и точные подписи

Поля ниже хранятся в `provider_configs_v1[providerId]` через `setProviderConfig` (SP:3243); сериализация — `ProviderConfig.toJson` (SP:6410). Предложенный раздел: **Модели и подключения**. Все перечисленные элементы доступны в Android-интерфейсе. `PD` = `lib/features/provider/pages/provider_detail_page.dart`; `PN` = `provider_network_page.dart`; `PB` = `provider_balance_page.dart`; `PCR` = `provider_custom_request_page.dart`; `OPD` = `oauth_provider_detail_page.dart`; `MK` = `multi_key_manager_page.dart`; `MKS` = `multi_key_manager_sheets.dart` — все в той же папке.

| Сохраняемый идентификатор | Точная подпись | Доказательство / условие показа |
|---|---|---|
| `providerType` | `providerDetailPageProviderTypeTitle` — Тип провайдера | PD:2104; варианты OpenAI/Gemini/Claude PD:2207; SP:6191. `ProviderKind.local` сохранённый вариант enum, отклоняемый setProviderConfig SP:3245. |
| `enabled` | `providerDetailPageEnabledTitle` — Включено | PD:1134; SP:6182 |
| `name` | `providerDetailPageNameLabel` — Имя | PD:1368; SP:6183 |
| `apiKey` | `multiKeyPageKey` — API-ключ | PD:1380; одиночный ключ; скрыт для KelivoIN / Google Vertex AI / режима нескольких ключей; SP:6184 |
| `baseUrl` | `providerDetailPageApiBaseUrlLabel` — Базовый URL API | PD:1401; SP:6189; встроенный KelivoIN доступен только для чтения |
| `chatPath` | `providerDetailPageApiPathLabel` — Путь API | PD:1417; совместимый с OpenAI без Responses; SP:6192 |
| `useResponseApi` | `providerDetailPageResponseApiTitle` — Responses API (/responses) | PD:1207; совместимый с OpenAI; SP:6193 |
| `vertexAI` | `providerDetailPageVertexAiTitle` — Vertex AI | PD:1220; Google; SP:6194 |
| `location` | `providerDetailPageLocationLabel` — Местоположение | PD:1432; Google Vertex; SP:6195 |
| `projectId` | `providerDetailPageProjectIdLabel` — ID проекта | PD:1440; Google Vertex; SP:6196 |
| `serviceAccountJson` | `providerDetailPageServiceAccountJsonLabel` — JSON сервисного аккаунта (вставьте или импортируйте) | PD:1448; вставка/импорт, SP:6198 |
| `multiKeyEnabled` | `providerDetailPageMultiKeyModeTitle` — Режим нескольких ключей | PD:1145; SP:6219 |
| `apiKeys[]` | `providerDetailPageManageKeysButton` — Управление ключами | PD:1192; подробности ниже; SP:6220 |
| `aihubmixAppCodeEnabled` | `providerDetailPageAihubmixAppCodeLabel` — APP-Code (скидка 10%) | PD:1232; AIhubmix; SP:6223 |
| `claudePromptCachingEnabled` | `providerDetailPageClaudePromptCachingTitle` — Кэширование промптов Claude | PD:1245; при поддержке Claude/OpenRouter; SP:6229; также аккаунт подписки: provider_prompt_cache_settings.dart:39 |
| `claudePromptCachingTtl` | `providerDetailPageClaudePromptCachingTtlTitle` — Время жизни кэша | PD:1260; 5m/1h; SP:6230; также аккаунт подписки: provider_prompt_cache_settings.dart:56 |
| `proxyEnabled` | `providerDetailPageEnableProxyTitle` — Включить прокси | PN:78; SP:6209 |
| `proxyType` | `networkProxyType` — Тип прокси | PN:89; варианты HTTP/SOCKS5 PN:279/286; SP:6210 |
| `proxyHost` | `providerDetailPageHostLabel` — Хост | PN:102; SP:6211 |
| `proxyPort` | `providerDetailPagePortLabel` — Порт | PN:114; SP:6212 |
| `proxyUsername` | `providerDetailPageUsernameOptionalLabel` — Имя пользователя (необязательно) | PN:127; SP:6213 |
| `proxyPassword` | `providerDetailPagePasswordOptionalLabel` — Пароль (необязательно) | PN:137; SP:6214 |
| `balanceEnabled` | `providerDetailPageBalanceInfo` — Узнать баланс аккаунта | PB:80; совместимый с OpenAI; SP:6225 |
| `balanceApiPath` | `providerDetailPageBalanceApiPathLabel` — Путь API баланса | PB:95; SP:6226 |
| `balanceResultPath` | `providerDetailPageBalanceResultPathLabel` — Путь к результату в JSON | PB:111; SP:6227 |
| `customHeaders[].name/value` | `modelDetailSheetCustomHeadersTitle` — Свои заголовки | PCR:63/71; provider_custom_request_editor.dart:99,111,112; SP:6206 |
| `customBody[].key/value` | `modelDetailSheetCustomBodyTitle` — Свои поля тела запроса | PCR:64/82; provider_custom_request_editor.dart:120,132,133; SP:6207 |
| `avatarType / avatarValue` | `providerAvatarChooseBuiltInIcon` — Выбрать встроенный значок | PD:359 редактор аватара; меню файл/URL/иконка/LobeHub/сброс PD:394; SP:6216/6217; запись emoji SP:3288 не вызывается из интерфейса |
| `name (OAuth account)` | `oauthName` — Название провайдера | OPD:297/304 |
| `enabled (OAuth account)` | `addProviderSheetEnabledLabel` — Включено | OPD:310/316 |

Группа провайдера хранится отдельно от ProviderConfig: `provider_group_map_v1[providerId]`; подпись `providerGroupsGroupLabel` — «Группа» (PD:2155). Создание и имя группы: `providerGroupsNameHint` — «Название группы» (provider_groups_page.dart:31/71); методы SP:2428/2451/2514. Порядок и перенос между группами: SP:2490/2535/2555/2630. Свёрнутость группы — сохранённое состояние интерфейса, а не отдельная настройка.

Аккаунты подписок/OAuth образуют вид подключения. Добавление — вкладка `oauthAccountsTab` (add_provider_sheet.dart:506), детали — OPD:225. Тип `oauthProvider`, токены, срок действия и сведения об аккаунте в `oauthCredentials`, дата синхронизации `oauthModelsSyncedAt` относятся к авторизации и рабочему состоянию (SP:6185–6187). Вход/выход, обновление расхода, синхронизация моделей, сведения о подключении, показать/скрыть ключ, потоковая проверка моделей (`_detectUseStream`, PD:90/2796), выделение, строка поиска и фильтры — действия или локальное состояние. Они не образуют самостоятельные глобальные настройки.

Вложенные настройки нескольких ключей провайдера: `lib/core/models/api_keys.dart`; сериализуются как `apiKeys` и `keyManagement`.

| Настройка пользователя | Точная подпись / значения | Доказательство |
|---|---|---|
| `apiKeys[].key` | `multiKeyPageKey` — API-ключ | MKS:325; api_keys.dart:56 |
| `apiKeys[].name` | `multiKeyPageAlias` — Псевдоним | MKS:294; api_keys.dart:57 |
| `apiKeys[].isEnabled` | переключатель возле ключа | MK:346; api_keys.dart:58 |
| `apiKeys[].priority` | `multiKeyPagePriority` — Приоритет (1–10); 1–10 | MKS:357/393; api_keys.dart:59 |
| `keyManagement.strategy` | `multiKeyPageStrategyRoundRobin` — По очереди / `multiKeyPageStrategyPriority` — По приоритету / `multiKeyPageStrategyLeastUsed` — Реже используемые / `multiKeyPageStrategyRandom` — Случайно | MK:169–181; MKS:100; api_keys.dart:175 |

`apiKeys[].maxRequestsPerMinute` (api_keys.dart:60), `keyManagement.maxFailuresBeforeDisable`, `failureRecoveryTimeMinutes`, `enableAutoRecovery` (api_keys.dart:176–178) присутствуют в сериализуемой модели, но **не редактируются в этом интерфейсе**. `roundRobinIndex` (179), `usage`, `status`, `lastError` и даты — внутренние счётчики и рабочее состояние. Пакетное добавление, удаление и проверка ключей — действия.

Настройки модели хранятся в `ProviderConfig.models[] / modelOverrides[logicalModelId]` (SP:6199–6204). Редактор: `lib/features/model/widgets/model_detail_sheet.dart` (`MD`); составление карты MD:823, сохранение MD:851/857.

| Идентификатор | Точная подпись | Строка интерфейса |
|---|---|---|
| `apiModelId` | `modelDetailSheetModelIdLabel` — ID модели | MD:383 |
| `name` | `modelDetailSheetModelNameLabel` — Название модели | MD:459 |
| `type` | `modelDetailSheetModelTypeLabel` — Тип модели | MD:496 |
| `contextWindow` | `modelDetailSheetContextWindowLabel` — Контекстное окно (токены) | MD:510 |
| `input[]` | `modelDetailSheetInputModesLabel` — Типы ввода | MD:554 |
| `output[]` | `modelDetailSheetOutputModesLabel` — Типы вывода | MD:577 |
| `abilities[]` | `modelDetailSheetAbilitiesLabel` — Возможности | MD:599 |
| `headers[].name/value` | `modelDetailSheetCustomHeadersTitle` — Свои заголовки | MD:634 |
| `body[].key/value` | `modelDetailSheetCustomBodyTitle` — Свои поля тела запроса | MD:662 |
| `builtInTools[]` | `modelDetailSheetBuiltinToolsTab` — Встроенные инструменты | MD:356 |

ID существующей модели доступен только для чтения (MD:387); для новой модели вводится ID провайдера. Тип: chat/embedding (MD:500/501), вход/выход: text/image, возможности: tool/reasoning. Набор встроенных инструментов зависит от провайдера (`BuiltInToolNames/BuiltInToolsHelper`). Постоянный логический ID позволяет иметь несколько экземпляров одной модели; сведения о синхронизации — рабочее состояние.

### Страницы поиска: все параметры поисковых сервисов

Предложенный раздел: **Модели и подключения → Дополнительно → Поисковые сервисы**; включение поиска в чате относится к **Чаты и ответы**. `SS` = `lib/features/search/pages/search_services_page.dart`; `SE` = `search_service_editor_page.dart`; `SK` = `search_api_keys_page.dart`; `SO` = `lib/core/services/search/search_service.dart`. `search_services_v1` хранит сериализованные `SearchServiceOptions.toJson`, `search_common_v1` — SearchCommonOptions. Общая запись: SS:102 → SP:5762 → SP:5714/5730/5737.

| Общий параметр / состояние | Точная подпись | Доказательство / примечание |
|---|---|---|
| `searchAutoTestOnLaunch` | `searchServicesPageAutoTestTitle` — Проверять подключения при запуске | SS:272/282; SP:725/5754; настройка интерфейса |
| `searchCommonOptions.resultSize` | `searchServicesPageMaxResults` — Максимум результатов | SS:316; SO:180/185; максимальное число результатов |
| `searchCommonOptions.timeout` | `searchServicesPageTimeoutSeconds` — Тайм-аут (секунды) | SS:379; SO:181/187; хранение в миллисекундах, интерфейс в секундах |
| `searchServiceSelected` | выбранная строка сервиса | SS:35/107; SP:721/5737; также search_settings_sheet.dart:437 |
| service type (`toJson.type`) | `searchServiceEditorProviderTypeTitle` — Провайдер поиска | SE:180/190; обычный выбор из 25 типов (SE:2643–2669); тип сохраняется; Kelivo разблокируется отдельно |
| `extraApiKeys[]` → JSON `apiKeys` | `searchServiceEditorMultiKeyTitle` — Чередование ключей | SE:741/793; SK:33/147/278; SO:203/210; чередование ключей; основной ключ — `apiKey` |

Текущий переключатель внешнего поиска меняет `Assistant.searchEnabled` через `AssistantProvider.setSearchEnabledForCurrentAssistant` (search_settings_sheet.dart:163). У `SettingsProvider.searchEnabled/search_enabled_v1` нет внешнего читателя и настройки интерфейса: это сохранённый скрытый API совместимости. Встроенный поиск модели меняет `modelOverrides[modelId].builtInTools` (search_settings_sheet.dart:65/78), подпись `searchSettingsSheetBuiltinSearchTitle` — «Встроенный поиск» (:241). Подпись динамического поиска Claude: `searchSettingsSheetClaudeDynamicSearchTitle` — «Динамическая фильтрация» (:320), запись через `BuiltInToolsHelper.withClaudeDynamicWebSearch` (:94). Это отдельные параметры модели, а не дополнительные скалярные ключи SettingsProvider.

| Класс поиска / сохраняемый тип | Поля интерфейса: идентификаторы и подписи (`SE:line`) | Сохраняемые поля без редактирования здесь |
|---|---|---|
| `BingLocalOptions` / `bing_local` (SO:292) | нет полей авторизации/параметров | `acceptLanguage` |
| `TavilyOptions` / `tavily` (SO:311) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:345)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:352) | — |
| `ExaOptions` / `exa` (SO:346) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:362)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:369) | — |
| `ZhipuOptions` / `zhipu` (SO:381) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `SearXNGOptions` / `searxng` (SO:401) | `url` — `searchServicesEditDialogInstanceUrl` — URL экземпляра (SE:379)<br>`engines` — `searchServicesEditDialogEnginesOptional` — Поисковые движки (необязательно) (SE:385)<br>`language` — `searchServicesEditDialogLanguageOptional` — Язык (необязательно) (SE:390)<br>`username` — `searchServicesEditDialogUsernameOptional` — Имя пользователя (необязательно) (SE:395)<br>`password` — `searchServicesEditDialogPasswordOptional` — Пароль (необязательно) (SE:399) | — |
| `LinkUpOptions` / `linkup` (SO:438) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `BraveOptions` / `brave` (SO:458) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:681)<br>`maximumNumberOfTokens` — `searchServicesDialogMaximumTokens` — Максимум токенов (SE:708)<br>`mode` — `searchServicesDialogSearchMode` — Режим поиска (SE:688) | — |
| `MetasoOptions` / `metaso` (SO:521) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `OllamaOptions` / `ollama` (SO:541) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `JinaOptions` / `jina` (SO:561) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `DuckDuckGoOptions` / `duckduckgo` (SO:581) | `region` — `searchServicesEditDialogRegionOptional` — Регион (необязательно, по умолчанию us-en) (SE:336) | — |
| `PerplexityOptions` / `perplexity` (SO:597) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | `country`, `searchDomainFilter`, `maxTokensPerPage` |
| `BochaOptions` / `bocha` (SO:636) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | `freshness`, `summary`, `include`, `exclude` |
| `SerperOptions` / `serper` (SO:677) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:408)<br>`gl` — `searchServicesDialogCountryOptional` — Страна/регион (необязательно) (SE:415)<br>`hl` — `searchServicesDialogLanguageOptional` — Язык (необязательно) (SE:420)<br>`tbs` — `searchServicesDialogTimeFilterOptional` — Фильтр по времени (необязательно) (SE:425)<br>`page` — `searchServicesDialogPageOptional` — Страница (необязательно) (SE:430) | — |
| `GrokOptions` / `grok` (SO:717) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:484)<br>`model` — `searchServicesDialogModel` — Модель (SE:491)<br>`reasoningEffort` — `reasoningBudgetSheetTitle` — Глубина рассуждений (SE:496)<br>`customUrl` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:501)<br>`systemPrompt` — `searchServicesDialogSystemPrompt` — Системный промпт (SE:507) | — |
| `QueritOptions` / `querit` (SO:784) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:448)<br>`sitesInclude` — `searchServicesDialogSitesIncludeOptional` — Включить сайты (необязательно) (SE:455)<br>`sitesExclude` — `searchServicesDialogSitesExcludeOptional` — Исключить сайты (необязательно) (SE:460)<br>`timeRange` — `searchServicesDialogTimeRangeOptional` — Период (необязательно) (SE:465)<br>`countries` — `searchServicesDialogCountriesOptional` — Страны (необязательно) (SE:470)<br>`languages` — `searchServicesDialogLanguagesOptional` — Языки (необязательно) (SE:475) | — |
| `StepFunOptions` / `stepfun` (SO:828) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:517)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:524)<br>`category` — `moruSearchCategory` — Категория (SE:530) | — |
| `FirecrawlOptions` / `firecrawl` (SO:867) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:539)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:545)<br>`country` — `moruSearchCountry` — Страна (SE:551)<br>`location` — `providerDetailPageLocationLabel` — Местоположение (SE:552) | `sources`, `categories` |
| `TinyFishOptions` / `tinyfish` (SO:929) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:557)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:564)<br>`location` — `providerDetailPageLocationLabel` — Местоположение (SE:570)<br>`language` — `asrServicesLanguageLabel` — Язык (SE:575)<br>`includeDomains` — `moruSearchIncludeDomains` — Включить домены (SE:580)<br>`excludeDomains` — `moruSearchExcludeDomains` — Исключить домены (SE:581) | — |
| `AnySearchOptions` / `anysearch` (SO:981) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:586)<br>`url` — `searchServicesFieldCustomUrlOptional` — Свой URL (необязательно) (SE:592) | — |
| `KagiOptions` / `kagi` (SO:1017) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `DoubaoOptions` / `doubao` (SO:1037) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:723) | — |
| `KelivoOptions` / `kelivo` (SO:1057) | нет полей авторизации/параметров | — |
| `ParallelOptions` / `parallel` (SO:1069) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:602)<br>`mode` — `searchServicesDialogSearchMode` — Режим поиска (SE:609) | — |
| `KimiOptions` / `kimi` (SO:1120) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:626)<br>`mode` — `searchServicesDialogSearchMode` — Режим поиска (SE:633) | — |
| `YouSearchOptions` / `you` (SO:1158) | `apiKey` — `searchServicesDialogApiKey` — API-ключ (SE:650)<br>`contentMode` — `searchServicesDialogContentMode` — Режим содержимого (SE:657) | — |

Поддерживаются 26 типов данных поиска: **25 обычных вариантов добавления** в `_providerTypes` ([search_service_editor_page.dart:2643](../../../lib/features/search/pages/search_service_editor_page.dart#L2643), элементы :2644–2668) плюс отдельно разблокируемый Kelivo. Подписи имён задаются в SE:2585–2637 (`searchServiceName*`). Встроенный поиск Kelivo добавляется скрытым действием на странице «О приложении» (about_page.dart:75 → `unlockKelivoSearch`, SP:5705); редактор не содержит его полей. `BingLocalOptions.acceptLanguage`, Perplexity `country/searchDomainFilter/maxTokensPerPage`, Bocha `freshness/summary/include/exclude`, Firecrawl `sources/categories` **сохраняются редактором без возможности редактирования** (SE:1288/1363/1376/1438). Проверочный запрос, результаты, кэш расхода, ошибки и состояние подключения `searchConnection` (SP:728/2296) — рабочее состояние.

### Составные настройки автоповтора и фоновой работы Android

`auto_retry_options`: чтение SP:788, запись SP:1675; все десять полей представлены в auto_retry_page.dart. Предложенный раздел: **Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов**.

| Вложенное поле | Подпись | Строка |
|---|---|---|
| `enabled` | `autoRetryEnableLabel` — Включить автоповтор | auto_retry_page.dart:162 |
| `maxRetries` | `autoRetryMaxRetries` — Максимум повторов | auto_retry_page.dart:178 |
| `initialDelayMs` | `autoRetryInitialDelay` — Начальная задержка (мс) | auto_retry_page.dart:193 |
| `multiplier` | `autoRetryMultiplier` — Множитель задержки | auto_retry_page.dart:208 |
| `maxDelayMs` | `autoRetryMaxDelay` — Максимальная задержка (мс) | auto_retry_page.dart:224 |
| `jitter` | `autoRetryJitter` — Случайный разброс | auto_retry_page.dart:239 |
| `retryOnNetworkError` | `autoRetryOnNetworkError` — Повторять при сетевых ошибках | auto_retry_page.dart:246 |
| `retryStatusCodes` | `autoRetryStatusCodes` — Коды состояния для повтора | auto_retry_page.dart:256 |
| `retryKeywords` | `autoRetryKeywords` — Ключевые слова для повтора | auto_retry_page.dart:285 |
| `stopKeywords` | `autoRetryStopKeywords` — Ключевые слова для остановки | auto_retry_page.dart:317 |

`mobile_background_settings_v1`: чтение SP:3220, запись SP:3222; модель lib/core/models/mobile_background_settings.dart:2. Предложенный раздел: **Приложение → Фон и уведомления**. `MB` = mobile_background_settings_page.dart, `BO` = background_overlay_settings_page.dart; обе страницы в lib/features/settings/pages.

| Вложенное поле | Точная подпись | Строка / статус |
|---|---|---|
| `androidEnabled` | `backgroundAndroidEnabled` — Фоновая генерация | MB:135; настройка интерфейса |
| `notificationsEnabled` | `backgroundNotifications` — Уведомления задач | MB:143; настройка интерфейса |
| `privacyMode` | `backgroundPrivacy` — Конфиденциальность статуса задач | MB:156; настройка интерфейса |
| `overlayEnabled` | `backgroundOverlay` — Плавающий статус задач | MB:169; настройка интерфейса |
| `liveUpdatesEnabled` | `backgroundLiveUpdates` — Обновляемые уведомления | MB:182; настройка интерфейса |
| `completionVisibility` | `backgroundFinishVisibility` — Длительность показа завершённого статуса | MB:192; настройка интерфейса |
| `overlayIconKind / overlayIconValue` | `backgroundOverlayIcon` — Плавающий значок | BO:337/342/348/353; варианты приложения/изображение/emoji |
| `reliabilityHintDismissed` | — | сохранённое скрытие подсказки, home/widgets/background_reliability_hint.dart:48; служебное состояние интерфейса |
| `overlayAppearance.width` | `backgroundOverlayWidth` — Ширина | BO:233; настройка интерфейса |
| `overlayAppearance.height` | `backgroundOverlayHeight` — Высота | BO:241; настройка интерфейса |
| `overlayAppearance.cornerRadius` | `backgroundOverlayCornerRadius` — Радиус скругления | BO:249; настройка интерфейса |
| `overlayAppearance.iconSize` | `backgroundOverlayIconSize` — Размер значка | BO:257; настройка интерфейса |
| `overlayAppearance.progressSize` | `backgroundOverlayProgressSize` — Диаметр кольца прогресса | BO:265; настройка интерфейса |
| `overlayAppearance.progressStrokeWidth` | `backgroundOverlayProgressStroke` — Толщина кольца прогресса | BO:273; настройка интерфейса |
| `overlayAppearance.showProgress` | `backgroundOverlayShowProgress` — Показывать кольцо прогресса | BO:291; настройка интерфейса |
| `overlayAppearance.showTitle` | `backgroundOverlayShowTitle` — Показывать заголовок | BO:297; настройка интерфейса |
| `overlayAppearance.showSubtitle` | `backgroundOverlayShowSubtitle` — Показывать подзаголовок | BO:303; настройка интерфейса |
| `overlayAppearance.showTime` | `backgroundOverlayShowTime` — Показывать прошедшее время | BO:309; настройка интерфейса |
| `overlayAppearance.showClose` | `backgroundOverlayShowClose` — Показывать кнопку закрытия | BO:315; настройка интерфейса |
| `overlayAppearance.showBackground` | `backgroundOverlayShowBackground` — Показывать фон | BO:321; настройка интерфейса |
| `overlayAppearance.showBorder` | `backgroundOverlayShowBorder` — Показывать рамку | BO:327; настройка интерфейса |

Разрешение уведомлений, каналы, исключение из оптимизации батареи, режим энергосбережения, системный автозапуск и разрешение наложения открывают настройки Android или показывают системный статус (MB:240–301); **это не дополнительные ключи приложения**. Активные задачи, служба, наложение, обновляемое уведомление и последняя ошибка (MB:304–319) — рабочее состояние. Сохранённые переключатели намерения пользователя и разрешения ОС учитываются отдельно.

### Выводы для новой структуры настроек

- 200 объявленных ключей не равны 200 самостоятельным элементам настроек: составные JSON-конфигурации, миграции, служебные псевдонимы, выбранные ID, порядок, свёрнутость и счётчики группируются и получают отдельный статус.
- `hapticsIosSwitch` — реальная настройка Android, несмотря на имя (display_haptics_page.dart:50/54; SP:5494/5495). Её использует общий IosSwitch; её нельзя считать только iOS-кодом.
- `desktopSendShortcut` — скрытая действующая настройка аппаратной клавиатуры на широком Android: обработчик проверяет ширину ≥ `AppBreakpoints.tablet`, без проверки ОС ([chat_input_bar.dart:1182](../../../lib/features/home/widgets/chat_input_bar.dart#L1182), :1193/:1214; порог 900 логических px — [breakpoints.dart:5](../../../lib/shared/responsive/breakpoints.dart#L5)). Вызова setter из текущего интерфейса настроек нет. `desktopMessageNavButtonsMode` отдельно сохранён как legacy без потребителя production-кода; текущий чат читает `mobileMessageNavButtonsMode` ([home_page.dart:1685](../../../lib/features/home/pages/home_page.dart#L1685)).
- У `showProviderInModelCapsule` нет элемента настройки, но есть читатель в широком Android HomeDesktopScaffold (home_desktop_layout.dart:230). Это скрытая настройка, действующая на Android; имя экрана не делает её немобильной.
- Составные `showUserNameTimestamp`, `showModelNameTimestamp`, `showMessageNavButtons` служат обратной совместимости новых отдельных полей и режимов (SP:1115–1127/1151–1158); отдельные дублирующие переключатели не нужны.
- Старые getters/setters `learningModeEnabled/learningModePrompt` не вызываются извне SettingsProvider, но ключи `learning_mode_enabled_v1` / `learning_mode_prompt_v1` читаются миграцией в дополнительные инструкции: [instruction_injection_store.dart:15](../../../lib/core/services/instruction_injection_store.dart#L15), :16; `_seedDefaultFromLearningMode` читает prompt :71 и enabled :75, создаёт новую инструкцию :81 и при enabled активирует её :83. Это источники legacy-миграции, а не осиротевшие ключи. Отдельно глобальный `SettingsProvider.searchEnabled` остаётся без внешнего читателя; текущий UI использует `Assistant.searchEnabled`.
- `dynamicColorSupported` (SP:499, запись SP:3231), `hasAnyActiveModel`, вычисляемые модели, временные объекты прокси, загрузка, `searchConnection`, снимок для восстановления стеклянной темы, счётчик запусков, псевдонимы шрифтов, синхронизация моделей, токены и счётчики ключей — служебное состояние, а не дополнительные настройки.
- MCP хранится отдельно: `lib/core/providers/mcp_provider.dart:350/351` владеет `mcp_servers_v1` и `mcp_request_timeout_ms_v1`; запись тайм-аута :531. В предложенной структуре подключения MCP и привязка рабочей области в глубоком редакторе находятся в **Модели и подключения → Дополнительно → MCP**; локальные инструменты и права — в **Рабочая область и инструменты**. Это решение структуры интерфейса, а не свойство хранения.
- Старый режим памяти (`memory_legacy_mode_v1` и промпты) редактируется пользователем в memory_settings_page.dart:90/117. Это действующая настройка, в отличие от миграционных ключей темы/шрифтов/TTS; её следует сохранить под понятным названием старого режима памяти.


Согласованная структура: флаги request/context/flutter log и все параметры `log*` — **Приложение → Диагностика**; запуск нового чата при старте, удержание экрана, обновления, поведение боковой панели — **Приложение**; mobile-кнопки перехода между сообщениями — **Чаты и ответы → Прокрутка**; автоповтор — **Чаты и ответы → Повтор ответа и ошибки → Автоповтор запросов**.

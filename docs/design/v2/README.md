# Moru v2. Место для мысли и дела

**Моё предложение: один спокойный, выразительный интерфейс для разговора и работы.** Крупная типографика, тёплый светлый фон, графитовая тёмная тема, фиолетовый акцент. Важные действия находятся снизу; настройки сокращаются до восьми понятных разделов. Существующую кастомизацию и данные пользователей сохраняем.

Это дизайн-исследование Android-телефона, а не реализованный Flutter-интерфейс. Изменения этого PR только в `docs/`. HTML — документационные макеты, а не Web-версия Moru. Аудит выполнен **до рисования**, по базе `af795269974fb38aa474ffd6afec537885ab17cb` ветки `claude/moru-v0-1-16-audit-s69yji`. Фактическая версия в её `pubspec.yaml` — `0.1.47+48`; название ветки не означает версию приложения. Аудит: 1 октября 2026, оформление результата: 2 октября.

## Посмотреть с телефона

- [PNG-доска: все 42 макета](board.png).
- [Главная: светлая](png/home-light.png) · [тёмная](png/home-dark.png).
- [Агент: светлая](png/agent-light.png) · [тёмная](png/agent-dark.png).
- [Разрешение: светлая](png/permission-light.png) · [тёмная](png/permission-dark.png).
- [Новые настройки: светлая](png/settings-light.png) · [тёмная](png/settings-dark.png).
- [Внешний вид: светлая](png/appearance-light.png) · [тёмная](png/appearance-dark.png).
- [Локальная HTML-галерея](index.html): скачать каталог и открыть в браузере. GitHub показывает HTML как исходник; PNG открываются прямо в GitHub.

Каждый HTML самодостаточен: встроены CSS, JavaScript, SVG Lucide и Manrope из Google Fonts, сетевых зависимостей нет. Размер телефона **390×844 CSS px**, PNG **780×1688**, `deviceScaleFactor=2`. Каждый из 21 сценария имеет светлый и тёмный вариант. Длинные разделы прокручиваются; PNG фиксирует исходное положение, HTML даёт посмотреть их целиком. [Список файлов](screens.json) и [результаты автоматической проверки](render-report.json).

## 1. Что есть в коде

Подробные доказательства и полный инвентарь вынесены в приложения к этому README. Они являются частью одного дизайн-пакета:

| Приложение | Что проверено |
|---|---|
| [Все настройки и страницы](audit-settings.md) | 26/26 корневых пунктов; каждый вложенный параметр display/theme/message, provider/search, memory, voice, browser, фон/уведомления; 200/200 объявленных preference-констант с разделением пользовательских и служебных; 119/119 файлов `lib/features/*/pages` в 19 features, включая 44 settings-файла. |
| [Чат и runtime](audit-runtime.md) | Composer, очередь, план, инструменты, diff, разрешения, ACP, файлы, PTY, браузер, превью, мини-приложения, расписания, память, голос, native background и уведомления. |
| [Тема и кастомизация](audit-theme.md) | `ThemeData`, `AppThemeBuilder`, `AppSemanticColors`, HCT/surface ladder, Glass/restore, Google/local fonts, message overrides, Markdown/code, preview, размеры, иконки и дублирование. |

`pages/` не равно числу экранов: там лежат `part`-файлы редакторов, превью и альтернативные раскладки. [Полный реестр](audit-settings.md#полный-файловый-реестр-libfeaturespages) отмечает это, включая оставшиеся nonmobile-пути, которые не являются целью нового дизайна.

### Карта основных возможностей

| Область | Уже работает | Основа для v2 |
|---|---|---|
| Главная и история | Текущий Home — сразу чат; drawer содержит список, глобальный поиск, ассистентов, создание/временные чаты. | Новая стартовая страница и нижняя навигация — новый UI над `HomeMobileScaffold`, `SideDrawer` и текущими сервисами; backend истории остаётся. |
| Чат | Текст, документы/изображения, модель, reasoning, ASR, TTS, Markdown/code, streaming, поиск, действия сообщения, recovery. | Перестроить chrome/composer, сохранить pipeline и lazy message list. |
| Очередь | FIFO сохраняется, редактируется, восстанавливается; отправка во время ответа уже означает постановку в очередь. | Видимое количество и нижний лист всей очереди. Существующий panel показывает последние три и может скрыть следующий элемент. |
| Работа агента | LLM workspace tools и внешний ACP переводятся в общую ленту; план, карточки, ошибки и разрешения уже существуют. | Раздельные подписи «ассистент», «модель», «агент», «папка»; читабельный progress без выдуманного процента. |
| Файлы и команды | Workspace policy, produced/referenced/modified metadata, nullable unified diff, shell jobs, file previews. | Сводка **переданных инструментами** изменений текущего ответа. Полный Git diff и rollback — другая задача. |
| Linux / терминал | PRoot, mount/env/mirrors, PTY-сессии, STDIO MCP. | Новая мобильная оболочка поверх существующих managers; вкладки не пересоздают PTY. |
| Браузер | Общий живой WebView, minimise/adopt без reload, плавающее окно, агентские browser tools. | Сохранить controller и маленькое окно; согласовать его с клавиатурой и composer. |
| Мини-приложения | Store, версии, сервер, фоновые задачи, журнал ошибок, ярлык, share/delete; web host. | Каталог карточек и видимые ошибки. Создание через агента, не фиктивный «магазин приложений». |
| Расписания | Native schedule service; редактор recurrence, дат/дней, prompt/model/assistant, notifications, run history. | Доступ из «Работы» и настроек; не смешивать расписание с текущим shell job. |
| Память | Global/assistant scope, архив/редактор/trace, модель pipeline, старые данные и cleanup. | «Данные и память», чёткие статусы ошибок; новая observable pipeline state — отдельная доработка. |
| Модели/вход | OpenAI/Claude/Google и совместимые provider configs; multiple keys, сетевые параметры; OAuth ChatGPT, Claude, Grok, Kimi Code, OpenRouter. | Понятный выбор «ключ API / вход в аккаунт». OAuth не означает наличие подписки, лимитов или одинаковых возможностей у всех сервисов. |
| Голос | System/network/local ASR, загрузка моделей, system/network TTS, playback policy и floating player. | Один раздел с двумя задачами «Ввод голосом / Озвучивание». Протоколы сохраняются. |
| Фон | Coordinator + application-owned FlutterEngine + native FGS, owners, Stop, privacy, approvals, recovery после interruption. | UI статусов и system notification polish. Foreground service не гарантирует выживание после force-stop/OEM kill. |

Важные точки входа: [home_mobile_layout.dart](../../../lib/features/home/pages/home_mobile_layout.dart#L25), [chat_input_bar.dart](../../../lib/features/home/widgets/chat_input_bar.dart#L992), [ComposerStatusStrip](../../../lib/features/home/widgets/composer_status_strip.dart#L44), [queued_input_queue.dart](../../../lib/features/home/controllers/queued_input_queue.dart#L46), [ACP translator](../../../lib/core/services/acp/acp_turn_translator.dart#L418), [workspace metadata](../../../lib/core/services/workspace/workspace_tool_metadata.dart#L38), [browser session](../../../lib/core/services/browser/browser_agent_session.dart), [документ background-work](../../android/background-work.md). Остальные точные пути и строки — в аудите runtime.

### Что уже хорошо и что мешает

**Переиспользовать:** feature structure + Provider/Drift; `ColorScheme` и `AppSemanticColors`; `SurfaceLadder`; `ChatBubbleStyle.resolve`; cached frosted backdrop; `SectionCard`, общие settings rows, `CustomBottomSheet`, tactile/haptics; Lucide adapter; существующие `flutter_animate`/`animations`; отдельно зарегистрированные app/code fonts. Нет причины переписывать ACP transport, БД чатов или движок Markdown ради нового вида.

**Централизовать:** `design_tokens.dart` пока содержит лишь часть отступов/радиусов. Четыре theme constructors повторяют component settings; theme/display pages дублируют press/row/switch helpers. Inline code использует `Colors.white12`/`#F1F3F5`, Mermaid — отдельные palette literals; новые semantic роли нужны и этим поверхностям. Примеры: [theme_factory.dart:159](../../../lib/theme/theme_factory.dart#L159), [theme_settings_page.dart:287](../../../lib/features/settings/pages/theme_settings_page.dart#L287), [display_settings_widgets.dart:120](../../../lib/features/settings/pages/display_settings_widgets.dart#L120), [markdown_with_highlight.dart:684](../../../lib/shared/widgets/markdown_with_highlight.dart#L684).

**Исправлять точечно:** `Icons.broken_image/insert_drive_file` ещё есть в [chat_message_widget.dart:377](../../../lib/features/chat/widgets/chat_message_widget.dart#L377); большинство настроек уже Lucide. Header segment может иметь 36×30, Stop — 32×32, approval button — высоту 36: [chat_header_switcher.dart:133](../../../lib/features/home/widgets/chat_header_switcher.dart#L133), [running_tool_bar.dart:157](../../../lib/features/home/widgets/running_tool_bar.dart#L157), [workspace_tool_ui.dart:319](../../../lib/features/chat/widgets/workspace_tool_ui.dart#L319). Для Android новые targets должны быть ≥48×48dp.

### Главные UX-проблемы

1. «Модели и сервисы» объединяет несвязанные задачи: голос, MCP, Linux, агенты, память, расписания и мини-приложения. 26 корневых строк почти не объясняют различия. «Внешний вид и поведение» дополнительно смешивает визуальные настройки, генерацию и фон.
2. У настроек браузера есть баннер полного доверия, но переключатель доверия находится в другом разделе. Журналы скрываются при выключенном logging; диагностика открывается жестами на About. Путь должен быть предсказуемым.
3. Модель, профиль ассистента и внешний агент ощущаются как один выбор, хотя отвечают за разные вещи. Установка агента не означает готовое подключение модели.
4. Рабочая область в верхних маленьких сегментах, дополнительные действия в composer, задачи в настройках — пользователь вынужден помнить местоположение каждого инструмента.
5. Очередь, план, mode/env/status и несколько overlays конкурируют за высоту над клавиатурой. Компактный summary должен открывать полноценные детали, а не прятать важное разрешение.
6. Вид устаревает из-за множества равнозначных строк, мелкого текста, слабых opacity hints и разрозненных радиусов, а не из-за отсутствия современной библиотеки. Иерархия и токены дадут больше, чем повсеместное размытие.

## 2. Дизайн и поведение

### Одно направление

**«Место для мысли и дела».** Главная приглашает начать разговор и показывает недавние чаты/ожидающее решение. Ответы модели читаются как хороший документ: открытая поверхность, ясные заголовки, таблицы, сдержанные действия. Работа агента становится понятной последовательностью: текущий шаг → план → инструмент → файлы → решение пользователя. Нет светящихся панелей, декоративного terminal chrome или обещаний «магического» процента готовности.

Нижняя навигация: **Чаты / Работа / Приложения / Настройки**. Она остаётся в обзорных разделах. Внутри разговора уступает место вводу; «Назад» и системный Android Back возвращают к списку. «Работа» открывает связанные файлы, терминал и браузер; из них есть явный возврат в чат. Drawer/поиск и доступ к временным чатам/ассистентам сохраняются, не исчезают вместе со старой оболочкой.

На главной не ставим случайные AI-рекомендации и не отправляем запрос для каждого приветствия. Недавние чаты, наличие живой задачи и ожидающего решения получаются из текущих данных. Состояние без модели получает один CTA «Подключить модель», без чатов — «Начать разговор», без Linux — «Настроить рабочую область».

### Компоновка телефона и доступность

- Поля по краям 20dp, в composer 12dp; основные действия в нижней части, строки и верхние иконки ≥48×48dp. В макете единица CSS px моделирует Flutter dp, не физический пиксель экрана.
- Обычный текст ≥4,5:1, крупный ≥3:1, функциональные иконки/границы ≥3:1 там, где это требуется WCAG AA. Тонкие декоративные разделители могут быть слабее; у input используется `outlineStrong`.
- Ничего значимого не обозначается только цветом: «Ждёт решения», чек, ошибка, заголовок. У иконок есть semantics/tooltip, у переключателей — checked state.
- 390×844 — демонстрационный viewport. В продуктовых PR дополнительно проверяются 320/360dp, Android insets, клавиатура, landscape и text scaling 200%; текст переносится, списки прокручиваются. Для `TextScaler` сохранить nonlinear accessibility scaling, не перемножать коэффициенты дважды.
- Reduced motion: убрать shimmer/пульсацию/движущийся градиент, duration=0 по системному запросу. Обычный tap feedback короткий; motion не заменяет текстовый статус.

### Дизайн-токены

Цвета ниже — **выбранная палитра для макетов**, а не литералы для всех будущих Flutter widgets. Сначала `ColorScheme`/HCT → semantic roles → component roles → явные пользовательские overrides. Custom/dynamic accent проходит тот же resolver. Saved overrides имеют приоритет; v2 не исправляет их молча.

| Роль | Светлая | Тёмная | Назначение |
|---|---|---|---|
| page | `#F5F5F3` | `#121419` | Общий фон |
| surfaceCard | `#FFFFFF` | `#1B1E26` | Карточки, sheets, поля |
| surfaceInset | `#EDEDEA` | `#262A34` | Тихие вложенные поверхности |
| onSurface | `#20222B` | `#F2F3F7` | Основной текст |
| onSurfaceVariant | `#626570` | `#B1B5C3` | Подписи и пояснения |
| primary | `#5142D9` | `#C6BEFF` | Акцент и действия |
| onPrimary | `#FFFFFF` | `#26204E` | Текст залитой кнопки |
| primaryContainer | `#EEEBFF` | `#302A4C` | Выбор, сообщение пользователя |
| outlineVariant | `#DEDEDF` | `#363B48` | Декоративные линии |
| outlineStrong | `#80838E` | `#8B91A3` | Значимые границы полей |
| success / container | `#176544` / `#E6F3EB` | `#91DAB2` / `#17382A` | Завершение и изменения `+` |
| warning / container | `#80500C` / `#FBF0DB` | `#F0CA85` / `#3B3020` | Ожидание решения |
| error / container | `#AE2737` / `#FAE8EB` | `#FFAFB9` / `#48252D` | Ошибка и изменения `−` |
| codeSurface | `#EEF0F4` | `#252A34` | Код с отдельной token palette |

White на `#5142D9`: **6,71:1**. Dark text `#121419` на `#C6BEFF`: **10,71:1**; white на том же акценте лишь **1,72:1**, поэтому тёмная кнопка имеет тёмный текст. Glass/custom bubble требуют проверки **скомпонованного** цвета с фоном, а не этой таблицы.

| Система | Значения |
|---|---|
| Шрифт | Manrope в макетах; Android system sans остаётся надёжным вариантом продукта. Сохранённый app font не переопределять. Google Fonts и импорт TTF/OTF используют текущий pipeline. |
| Типографика | Hero 32/37, 800; page title 28/34, 750; header 18/25, 700; section 17/24, 800; body message 16/26, 400; control 14/21, 600–700; metadata 12/18, 500. |
| Код | Пользовательский code font, иначе monospace 13/20; terminal использует свой размер и палитру. App font не меняет код случайно. |
| Радиусы | Control 12–16; card/message 20; composer/sheet 22–28; badge 7; thumbnail 14. Круг — только swatch/avatar/status, не любая кнопка. |
| Отступы | 4, 8, 12, 16, 20, 24, 32; основной gutter 20, composer gutter 12. |
| Иконки | Lucide 22dp, stroke 1,8; secondary 18dp при прежнем target 48dp. Brand monogram — знак Moru, не заменитель системной иконки. |
| Motion | Tap 120ms, sheet/section 180–220ms easeOutCubic; только transform/opacity и ограниченные size transitions. |
| Elevation | Разделять поверхностями и outline; тень только у floating browser/sheet, не у каждого сообщения. |

**Техническая оговорка про шрифты:** нынешний `AppFontWeights` нормализует Android w500→w400 и w600+→w500; Google Fonts importer берёт regular face. Более сильные заголовки макета требуют явной правки shared typography/weight policy и проверки реально загруженных faces. Один token `fontWeight=800` сам по себе не даст такой же результат. Не навязывать Manrope через сеть при первом запуске; если выбирать его новым default, добавить лицензированный встроенный face отдельно, сохранив старый выбор пользователей.

### «Внешний вид» с живым превью

Порядок: **превью → режим/тема → акцент → шрифт/размер → сообщения → фон → код/Markdown → редкие детали**. Превью содержит русский текст, user/assistant message и код, остаётся видимым при прокрутке. В продукте sample дополнить CJK/emoji/таблицей и возможностью свернуть превью при большой системной типографике.

Режим «Система / светлая / тёмная» и визуальные опции **палитра / AMOLED (pure background) / Glass** сохраняют реальную ортогональность current prefs. Четыре понятных плитки в макете — shortcuts к этой комбинации, не повод объединять saved keys в новую enum. «Как в системе» не уничтожает выбранную палитру; светлый pure остаётся white, dark pure — black.

Все нынешние options остаются: dynamic/system accent, встроенные/custom palettes, собственный цвет, layered surfaces, Glass/economy/blur и role overrides; app/code font, Google Fonts/local import, chat scale; default/frosted/solid, fit-content/split paragraphs, оба цвета/opacity/border role; wallpaper/mask/composer opacity; Markdown/code/table/formula/diagram настройки. Часто используемое — на общей странице, тонкое — в нижних листах. [Полная карта внешнего вида](audit-settings.md#полный-инвентарь-display-тем-стиля-шрифтов-изображений-и-профиля).

Подписи «Свободно / Пузырьки / Текст» в HTML иллюстрируют будущие presentation presets. В существующем коде сохранённые стили — default/frosted/solid: они остаются в точных настройках. Новые presets, если принимаем их, разрешаются в существующие overrides; это явная функция PR, а не выдуманное уже существующее API.

**Черновик локальный.** Preview не вызывает setter `SettingsProvider`. Его `copyWith` разделяет реальные `_preferences` и не является безопасным sandbox. Нужны чистый theme resolver, immutable draft и commit адаптер. «Применить» сохраняет, Back/«Отмена» отбрасывает, при ошибке записи draft остаётся для retry. Font import нельзя начинать destructive setter во время preview: он удаляет старый managed file. Glass restore snapshot и localOnly `chatFontScale` сохраняют нынешний scope. [Подробности контракта](audit-theme.md#практический-путь-к-unified-tokens-и-live-preview).

HTML действительно меняет тему, accent/onPrimary, шрифт, размер, message preview, фон/код/Markdown без записи; RGB contrast adjustment — демонстрация, не замена Flutter HCT. Toast и переходы между файлами показывают границы прототипа; OAuth/команды/установка в нём не выполняются.

## 3. Новая структура настроек

Корень содержит **ровно восемь разделов**. Поиск сохраняет старые labels как синонимы и открывает конкретный control с новым breadcrumb. Важно включить не только `SettingsProvider`: MCP timeout, workspace/env, schedules и assistant settings живут в других providers/models.

| Раздел | Первый уровень | Редкое глубже |
|---|---|---|
| Внешний вид | Превью, темы/акцент, шрифт/размер, сообщения, фон, код | Role overrides, advanced theme, animation/economy, rendering |
| Модели и подключения | Подключения, ключ/вход, модели по умолчанию | Provider groups, multiple keys, balance, requests/network, search services, MCP endpoints/auth |
| Чаты и ответы | Отправка, модель в чате, генерация, названия, повтор/ошибки | Контекст, OCR, retries, навигация сообщений, быстрые фразы |
| Ассистенты и агенты | Ассистенты, установленные ACP агенты | Prompts, agent mode, tool enablement, навыки, книга мира, instruction injection, health |
| Рабочая область и инструменты | Рабочие области/Linux, браузер, расписания, мои приложения | Shell policy, schemas/approval, phone control, PRoot/mount/env/mirrors, app web server |
| Голос | Распознавание, озвучивание, сервис | ASR/TTS model/voice/format/network/download и playback policy |
| Данные и память | Память, профиль, копии, место, статистика | Memory scope/prompts/trace/legacy; WebDAV/S3/snapshots/retention/cleanup |
| Приложение | Язык, вибро, фон/уведомления, About | Android permissions/channels/battery/autostart, overlay layout, логи и диагностика |

### Было → стало: все корневые пункты

| Сейчас (`settings_page.dart`) | Новый путь |
|---|---|
| Управление телефоном | Рабочая область и инструменты → Управление телефоном |
| Цветовой режим | Внешний вид → Режим |
| Внешний вид и поведение | Внешний вид; поведение → Чаты и ответы; язык/вибро/фон → Приложение |
| Ассистент | Ассистенты и агенты → Ассистенты |
| Модель по умолчанию | Модели и подключения → Модели по умолчанию |
| Провайдеры | Модели и подключения → Подключения |
| Поиск | Модели и подключения → Дополнительно → Поисковые сервисы |
| Синтез речи | Голос → Сервисы TTS и ASR |
| MCP | Модели и подключения → Дополнительно → MCP |
| Агенты | Ассистенты и агенты → Агенты |
| Браузер | Рабочая область и инструменты → Браузер |
| Рабочее пространство и среда | Рабочая область и инструменты → Рабочие области и Linux |
| Задачи по расписанию | Рабочая область и инструменты → Задачи по расписанию |
| Мои приложения | Рабочая область и инструменты → Мои приложения; тот же каталог в нижней навигации |
| Веб-сервер | Рабочая область и инструменты → Мои приложения → Веб-сервер |
| Навыки | Ассистенты и агенты → Навыки |
| Книга мира | Ассистенты и агенты → Книга мира |
| Память | Данные и память → Память |
| Быстрая фраза | Чаты и ответы → Быстрые фразы |
| Добавление инструкций | Ассистенты и агенты → Добавление инструкций |
| Сетевой прокси | Модели и подключения → Дополнительно → Сетевой прокси |
| Резервное копирование | Данные и память → Резервные копии |
| Хранилище чатов | Данные и память → Хранилище |
| Статистика | Данные и память → Статистика |
| Журналы | Приложение → Диагностика → Журналы |
| Инструменты и разрешения | Рабочая область и инструменты → Инструменты и разрешения |

**Полная карта каждого вложенного пункта с точным русским label, ключом и `файл:строка`: [audit-settings.md](audit-settings.md).** Здесь сгруппирован корень; приложение содержит granular rows, а не потерю редких настроек. В частности: 15 текущих browser action toggles, все display behavior/rendering/haptics controls, light/dark message role fields, memory editor/archive/legacy, TTS/ASR редакторы, OAuth usage/cache, provider custom body/headers и все search service поля. Отдельно помечены служебные/retired/nonmobile keys, которые не надо превращать в новые Android настройки.

Некоторые старые пути отражают прежние labels: «Провайдеры» становится «Подключения», «Поиск/MCP» уходят в «Дополнительно». При реализации новая навигация и search breadcrumbs обновляются вместе; app preference IDs остаются прежними. Browser capabilities шире текущих 15 переключателей: каталог имеет 27 actions. Показ остальных 12 — отдельное расширение UI, не будто они уже были настройками.

## 4. Мастер первого запуска

1. **Язык.** Предвыбор по устройству; все существующие языки, не только три показанных. «Пропустить» оставляет текущий/default locale.
2. **Тема.** Система/светлая/тёмная; краткое превью, ссылка на полную кастомизацию позже. «Пропустить» оставляет system и текущую палитру.
3. **Модель.** Два пути: ключ API или вход в аккаунт. Затем существующий provider editor/login, проверка и выбор из реально доступных моделей. Вход/ошибка/возврат из браузера сохраняют этот шаг. «Пропустить» открывает приложение без модели с ясным CTA подключения.
4. **Linux и агенты, необязательно.** Сначала оценка реального download/free space и существующий environment installer; затем выбранный agent install/check. Можно отложить, начать обычный чат сразу. Не требовать Linux для LLM и не запускать скрытую установку по одному toggle.

Четыре **экрана решений** не означают четыре клика для OAuth/Linux: их реальные flows длиннее и уже есть. Мастер хранит только прогресс и подтверждённые настройки; его marker не заменяет database installation/recovery markers. Для существующих установок не стартует автоматически и не сбрасывает saved settings. Permissions/background dialogs показываются в контексте первого реального запуска задачи, не всем при первом старте.

## 5. Честная реализуемость

| Макет | На существующей основе | Новая работа / предел |
|---|---|---|
| Главная, список, навигация | ChatService/assistant/workspaces/miniapps | Новый mobile shell/dashboard и переходы; не нужен новый storage |
| Модель + reasoning | `showModelSelectSheet`, `showReasoningBudgetSheet`, capability resolver | Общая композиция; сохранять off/auto/custom/XHigh/Max и inheritance/perChat semantics |
| LLM-чат | Timeline, incremental Markdown, content notifier, selection/actions | Новый UI, не новый renderer или eager list |
| Агент/план | ACP plan и tools, локальный TaskPlanRegistry | ACP execution tool не создаёт Moru ToolRun. Нижний status может брать активный ACP tool card через отдельный projection, а не показывать фальшивый local runtime ID |
| Изменения файлов | `WorkspaceToolMetadata` + существующий diff viewer | Сводка по ответу, nullable counts/diff; shell может не дать diff; повторные изменения одного файла показывать как отдельные operations, не складывать в псевдо-Git итог |
| Разрешение | Live approval identity + native actions | Новый UI и hit areas; redacted payload и owner checks остаются. После Stop/kill старый запрос закрыт, не восстановлен для повторного исполнения |
| Работа: вкладки | File browser/preview, PTY manager, BrowserAgentSession | Новая мобильная композиция и overlay coordinator; IndexedStack/TickerMode не должны сбрасывать живые controllers |
| Внешний вид | Темы/HCT/bubble resolver/fonts | Чистый resolver, isolated draft, staging fonts и надёжный commit. Это сложнее, чем собрать старые страницы в один ListView |
| Мини-приложения | Store/jobs/server/error journal/shortcuts | UI карточек, поиск, актуальные status/errors; не путать declared server command с running server |
| Уведомление | Native `BackgroundNotifications` уже умеет approval actions/identity/unlock/privacy | Системный Android шаблон контролирует раскладку. Макет — описание информации/действий; фон, размеры и кнопки нельзя гарантировать как в PNG на всех OEM |

Код позволяет реализовать всё основное направление без переписывания приложения. Самые дорогие части: **безопасный draft внешнего вида, сохранение поведения streaming/scroll, объединение мобильной навигации и overlays**. ACP/БД/PRoot остаются.

### Риски и миграция

- **Blur и анимация.** Не размывать каждую карточку настроек. Переиспользовать cached backdrop/bucket lifecycle, economy/reduced motion, TickerMode/lifecycle pause. На реальном arm64 телефоне измерить raster/frame time/memory до и после; Android с бюджетным GPU обязателен. Пока никаких выдуманных FPS.
- **Длинные чаты.** Сохранить `MessageListView`/SuperSliverList, streaming notifier/checkpoints/selection и height estimates. 1 000+ сообщений, длинный Markdown/code/table, new chunks во время scroll, смена шрифта, возвращение после клавиатуры, редактирование очереди. Bench `timeline_scroll_bench.dart` даёт наблюдения, не заменяет assertions.
- **Настройки.** Не переименовывать ключи, palette IDs, assistant/conversation overrides; null означает inheritance. Не менять default у старой установки. Pure остаётся pure, explicit custom/dynamic/font/color overrides сохраняются. Glass on/off должен вернуть свой restore snapshot даже после restart.
- **Сохранение Apply.** Appearance объединяет Drift business prefs, локальные prefs и font files. Это не одна существующая транзакция. Для business fields — одна транзакция на прежних ключах; local-only записи/font replacement требуют staged apply с ошибкой/retry и безопасным порядком замены. Проектировать recovery именно этой операции, не новую общую settings architecture. Crash между шагами не должен удалить единственный рабочий font или оставить ложное «Применено».
- **Данные.** Первый UI PR вообще без schema migration. Новые данные onboarding — отдельный local marker. Если позднее понадобится persistent ACP plan/activity — отдельная схема/миграция с backup/restore fixtures; не включать её скрытно в дизайн.
- **Разрешения/фон.** Одно решение соответствует approvalId/run/message текущего выполнения. Уведомления остаются PRIVATE/с redaction по preference; actions перепроверяют freshness и разблокировку. Force-stop не обещает продолжения команды. Фоновые задачи и выбранные permissions не меняются ради внешнего вида.

## 6. Внедрение небольшими PR

Это план будущей реализации, не команда выполнить её в этом PR. Каждый шаг имеет законченный пользовательский или инфраструктурный результат, собирается самостоятельно; ни один не вводит оболочку «пока потом перепишем». Оценки — рабочие дни одного опытного Flutter-инженера вместе с проверкой и обычным review, не календарное обещание. Android/device validation может добавить ожидание устройств.

**Общие ограничения:** Android-only, текущие package/application ID и signing; один arm64 APK; существующие зависимости/Provider/Drift; все пользовательские настройки/чаты сохранены; Lucide; targets 48dp; AA; RU плюс сохранение EN/ZH; нет новых desktop/native Web targets. Новые labels через ARB + gen-l10n; не менять version в этом docs PR. Для будущего релиза — version/release notes по AGENTS.md.

**Пять особенно важных классов проверки:** импортированные fonts/Glass при cancel и crash; старые custom/pure/dynamic настройки после restore; длинный streaming чат с клавиатурой; stale permissions после Stop/kill; OEM background/system notification layout.

| PR / объём | Точная область и законченный результат | Проверка перед следующим PR |
|---|---|---|
| **1. Geometry/typography tokens** · 2–3 дня, S | `lib/theme/design_tokens.dart`, `theme_factory.dart`, `app_font_weights.dart`, `shared/widgets/section_card.dart`, `ios_settings_rows.dart`, `ios_tactile.dart`: роли размеров/шрифтов/targets; общий builder component themes без изменения palette IDs. Устранить копии по мере использования shared components, не массово весь lib. | Theme equality и unrelated settings rebuild; shared widget semantics/48dp; RU/EN/ZH + scale 200%. Старые пользовательские font/weight choices без сброса. |
| **2. Настройки: восемь разделов** · 2–3 дня, M | `features/settings/pages/settings_page.dart`, новые section pages в той же feature; `search/settings_search_index.dart`, navigator/anchors. Перенести реальные входы, сохранить дочерние editors. Search знает новый breadcrumb и старые синонимы. | Контрольная карта 26 roots + granular leaves; поиск открывает конкретный control; скрытые logs/diagnostics доступны предсказуемо, no writes при навигации. |
| **3. Чистый theme/preview resolver** · 2–3 дня, M | Выделить `AppearanceSnapshot` и `resolveAppearance(snapshot, dynamicLight, dynamicDark)` рядом с `app_theme_builder.dart`; root и старый message preview пользуются одной функцией. Исправить cache same-ID custom palette, brightness/fonts/economy. Никакого нового persistence. | `theme_factory_test`, `app_theme_builder_test`, message preview tests; сравнение preview/runtime light/dark/custom/dynamic; changing preview не пишет prefs. |
| **4. Экран внешнего вида и Apply** · 4–6 дней, L | `features/settings` appearance page/draft/commit adapter; существующие settings setters/business routing/fonts import по прежним ключам. Preview + drawers всех настроек; staged font replacement, Glass restore, Apply/Cancel/error. | Restart/cancel/back/failed write/crash fixtures; localOnly scale остаётся local; old font не удалён до успешного commit; Glass on/off/restart и backup roundtrip. |
| **5. Новая палитра и semantic code roles** · 2–3 дня, M | `theme/palettes.dart`, `app_semantic_colors.dart`, `surface_ladder.dart`; inline/Mermaid/code роли в `shared/widgets/markdown_with_highlight.dart`. Новый selectable вариант; новый default только fresh install при отдельном принятом решении. | AA всех semantic pairs + actual composite; custom/AMOLED/light/dark; Markdown selection/copy/code collapse, cache invalidation, old bubble overrides. |
| **6. Мобильная главная и навигация** · 3–4 дня, M | `features/home/pages/home_mobile_layout.dart`, dedicated mobile dashboard/list и существующий `side_drawer.dart`; новый shell использует прежние chat/workspace/miniapp routes. Чат становится detail без нижней nav. | Back stack, temporary chats, ассистенты, поиск/архив, no-model/empty/busy состояния; навигация не пересоздаёт stream/PTY/WebView. |
| **7. Модель и reasoning в одном выборе** · 1–2 дня, S | `features/model/widgets/model_select_sheet.dart`, `features/chat/widgets/reasoning_budget_sheet.dart`: единый bottom sheet, capability-driven levels и пояснения. Provider login/editor не переписывать. | `perChatModelEnabled`, follow-assistant/inherit, unavailable model; off/auto/1024/16000/32000/custom и optional 64000/128000; no unsupported levels/ошибочной записи global model. |
| **8. Composer, очередь, вид ответа** · 3–4 дня, M | `chat_input_bar.dart`, `message_list_view.dart`, `chat_message_widget.dart`, timeline projector/visibility; новые chrome/tokens, полная очередь, явные Send/Stop. Использовать текущие incremental rendering/selection/recovery. | FIFO/edit/remove/drain/restart и draft send acknowledgement; длинный streaming + scroll anchor, font-scale, keyboard; pending approvals видны при showToolCards=false. |
| **9. Агент: работа, файлы, решения** · 2–3 дня, M | `composer_status_strip.dart`, plan/running chips, timeline/tool detail и `acp_chat_bridge.dart` presentation adapter. ACP status из tool parts, local status из ToolRun; partial file summary + текущий diff viewer. Permission target ≥48 и readable payload. | Agent without plan/diff/modes; failed edit не counted changed; nullable/truncated/repeated-file diff; local + ACP одновременно; stale approval после Stop, AgentErrorPart/OAuth recovery сохраняются. |
| **10. Работа и браузер** · 2–3 дня, M | `workspace_files_mobile_layout.dart`, `workspace_navigation.dart`, terminal opening/screen, `browser_mini_window.dart`, `app_overlays.dart`: вкладки/возврат в чат и placement coordinator. Retain managers/controller; zero new filesystem policy. | PTY input/focus/resize, живой браузер minimise/adopt без reload, файлы/preview permissions/path boundary; keyboard не перекрыт browser/TTS/status overlay. |
| **11. Первый запуск** · 2–3 дня, M | Новая mobile onboarding feature + route gate в `main.dart`; локальный progress marker. Existing provider OAuth/editor и environment installer/agent catalog. Skip в каждом шаге, pending login/install не считается завершённым. | Fresh/existing/restore installation, язык EN/RU/ZH, skip всех шагов, cancel OAuth/download, нехватка места, no Linux/no model; database recovery не маскируется onboarding marker. |
| **12. Приложения, notifications и device polish** · 2–3 дня, M | `mini_apps/pages/mini_apps_page.dart`, existing sheets/status APIs; `lib/core/services/mobile_background.dart` и native `background/BackgroundNotifications.kt`: необязательная redacted command/workspace summary в approval payload, information/actions polish + ARB. Профилирование blur/scroll на телефонах, финальная проверка копий и AA. | Versions/jobs/errors/server actual state, shortcuts/share/delete; private/redacted locked notification, channel disabled, exact stale target; OEM/device cases, reduced motion/economy и PNG/golden актуальных UI. |

Базовый объём **27–40 инженерных дней**; рабочую реализацию можно выпускать после каждого среза. S — несколько shared widgets/один flow; M — feature UI и её регрессионные сценарии; L — несколько хранилищ и commit/recovery. Дизайн можно принять частями: сначала настройки/tokens, затем shell/chat, затем runtime polish.

Каждый продуктовый PR: format **только изменённых Dart**, `dart analyze --fatal-infos lib test integration_test`, `flutter test`, три Python Android policy/APK/keep-rules suites из AGENTS.md; localization gate при ARB; штатный CI arm64 signed release APK для PR этого репозитория (fork PR — debug). Не добавлять тесты, повторяющие каждый отступ: проверять реальные contracts, accessibility, сохранение и сложные состояния. Benchmark-скрипты сохранять как наблюдения, не объявлять зелёным тестом производительности.

### Чего я сам не рекомендую делать

- **Стекло по умолчанию и blur на каждом сообщении/карточке.** Стоимость GPU, слабый контраст на обоях, сложные cache lifecycle. Glass остаётся осознанным вариантом с economy и preview.
- **Процент выполнения проекта/ETA.** План даёт N/M отмеченных шагов, не реальную оценку. Показывать название шага и elapsed команды.
- **Полный Git-review/rollback из tool metadata.** Сейчас сведения неполные. Макет ограничен файлами, о которых сообщили tools; полный review нужен отдельным продуктовым запросом.
- **Универсальная «панель всех процессов» в первом редизайне.** Native aggregate уже знает active owners, но подробный публичный owner inventory требует API. Для первой версии достаточно chat status и существующих detail sheets.
- **Новая модель доверия «всегда разрешать этот проект» ради красивой карточки.** Сохраняем текущую policy и одноразовый ответ ACP. Не расширять разрешение из эстетических соображений.
- **Обязательный Linux/агент или Google Font при onboarding.** Это сеть, место и ожидание до первого простого разговора. Дать попробовать обычный чат и отложить настройку.
- **Pixel-perfect кастомное Android notification окно.** Использовать системный шаблон, доступные actions/privacy; OEM внешность принадлежит Android.
- **Массовая миграция чатов/настроек или смена state management.** Для этого дизайна не нужна; повышает риск потери данных и цену review.

## 7. Воспроизведение и проверки этого пакета

```bash
python3 docs/design/v2/build_mockups.py
python3 docs/design/v2/render_mockups.py
```

Для рендера нужны Python Playwright, Pillow и Chromium. Они уже доступны в использованной cloud-среде; это инструменты документации, в `pubspec` ничего не добавлено. Путь Chromium по умолчанию `/usr/bin/chromium`. Font и SVG встроены в HTML; renderer блокирует внешнюю сеть и ждёт `document.fonts.ready`. Доска собирается из тех же PNG, не из других макетов.

Лицензии: [Lucide ISC](LUCIDE-LICENSE.txt), SVG из tag `0.468.0`; [Manrope OFL](MANROPE-LICENSE.txt), файл из Google Fonts. `lucide-icons.json`/`Manrope.ttf` — источники для воспроизведения; копия одного HTML не требует их отдельно.

Итоговые команды, результаты и границы проверки записаны в [verification.md](verification.md). Это доказательства checks документационного PR. HTML/Chromium не доказывает Flutter performance, TalkBack, OEM notifications, успешную установку агента или реальный OAuth; эти проверки привязаны к будущим PR выше.

## Все экраны

| Сценарий | Светлая PNG | Тёмная PNG | HTML |
|---|---|---|---|
| 01. Главная | [Открыть](png/home-light.png) | [Открыть](png/home-dark.png) | [Светлый](html/home-light.html) · [Тёмный](html/home-dark.html) |
| 02. Список чатов | [Открыть](png/chats-light.png) | [Открыть](png/chats-dark.png) | [Светлый](html/chats-light.html) · [Тёмный](html/chats-dark.html) |
| 03. Чат с моделью | [Открыть](png/chat-light.png) | [Открыть](png/chat-dark.png) | [Светлый](html/chat-light.html) · [Тёмный](html/chat-dark.html) |
| 04. Агент: ход работы | [Открыть](png/agent-light.png) | [Открыть](png/agent-dark.png) | [Светлый](html/agent-light.html) · [Тёмный](html/agent-dark.html) |
| 05. Агент: изменения файлов | [Открыть](png/agent-files-light.png) | [Открыть](png/agent-files-dark.png) | [Светлый](html/agent-files-light.html) · [Тёмный](html/agent-files-dark.html) |
| 06. Агент: запрос разрешения | [Открыть](png/permission-light.png) | [Открыть](png/permission-dark.png) | [Светлый](html/permission-light.html) · [Тёмный](html/permission-dark.html) |
| 07. Выбор модели и рассуждений | [Открыть](png/model-light.png) | [Открыть](png/model-dark.png) | [Светлый](html/model-light.html) · [Тёмный](html/model-dark.html) |
| 08. Работа: файлы | [Открыть](png/files-light.png) | [Открыть](png/files-dark.png) | [Светлый](html/files-light.html) · [Тёмный](html/files-dark.html) |
| 09. Работа: терминал | [Открыть](png/terminal-light.png) | [Открыть](png/terminal-dark.png) | [Светлый](html/terminal-light.html) · [Тёмный](html/terminal-dark.html) |
| 10. Работа: плавающий браузер | [Открыть](png/browser-light.png) | [Открыть](png/browser-dark.png) | [Светлый](html/browser-light.html) · [Тёмный](html/browser-dark.html) |
| 11. Работа: браузер поверх чата | [Открыть](png/browser-mini-light.png) | [Открыть](png/browser-mini-dark.png) | [Светлый](html/browser-mini-light.html) · [Тёмный](html/browser-mini-dark.html) |
| 12. Настройки: корень | [Открыть](png/settings-light.png) | [Открыть](png/settings-dark.png) | [Светлый](html/settings-light.html) · [Тёмный](html/settings-dark.html) |
| 13. Настройки: модели и подключения | [Открыть](png/connections-light.png) | [Открыть](png/connections-dark.png) | [Светлый](html/connections-light.html) · [Тёмный](html/connections-dark.html) |
| 14. Настройки: чаты и ответы | [Открыть](png/chat-settings-light.png) | [Открыть](png/chat-settings-dark.png) | [Светлый](html/chat-settings-light.html) · [Тёмный](html/chat-settings-dark.html) |
| 15. Внешний вид: живое превью | [Открыть](png/appearance-light.png) | [Открыть](png/appearance-dark.png) | [Светлый](html/appearance-light.html) · [Тёмный](html/appearance-dark.html) |
| 16. Первый запуск: язык | [Открыть](png/onboard-language-light.png) | [Открыть](png/onboard-language-dark.png) | [Светлый](html/onboard-language-light.html) · [Тёмный](html/onboard-language-dark.html) |
| 17. Первый запуск: тема | [Открыть](png/onboard-theme-light.png) | [Открыть](png/onboard-theme-dark.png) | [Светлый](html/onboard-theme-light.html) · [Тёмный](html/onboard-theme-dark.html) |
| 18. Первый запуск: подключение модели | [Открыть](png/onboard-model-light.png) | [Открыть](png/onboard-model-dark.png) | [Светлый](html/onboard-model-light.html) · [Тёмный](html/onboard-model-dark.html) |
| 19. Первый запуск: Linux и агенты | [Открыть](png/onboard-linux-light.png) | [Открыть](png/onboard-linux-dark.png) | [Светлый](html/onboard-linux-light.html) · [Тёмный](html/onboard-linux-dark.html) |
| 20. Мини-приложения | [Открыть](png/apps-light.png) | [Открыть](png/apps-dark.png) | [Светлый](html/apps-light.html) · [Тёмный](html/apps-dark.html) |
| 21. Android: агент ждёт разрешения | [Открыть](png/notification-light.png) | [Открыть](png/notification-dark.png) | [Светлый](html/notification-light.html) · [Тёмный](html/notification-dark.html) |

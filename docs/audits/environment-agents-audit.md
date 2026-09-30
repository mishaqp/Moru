# Аудит Linux-окружения и ИИ-агентов Moru

Дата: 30 сентября 2026. Репозиторий: `mishaqp/Moru`, ветка `claude/moru-v0-1-16-audit-s69yji`, [PR #79](https://github.com/mishaqp/Moru/pull/79).
Снимок анализируемого кода: [`2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d`](https://github.com/mishaqp/Moru/tree/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d).
Изменяется исключительно этот документ. Код, настройки сборки и версия приложения не изменяются.

**Статус: промежуточный отчёт.** Разделы сохраняются отдельными коммитами по мере завершения. «Не проверено» означает отсутствие завершённого аудита, а не отсутствие проблем.
[AGENTS.md:1-160](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/AGENTS.md#L1-L160) и [docs/releases/v0.1.47.md:231-241](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/docs/releases/v0.1.47.md#L231-L241) прочитаны; учитываются уже выполненные исправления v0.1.47. Лента чата, темы и обычные провайдеры моделей вне области аудита. Настройки провайдера рассматриваются только как входные данные ACP.

Метки доказательств: **Код** — вывод из прочитанных исходников; **Запуск** — выполненная в этой сессии проверка; **CI** — просмотренные логи точного SHA; **Сообщено владельцем** — уже выполненная проверка из задания; **Гипотеза** — требует воспроизведения. Телефон и Android WebView здесь недоступны. S/M/L — относительный объём работы, не обещание сроков.

## 1. Краткое резюме — 10 главных проблем

1. **A-01:** открытый ACP-чат сохраняет старые параметры API, заголовки, права папок и переменные окружения.
2. **A-02:** выключение root не прекращает уже работающие root-процессы; возврат владельцев выполняется одновременно с их дальнейшими записями.
3. **A-03:** «Проверить связь» проверяет ACP-приветствие, но сообщает о работоспособности без запроса к модели.
4. **A-04:** ежедневные действия, обслуживание и опасные операции смешаны на длинном экране «Окружение».
5. **A-09:** «Обновить» может повторно установить старую выбранную rootfs, хотя уже предложена новая версия.
6. Не проверено — будет заполнено после аудита нативного запуска и PTY.
7. **A-06/A-07/A-08:** отмена native-подготовки и ранних package-запусков неполна; голый dpkg обходит ожидание lock.
8. Не проверено — будет заполнено после аудита остальных ACP-путей и веб-интерфейсов.
9. Не проверено — будет заполнено после аудита рабочих файлов и безопасности.
10. Не проверено — будет заполнено после проверки покрытия тестами и документации.

**A-05 не входит в главные дефекты:** названия `desktop` сами по себе не доказывают мёртвый код; раскладки вызываются через адаптивный выбор ширины Android-экрана. Окончательная оценка ниже будет дополнена.

## 2. Карта системы

Предварительная карта по прочитанным точкам входа:

- «Окружение» → `EnvironmentPane` → `EnvironmentInstaller` / `EnvironmentProvider` → `WorkspaceChannel` → `WorkspacePlugin` → скачивание, распаковка и подготовка rootfs.
- Пакеты → `EnvironmentDependencies` → команды в `AndroidProotRuntime` → нативный exec → `apk` или `apt-get`.
- Терминал → `TerminalSessionManager` → `openPty` → `PtySession` / JNI → оболочка Linux.
- Агенты → `AcpAgentManager` → npm и подготовка конфигурации → STDIO-процесс; `AcpChatSessions` хранит процесс и ACP-сессию каждого чата.
- Веб-интерфейсы агентов → `AcpAgentWebServers` → процесс в том же runtime → loopback-адрес → встроенный браузер.
- Оба режима используют одну rootfs; флаг root выбирает `ProotCommand` либо `ChrootCommand` с `moru_chroot.c`.

Основания: [lib/core/services/sandbox/mobile_workspace_bootstrap.dart:40-75](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/sandbox/mobile_workspace_bootstrap.dart#L40-L75), [lib/main.dart:662-738](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/main.dart#L662-L738), [lib/core/services/sandbox/android_proot_runtime.dart:92-175](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/sandbox/android_proot_runtime.dart#L92-L175).
Полная карта рабочих файлов, документов и фоновых команд — **не проверено**.

## 3. Находки

| ID | Область | Серьёзность | Описание и доказательство | Файл:строка | Сценарий: шаги → ожидалось → на самом деле | Предлагаемое исправление | Объём |
|---|---|---|---|---|---|---|---|
| A-01 | ACP / настройки запуска | Высокая | **Код; ранее подтверждено владельцем.** `_launchKey` не содержит `anthropicProvider`, `responsesApi`, `headers`, `mount.readOnly` и переменных окружения. Веб-сравнение учитывает параметры провайдера и полные `Mount`, но пользовательские переменные также не являются его входом. | [lib/core/services/acp/acp_chat_sessions.dart:165-177](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_chat_sessions.dart#L165-L177); [lib/core/services/acp/acp_chat_sessions.dart:254-266](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_chat_sessions.dart#L254-L266); [lib/core/services/acp/acp_agent_web_servers.dart:279-293](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_agent_web_servers.dart#L279-L293); [lib/core/services/acp/acp_agent_manager.dart:550-555](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_agent_manager.dart#L550-L555) | Запустить агент в чате → поменять формат API / требуемый заголовок / переменную / writable-папку на readonly → отправить следующую задачу. Ожидалось: новый процесс с актуальными настройками и правами. Фактически: совпадает старый ключ, используется прежний процесс; новые значения не попадают в уже запущенное окружение. | Общий неизменяемый снимок эффективного запуска для ACP и веба: API, headers, переменные, mounts с правами и поколение runtime; сравнивать без вывода секретов. | M |
| A-02 | Root / жизненный цикл процессов | Высокая | **Код; ранее подтверждено владельцем.** Переключение сохраняет флаг, но не завершает терминалы, ACP, веб, мини-серверы и фоновые команды. При выключении флаг меняется до `chrootFixOwner`; продолжающие работу root-процессы могут снова создавать чужие файлы. | [lib/core/services/sandbox/environment_installer.dart:699-712](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/sandbox/environment_installer.dart#L699-L712); [lib/features/workspace/widgets/environment/environment_pane.dart:346-359](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/widgets/environment/environment_pane.dart#L346-L359); [lib/core/services/acp/acp_chat_sessions.dart:254-266](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_chat_sessions.dart#L254-L266) | Запустить терминал/агента в root → выключить «Быстрый режим» → продолжить команду в прежней сессии. Ожидалось: все последующие операции через PRoot, файлы доступны Moru. Фактически: живой процесс сохраняет root и старые монтирования; возврат владельцев не препятствует новым root-записям. | Общий барьер переключения: запретить новые запуски, остановить и дождаться всех потребителей runtime, вернуть владельцев, затем завершить смену режима и перепроверить систему. | L |
| A-03 | Проверка агента / UX-честность | Средняя | **Код; ранее подтверждено владельцем.** `check` делает loopback-probe и `start/initialize`, затем возвращает `agent.info`, не создавая модельный запрос. Русский статус звучит как проверка способности отвечать. | [lib/core/services/acp/acp_agent_manager.dart:389-419](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_agent_manager.dart#L389-L419); [lib/core/services/acp/acp_agent.dart:188-210](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/acp/acp_agent.dart#L188-L210); [lib/l10n/app_ru.arb:1148](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/l10n/app_ru.arb#L1148) | Установить агент, задать неверный ключ или несовместимый формат API → «Проверить связь». Ожидалось: проверка подключения к модели. Фактически: если агент откладывает авторизацию до запроса, ACP-приветствие успешно и экран пишет «Работает». | Разделить статусы «Программа запускается», «Инструменты Moru доступны», «Модель ответила»; настоящий короткий запрос к модели запускать отдельной понятной проверкой. | M |
| A-04 | Экран «Окружение» | UX | **Код; ранее подтверждено владельцем.** Одна лента объединяет состояние, файлы, пакеты, зеркала, переменные, обслуживание, выбор образа, PRoot и root. | [lib/features/workspace/widgets/environment/environment_pane.dart:424-611](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/widgets/environment/environment_pane.dart#L424-L611); [lib/features/workspace/widgets/environment/environment_pane.dart:614-646](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/widgets/environment/environment_pane.dart#L614-L646) | Новичок открывает настройки, чтобы запустить агента → ожидает последовательность «подготовить → выбрать → начать». Фактически: должен сам понять несколько разнородных блоков и различие установки системы, пакетов, ремонта и сброса. | Главный экран «Linux»: состояние + терминал/файлы/агенты; подготовка одной задачей; пакеты отдельным экраном; зеркала/переменные/PRoot в «Дополнительно»; замена/сброс в «Обслуживание». | L |
| A-05 | Android wide layout / названия | Низкая | **Код; reachability проверена.** `*_desktop_layout.dart` реально импортируются и выбираются через `useDesktopWorkspaceLayout` → `ResponsiveHelper.isDesktop`. Их нельзя удалять только из-за имени. | [lib/features/workspace/workspace_layout.dart:5-7](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/workspace_layout.dart#L5-L7); [lib/features/workspace/pages/environment_page.dart:19-23](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/environment_page.dart#L19-L23); [lib/features/workspace/pages/workspace_files_page.dart:36-47](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/workspace_files_page.dart#L36-L47) | Открыть раздел на широком Android-планшете/складном экране → ожидается адаптивная раскладка. Фактически: предусмотрен переход в desktop-названные виджеты; все четыре пути достижимы при ширине Android-окна ≥1200 логических пикселей. Это не функциональный дефект, только вводящее в заблуждение имя. | Сохранить эти раскладки. Переименование desktop → wide необязательно; удаления по имени не делать. | S |

| A-06 | Установка / «Исправить» | Средняя | **Код.** Cancel прерывает HTTP, но не native extract/patch. После распаковки отмена проверяется; во время repair не проверяется вообще. | [lib/core/services/sandbox/environment_installer.dart:168-204](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_installer.dart#L168-L204); [lib/core/services/sandbox/environment_installer.dart:419-456](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_installer.dart#L419-L456); [android/app/src/main/kotlin/com/psyche/kelivo/workspace/WorkspacePlugin.kt:347-355](https://github.com/mishaqp/Moru/blob/undefined/android/app/src/main/kotlin/com/psyche/kelivo/workspace/WorkspacePlugin.kt#L347-L355) | Начать установку → дождаться «Распаковка» → Отмена. Ожидалось: операция прекращается и освобождает экран. Фактически: native-запись продолжается до завершения, затем удаляется staging. Во время «Исправить» → Отмена: repair всё равно объявляет ready. | Идентификатор native-операции; cancel-and-await для hash/extract/patch; отдельный статус «Отменяем…»; один протокол отмены для установки и ремонта. | M |
| A-07 | Пакеты / блокировка dpkg | Средняя | **Код + безопасный запуск.** Перед apt с Lock::Timeout=60 выполняется голый `dpkg --configure -a`; при чужой блокировке `set -e` прерывает сценарий немедленно. | [lib/core/services/sandbox/environment_dependencies.dart:185-190](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L185-L190) | На Debian/Ubuntu начать apt в терминале → пока он держит lock, установить пакет в UI. Ожидалось: ограниченное ожидание очереди. Фактически: ранний dpkg завершается до apt; установка проваливается. Fixture: exit 2 за 0.021 с, apt не вызван. | Общий шлюз UI-транзакций + ограниченное ожидание для configure; корректная отмена. Не удалять lock-файлы. Проверять реальную конкуренцию dpkg. | M |
| A-08 | Пакеты / ранняя отмена | Средняя | **Код; временное окно на телефоне требует воспроизведения.** `_run` выдаёт runId, но не передаёт `isCancelled`; runtime ещё ожидает readiness. Cancel может попасть в незарегистрированный ID, после чего exec всё равно запускается. | [lib/core/services/sandbox/environment_dependencies.dart:302-307](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L302-L307); [lib/core/services/sandbox/environment_dependencies.dart:345-356](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L345-L356); [lib/core/services/sandbox/android_proot_runtime.dart:93-99](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/android_proot_runtime.dart#L93-L99); [lib/core/services/sandbox/channel_command_runtime.dart:100-108](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/channel_command_runtime.dart#L100-L108) | Установить пакет → немедленно Отмена, пока идёт native probe. Ожидалось: процесс не запускается либо сразу прекращается. Фактически: ранний native cancel не находит ID; отсутствующий callback позволяет последующий запуск. Для детерминированной проверки задержать fake probe. | Передавать `isCancelled: () => _cancelled` и использовать уже реализованный двойной guard channel-runtime; тест до и после native-регистрации. | S |
| A-09 | Обновление образа | Средняя | **Код.** Check предлагает Ubuntu 24.04.4, но следующий переход в установку подставляет сохранённый 24.04.3. Это замена rootfs с отдельным подтверждением, а не apt upgrade. | [lib/core/services/sandbox/environment_installer.dart:235-249](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_installer.dart#L235-L249); [lib/features/workspace/widgets/environment/environment_pane.dart:234-252](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_pane.dart#L234-L252); [lib/features/workspace/widgets/environment/environment_pane.dart:316-325](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_pane.dart#L316-L325); [lib/features/workspace/pages/environment_download_page.dart:58-84](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/pages/environment_download_page.dart#L58-L84) | Установить default 24.04.3 → Проверить обновления → повторно нажать строку с 24.04.4 → принять выбор без ручного изменения → подтвердить замену. Ожидалось: предложенный новый образ. Фактически: переустанавливается 24.04.3, гостевые пакеты заменяются; следующий check снова предлагает 24.04.4. | Передать предложенный image в update-навигацию; не менять сохранённый выбор при read-only check; назвать операцию «Заменить системой версии …» и показать последствия. | S |
| A-10 | Зеркала / замена rootfs | Низкая | **Код.** Выбор зеркала хранится отдельно; после замены/сброса и установки UI считает его активным, хотя новая rootfs получила собственные config-файлы. Обычная установка пакетов правильно переигрывает сохранённый выбор. | [lib/core/services/sandbox/environment_installer.dart:446-488](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_installer.dart#L446-L488); [lib/core/providers/environment_provider.dart:331-341](https://github.com/mishaqp/Moru/blob/undefined/lib/core/providers/environment_provider.dart#L331-L341); [lib/features/workspace/widgets/environment/environment_pane.dart:1038-1041](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_pane.dart#L1038-L1041); [lib/core/services/sandbox/environment_dependencies.dart:246-268](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L246-L268) | Выбрать зеркало apt/apk → заменить rootfs → до установки пакетов сравнить UI с `/etc/apt/…` или `/etc/apk/repositories`. Ожидалось: выбранное активное зеркало применено. Фактически: preference прежний, гостевой config из нового архива; явный apply/установка пакетов затем исправляет. | При подготовке новой rootfs применить совместимые сохранённые зеркала либо честно показать «сохранено, ещё не применено». Проверять preference и реальные файлы вместе. | M |
| A-11 | Пакеты / готовность к агентам | UX | **Код.** Prepare считает только missing; unknown не мешает выводу «Всё нужное агентам установлено» и отключению кнопки. | [lib/features/workspace/widgets/environment/environment_dependencies_section.dart:135-136](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_dependencies_section.dart#L135-L136); [lib/features/workspace/widgets/environment/environment_dependencies_section.dart:203-233](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_dependencies_section.dart#L203-L233); [lib/l10n/app_ru.arb:5283](https://github.com/mishaqp/Moru/blob/undefined/lib/l10n/app_ru.arb#L5283) | Первое открытие пакетов во время probe либо после его ошибки. Ожидалось: «Проверяем / не проверено / повторить». Фактически: строки ещё unknown, но блок подготовки объявляет всё установленным. | Считать готовностью только installed для всех необходимых пакетов; unknown и failed — отдельные состояния с повторной проверкой. | S |

### A-05: результат проверки раскладок

Все четыре файла используются: [skills_page.dart:19-23](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/skills_page.dart#L19-L23), [workspaces_page.dart:89-94](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/workspaces_page.dart#L89-L94), environment и workspace_files из таблицы. [screen_type_helper.dart:11-14](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/shared/responsive/screen_type_helper.dart#L11-L14) выбирает `desktop/wide` по [breakpoints.dart:12-21](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/shared/responsive/breakpoints.dart#L12-L21), а не по ОС. При 900–1199 используется mobile workspace layout, при ≥1200 — wide. **Предложение удалить как мёртвый код отвергнуто.** Визуальная проверка планшета — только на устройстве.

### 3.1. Жизненный цикл установки

**Пройдено чтением кода и тестов:** install, cancel, repair, reset, swap/previous-rootfs, HTTP resume, проверка версии и перенос зеркал. A-06/A-09/A-10 описывают выявленные дефекты.

Установка сначала готовит staging, проверяет архитектуру и патчит образ; смена каталога выполняется после этого. Ошибка до swap сохраняет предыдущую систему; восстановления после разрыва rename покрыты [test/core/services/sandbox/environment_installer_test.dart:499-546](https://github.com/mishaqp/Moru/blob/undefined/test/core/services/sandbox/environment_installer_test.dart#L499-L546). Reset удаляет previous-rootfs раньше текущей системы, чтобы её не воскресил startup-recovery ([lib/core/services/sandbox/environment_installer.dart:213-231](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_installer.dart#L213-L231); [test/core/services/sandbox/environment_installer_test.dart:587-617](https://github.com/mishaqp/Moru/blob/undefined/test/core/services/sandbox/environment_installer_test.dart#L587-L617)). Это следует сохранить.

Частичная HTTP-загрузка привязана к источнику; 206 продолжает, 200 начинает заново, 416 проверяется как потенциально полный файл; digest обязателен, неверный архив удаляется. Существующие unit-сценарии: [test/core/services/sandbox/environment_installer_test.dart:157-208](https://github.com/mishaqp/Moru/blob/undefined/test/core/services/sandbox/environment_installer_test.dart#L157-L208), [test/core/services/sandbox/environment_installer_test.dart:249-354](https://github.com/mishaqp/Moru/blob/undefined/test/core/services/sandbox/environment_installer_test.dart#L249-L354). Это чтение тестов, не симуляция сети телефона. Процесс Android, ENOSPC в середине распаковки и конкретные legacy-миграции/SELinux после root — требуют отдельной проверки устройства (раздел 7).

### 3.2. Нативный runtime

Не проверено: процессы/FD, завершение потомков, PRoot/chroot binds, владельцы uid/gid после apt/postgres, SELinux.

### 3.3. Терминал и PTY

Не проверено: ресайз, клавиши, вставка, восстановление после сворачивания и завершения Android-процесса.

### 3.4. Пакеты

**Пройдено:** имена пакетов приняты из проверки владельца; прочитаны probes, команды apk/apt, версии, serial/batch, bounded logs, mirrors и cancel. A-07/A-08/A-11 — конкретные дефекты. APK использует `--wait 60`; apt-команды — Lock::Timeout=60, кроме раннего dpkg. Probe требует однозначный marker по каждому пакету ([lib/core/services/sandbox/environment_dependencies.dart:310-337](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L310-L337)), поэтому отсутствие вывода не выдаётся за installed.

**Запуск: настоящая блокировка dpkg в изолированном scratch admindir.** Python держал POSIX-lock scratch database; wrapper добавлял `--admindir`, apt wrapper только отмечал вызов. Пакеты хоста и его база не изменялись. Вывод:

```text
exit_code=2
elapsed_seconds=0.021
apt_called=false
dpkg: error: dpkg database lock was locked by another process
```

Групповая попытка хранит общий лог на `picked.first`, поэтому открытие другого участника не показывает исход всей группы ([lib/core/services/sandbox/environment_dependencies.dart:231](https://github.com/mishaqp/Moru/blob/undefined/lib/core/services/sandbox/environment_dependencies.dart#L231); [lib/features/workspace/widgets/environment/environment_dependencies_section.dart:423-458](https://github.com/mishaqp/Moru/blob/undefined/lib/features/workspace/widgets/environment/environment_dependencies_section.dart#L423-L458)). Нужен один видимый итог партии с состоянием каждого пакета; подробности включены в UX-разбор.

### 3.5. Агенты, ACP, MCP и веб

Не проверено: остальная установка/удаление/обновление, сессии, секреты, Codex через шлюз, cookie DeepSeek Harness и Android WebView.

### 3.6. Рабочие пространства и файлы

Не проверено: привязка, внешние папки, DocumentsProvider, AGENTS.md, фоновые команды и план.

### 3.7. Безопасность

Не проверено: полный аудит токенов, ключей, loopback, файловых границ и полномочий агента.

### 3.8. Тесты и документация

Не проверено: полная карта покрытия, пробелы и сверка документации.

## 4. UX-разбор экранов и новая структура

Не проверено — кроме предварительного A-04. Будут отдельно разобраны Окружение, Пакеты, Агенты, Рабочие пространства, Файлы/внешние папки и Терминал; сравнение с исходниками OmniBot и ReTerminal.

## 5. Что сделано хорошо и трогать не нужно

**Сообщено владельцем; повторно не запускалось в этом продолжении:**

- Все пять агентов установлены и ответили на ACP initialize на Alpine 3.24 и Debian 13. Это проверка процесса/протокола, не успешного обращения к каждой модели.
- Node обновлён до 24 через NodeSource на Ubuntu 22.04/24.04 и Debian 13.
- Имена всех пакетов раздела «Пакеты» проверены на Alpine 3.24 и Debian 13.
- Все ссылки на образы отвечали HTTP 200.
- SHA-256 arm64-образов Ubuntu 22.04/24.04 и Alpine 3.22–3.24 совпали. Debian: контрольные суммы **не подтверждены**. В продолжении выполнен curl для обеих закреплённых arm64-ссылок: HTTP 403, exit 22, загружено 0 байт; SHA-256 не вычислялся.
- Перед установкой проверяется свободное место.

**Запуск в предыдущей части этой же сессии:** 39 Python-тестов прошли, проверка русских ARB: `3613 EN = 3613 RU`, `bash -n tool/fetch_proot.sh` завершился с кодом 0. Локальный Flutter SDK отсутствует.

**CI точного SHA, логи просмотрены:** [PR Checks](https://github.com/mishaqp/Moru/actions/runs/36718836654): `No issues found!`, `6492 tests passed`; [Android arm64](https://github.com/mishaqp/Moru/actions/runs/36718835351): восемь C chroot-тестов прошли, `:app:testDebugUnitTest` / `BUILD SUCCESSFUL`. Это результаты CI, не новый запуск на телефоне.

### Выполненная дополнительная проверка Debian

Команда для каждого URL: `curl --fail --location --connect-timeout 15 --max-time 55 --output <scratch.tar.xz> --write-out '%{http_code} %{size_download}' <URL>`.
URL взяты из [rootfs_catalog.dart:196-236](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/core/services/sandbox/rootfs_catalog.dart#L196-L236). Вывод:

```text
debian13: curl exit=22; HTTP=403; size_download=0
debian12: curl exit=22; HTTP=403; size_download=0
curl: (22) The requested URL returned error: 403
```

Дополнительный запрос заголовков также получил HTTP/2 403, server: cloudflare. Это факт доступности из данного runtime; он не опровергает ранее сообщённый HTTP 200 из другой сети и не доказывает, что URL не работает на телефоне. Проверка SHA требует получить реальные байты архива.

## 6. План исправлений — отдельные проверяемые пререлизы

Предварительно:

1. Координатор жизненного цикла runtime и переключение root (A-02).
2. Единый снимок запуска агентов (A-01), поверх безопасного lifecycle.
3. Честная диагностика программы, MCP и модели (A-03).
4. Перестройка навигации и подготовки (A-04), после исправления состояний.
5. Итоговая матрица устройств, дистрибутивов и документация.

Не проверено — зависимости остальных находок и задачи, которые можно делать параллельно, добавляются после завершения анализа.

## 7. Проверки на телефоне для владельца

Предварительные сценарии (использовать тестовую рабочую папку и несекретные переменные):

1. **A-01:** запустить ACP-чат; задать `MORU_AUDIT_VALUE=before`; изменить на `after`; следующей командой агента прочитать переменную. Зафиксировать, потребовался ли новый процесс. Аналогично проверить смену прав тестовой внешней папки.
2. **A-02:** открыть root-терминал; `id -u`; выключить root; вернуться в ту же вкладку и повторить `id -u`. Ожидается остановленная прежняя сессия и новый процесс в выбранном режиме; PRoot может показывать гостевой uid 0, поэтому также фиксировать режим и возможность новой записи через Moru.
3. **A-03:** на тестовом провайдере поставить заведомо неверный ключ; «Проверить связь»; затем короткая задача агенту. Сопоставить успешное ACP-приветствие и ошибку реального запроса.
4. **A-06:** на тестовой установке нажать Отмена именно во время распаковки, затем во время «Исправить»; записать время до освобождения UI и итоговый статус. Не отключать питание ради этой проверки.
5. **A-07:** Debian/Ubuntu, два терминала/экран пакетов: во время реального `apt-get install` нажать установку другого пакета в UI; проверить ожидание/сообщение lock. Не удалять lock-файл и не убивать dpkg через SIGKILL.
6. **A-08:** нажать отмену сразу после старта установки пакета; после освобождения UI проверить, не продолжает ли native-процесс транзакцию. Детерминированный вариант требует fake channel с задержкой probe.
7. **A-09:** default Ubuntu 24.04.3 → Проверить обновления → повторный переход в установку; до подтверждения замены записать предвыбранную версию. Саму замену выполнять только на тестовой системе.
8. **A-10/A-11:** после тестовой замены проверить source-файл до установки пакетов; при первой проверке/ошибке сравнить строки unknown и итог Prepare.
9. Остальные проверки — **не проверено**, будут добавлены с точными действиями.

Не вставлять реальные ключи, cookie и токены в команды для журнала или в отчёт.

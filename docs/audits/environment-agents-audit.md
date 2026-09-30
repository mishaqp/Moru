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
5. Не проверено — будет заполнено после аудита жизненного цикла установки.
6. Не проверено — будет заполнено после аудита нативного запуска и PTY.
7. Не проверено — будет заполнено после аудита пакетов.
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
| A-05 | Android wide layout / названия | Низкая | **Код; оценка reachability ещё не завершена.** `*_desktop_layout.dart` реально импортируются и выбираются через `useDesktopWorkspaceLayout` → `ResponsiveHelper.isDesktop`. Их нельзя удалять только из-за имени. | [lib/features/workspace/workspace_layout.dart:5-7](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/workspace_layout.dart#L5-L7); [lib/features/workspace/pages/environment_page.dart:19-23](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/environment_page.dart#L19-L23); [lib/features/workspace/pages/workspace_files_page.dart:36-47](https://github.com/mishaqp/Moru/blob/2c7e9da53ed88e68e0bfedccedaebca3bb5e5d0d/lib/features/workspace/pages/workspace_files_page.dart#L36-L47) | Открыть раздел на широком Android-планшете/складном экране → ожидается адаптивная раскладка. Фактически: предусмотрен переход в desktop-названные виджеты; окончательный порог и все четыре пути пока не проверены. | После проверки всех вызовов сохранить нужные Android-wide раскладки; при чистке переименовать в wide/tablet, удалять только доказанно недостижимое. | S |

### 3.1. Жизненный цикл установки

Не проверено: завершить аудит отмены, сетевых обрывов, ремонта, сброса, замены, обновления, previous-rootfs и миграций.

### 3.2. Нативный runtime

Не проверено: процессы/FD, завершение потомков, PRoot/chroot binds, владельцы uid/gid после apt/postgres, SELinux.

### 3.3. Терминал и PTY

Не проверено: ресайз, клавиши, вставка, восстановление после сворачивания и завершения Android-процесса.

### 3.4. Пакеты

Не проверено: ошибки менеджеров пакетов, dpkg/apk locks, отмена, групповые исходы и прогресс.

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
- SHA-256 arm64-образов Ubuntu 22.04/24.04 и Alpine 3.22–3.24 совпали. Debian: **не проверено**, нужна загрузка через curl; urllib возвращал 403.
- Перед установкой проверяется свободное место.

**Запуск в предыдущей части этой же сессии:** 39 Python-тестов прошли, проверка русских ARB: `3613 EN = 3613 RU`, `bash -n tool/fetch_proot.sh` завершился с кодом 0. Локальный Flutter SDK отсутствует.

**CI точного SHA, логи просмотрены:** [PR Checks](https://github.com/mishaqp/Moru/actions/runs/36718836654): `No issues found!`, `6492 tests passed`; [Android arm64](https://github.com/mishaqp/Moru/actions/runs/36718835351): восемь C chroot-тестов прошли, `:app:testDebugUnitTest` / `BUILD SUCCESSFUL`. Это результаты CI, не новый запуск на телефоне.

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
4. Остальные проверки — **не проверено**, будут добавлены с точными действиями.

Не вставлять реальные ключи, cookie и токены в команды для журнала или в отчёт.

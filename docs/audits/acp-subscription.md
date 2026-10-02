# ACP: вход Claude Code и Codex по подписке

Дата: **02.10.2026 (UTC)**. База PR: `claude/moru-v0-1-16-audit-s69yji`.
Исследование адаптеров и нативных CLI выполнено отдельно от тестов Moru:

- [Claude Code: версии, исходники, протокол, login/status/logout и правила Anthropic](acp-subscription-claude.md).
- [Codex, OpenCode и Kimi: версии, исходники, device auth, storage и refresh](acp-subscription-codex-other.md).

## Выбор пути

Реализован **путь A**: официальный CLI сам проводит вход, хранит и обновляет
авторизацию. Moru запускает `claude auth login --claudeai` либо
`codex login --device-auth` в том же Linux runtime и с тем же постоянным auth
home, что и соответствующий ACP-запуск. Отдельно установленные официальные
CLI доступны через существующий install manifest Moru. Адаптер может включать
свою версию CLI; обе Claude-версии и Codex CLI passthrough проверены в
исследовании. Зафиксированные версии — снимок исследования, установка Moru
по-прежнему использует текущие npm-пакеты.

PTY и ACP terminal tools не требуются для проверенных native login flows:
они работают через pipes с открытым stdin. Moru не объявляет
`clientCapabilities.auth.terminal` или URL elicitation, поскольку не
реализует общий интерактивный terminal-auth/elicitation контракт. Обычный
`terminal: false` сохранён. Существующий `AcpAgent.authenticate` остаётся
доступным и проверяется фейковым протоколом, но выбранный вход проходит через
официальную CLI-команду. У Claude terminal method нельзя передавать в этот RPC.

| Агент и проверенная версия | Реальный результат без входа | Решение для Moru |
| --- | --- | --- |
| Claude ACP **0.85.0**, CLI **2.1.287**, bundled CLI **2.1.286** | При capabilities Moru `authMethods: []`; `session/new` успешен, первый prompt — **-32000** | Native login с HTTPS-ссылкой; пользователь вводит полный `code#state` |
| Codex ACP **2.1.1**, CLI **0.160.0** | `api-key`, `chat-gpt`; device method появляется с URL elicitation; `session/new` — **-32000** | Native device auth; код и ссылка доступны только на экране входа |
| OpenCode **1.18.34** | `opencode-login`; authenticate — пустой no-op; анонимный prompt ответил через бесплатный public default | Подписочный режим не добавлен: успешный ответ не доказывает вход или подписку |
| Kimi Code **2.1.1** | Terminal `login`; `session/new` — **-32000**; authenticate лишь проверяет готовность | Подписочный режим не добавлен: свой интерактивный flow и storage требуют отдельной реализации/проверки |

Подробные `agentCapabilities`, варианты initialize, опубликованные исходники
и ограничения каждого probe приведены в двух связанных аудитах. DeepSeek
Harness не менялся.

Путь B с OAuth-аккаунтами обычных провайдеров Moru не выбран. Экспорт bearer
в env не превращает его в native login с обновлением. Копирование refresh
token создаёт двух независимых владельцев rotation; токен с неподходящими
scope/client/backend или истёкший access token не обеспечивает подписочный
доступ. Копирование в разные homes не снимает этот риск. У Anthropic отдельно
документировано требование одобрения сторонних продуктов с claude.ai login
через Agent SDK; наличие ACP-адаптера и успешный технический login не
устанавливают такого одобрения. Источники и точная цитата сохранены в Claude
аудите. Проверка не делает вывод о статусе персонального форка.

## Хранение и запуск

`Assistant.agentAuthMode` принимает `provider` или `subscription`. Старые
сохранения и неизвестное значение используют `provider`; duplicate/export/
import сохраняют поле. `manage_assistants` поддерживает и валидирует его;
подписку можно выбрать только для Claude Code/Codex. Переключение обратно
сохраняет прежние provider/model pins. Для подписочного чата используется
логический источник `acp:<agentId>`, поэтому отсутствие API-провайдера не
блокирует отправку. Обычные заголовки/предложения не пытаются вызвать API
через этот источник; явно выбранная вспомогательная API-модель применяется.

Явное нажатие «Войти» выбирает подписку для нужного ассистента перед native
login: в деталях агента создаётся/используется его helper, а из карточки
ассистента меняется именно выбранный assistant ID. Открытие страницы и
«Проверить» не создают ассистента и не меняют режим. Повторное нажатие и
завершение async callback после закрытия страницы не запускают второй login.

- Claude: `CLAUDE_CONFIG_DIR=/root/.config/moru-agents/subscription/claude`;
  native `.credentials.json` хранится здесь, а не в временном каталоге.
- Codex: `CODEX_HOME=/root/.config/moru-agents/subscription/codex`;
  native `auth.json` хранится здесь, provider config Moru не записывается.
- Persistent auth homes имеют режим **0700**; native credential files
  создаёт официальный CLI. Moru не читает их и не помещает в свои бэкапы.
- Оба режима остаются независимыми от `/root/.config/moru-agents/codex`
  и прежнего provider launch. Подписка не получает ключи, endpoint/model
  overrides и cloud-provider флаги из Moru или guest login profile.
- Каждый Claude login/status/logout/ACP сохраняет отдельные
  `CLAUDE_CODE_TMPDIR=/tmp/mc/<id>` и `CLAUDE_CODE_CONTAINER_ID`.
  Root Codex по-прежнему изолирует daemon leaf через `/tmp/md/<id>`.
  Подготовка и запуск используют один проверенный режим runtime, leases
  завершаются после native stop. Общие владельцы и права workspace не меняются.

Login/logout останавливают процессы соответствующей подписки и блокируют
новые запуски до завершения операции. Отмена, dispose и удаление агента
останавливают также status/logout-команды и попытку, ещё ожидающую подготовки
Linux. Коды и ссылки очищаются при завершении/отмене.

У Codex refresh semaphore действует только внутри одного процесса, а запись
auth store не даёт межпроцессного CAS. Поэтому реализовано постоянное
ограничение: **один подписочный ACP-процесс Codex в Moru**. Переход из
простаивающего чата останавливает старый процесс до запуска нового и
восстанавливает контекст обычным load/resume/history механизмом. Второй
параллельный ответ сообщает, что Codex уже работает; после завершения или Stop
можно продолжить. API-режим и Claude сохраняют прежнюю параллельность. Внешний
CLI, запущенный вручную с тем же subscription home, не координируется Moru.

## Экран и статус

Настройки → Агенты → Claude Code / Codex: обратимый выбор режима и «Войти по
подписке». Отдельный мобильный экран показывает «Войти», «Проверить», «Выйти»
и состояние. Claude использует manual callback страницы провайдера, поэтому
выбранный flow не зависит от Android browser → guest loopback callback.
Codex показывает подсказку включить device-code login в Security ChatGPT.
HTTPS-ссылки открываются действием пользователя во внешнем браузере.

`claude auth status --json` должен вернуть exit 0, `loggedIn: true` и
`authMethod: claude.ai`. JSON разбирается только из stdout; stderr-предупреждения
не ломают результат. API-key/env OAuth источник не засчитывается как подписка.
Codex должен вернуть `Logged in using ChatGPT`; API-key login также не
засчитывается. Exit/error неизвестного формата означает «статус не проверен».
Сведения об аккаунте отбрасываются. Проверка локального login и ACP session
не проверяет квоту, оплату или успешный model response. «Проверить» сохраняет
Moru MCP loopback probe и использует уже живой Codex, не создавая конкурента.
Ответ ACP `auth_required` / **-32000** устанавливает «нужен вход».

`AcpAgentAuth` не использует install journal или chat/tool logger. Raw output
остаётся в bounded private parser; наружу выходят только безопасные enum и
allowlisted challenge для экрана. Подписочный `AcpSecretRedactor` скрывает
OAuth/JWT, access/refresh/device/user codes и auth URLs, включая фрагменты,
ANSI и границы chunks, до chat/error/card persistence. Локальные ID карточек
хешируются, protocol routing сохраняет исходные ID privately. ACP browser
tool с auth URL отклоняется до WebView; BrowserLibrary не сохраняет такие
адреса и при позднем обновлении title. WebView фильтрует message/level/source
до записи в console, включая redirect и JS-сообщения. Настройки входа
не используют shared browser console/history.

## Проверка и оставшиеся условия

Реальные official adapter/CLI probes дошли до внешнего шага авторизации без
живого аккаунта: Claude ждёт browser/code, Codex выдаёт device challenge;
неавторизованные ACP ошибки воспроизведены. PRoot source использует сеть
телефона; Linux IPv4 loopback probe успешен, но доступность callback с браузера
телефона не проверена. Выбранный manual/device flow не требует этого callback.

Host tests покрывают initialize/authenticate, lifecycle/check/logout/cancel,
credential-change startup race, единственный Codex-процесс и переключение
чатов, launch env/config, MCP/permissions/restore, секреты и совместимость
ассистентов. Итоговые команды и числа после полного чеклиста записаны в
[release notes](../releases/v0.1.47.md).

До принятия на телефоне с **Claude Pro/Max** и **ChatGPT Plus/Pro** требуется:

1. Установить/обновить агента, выбрать подписку без API-ключа, пройти вход и
   «Проверить», отправить реальный prompt, проверить ответ и Moru MCP approval.
2. Нажать «Выйти» во время/после ответа; новый prompt должен потребовать вход.
   Убедиться, что ссылки/коды/токены отсутствуют в чате, подробностях, журналах
   и browser history.
3. Перезапустить Moru/Linux, проверить сохранённый вход и восстановление чата;
   затем выйти и пройти повторный вход после перезапуска.
4. Повторить в PRoot и доступном root-chroot на Android arm64 glibc/musl,
   проверить отдельные временные каталоги, отмену входа, background/kill,
   native refresh/expiry, server revoke и переход между чатами Codex. Отдельно
   проверить доступ к native auth store при переключении PRoot ↔ root-chroot.
5. Вернуться к API-режиму: прежние provider/model/headers и параллельные
   API-чаты должны работать с сохранёнными настройками.

Живой аккаунт, оплаченный ответ, refresh/revoke на сервере, root-запуск полного
Flutter-чеклиста и физический Android в текущем cloud-сеансе не проверялись.
APK собирает CI; host-тесты не подменяют эту проверку.

Итоговый `flutter test --concurrency=4` под UID 1000: **7232 passed**, exit 0;
полный fatal-info analyzer, format/l10n и три Python-gate также успешны.
ACP/model/agent UI: **498 passed** с UID 1000/`umask 000` и **498 passed**
с UID 0 в user namespace/`umask 027`; auth/temp-dir с `umask 077`: **104 passed**.
После финальной правки интерфейса его **26 тестов**, а history/console
**64 теста** также прошли с UID 0/`umask 077`. Host UID 1000 отображён в UID 0
через `unshare --user --map-root-user`; это не проба физического Android root.
Native исследование выполнялось под обычным UID 1000. SHA-256 всех 54
изменённых Dart-файлов совпал до и после полного итогового прогона.

Дополнительно с UID 0/`umask 077` прошли **89 тестов** AssistantManagerTool,
model source, вспомогательных title, capability settings, send и chat bridge.

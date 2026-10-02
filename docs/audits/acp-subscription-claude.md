# Claude Code: подписочная авторизация через ACP

Дата проверки: **2026-10-01, UTC**. Исходный Moru: `af795269974fb38aa474ffd6afec537885ab17cb`, ветка `codex/acp-subscription-auth`. Документ фиксирует исследование интерфейсов до реализации в этой ветке, а не результаты проверки будущего Android UI.

## Рекомендация

Технически подходит **вариант A: авторизацией владеет официальный Claude CLI**. Moru запускает его login/status/logout в своей Linux-среде, открывает полученную ссылку во внешнем браузере Android и при необходимости передаёт введённый пользователем полный код в stdin CLI. CLI хранит, обновляет и удаляет credentials. Moru не извлекает access/refresh token из файлов и не переносит OAuth credentials своего обычного провайдера в agent env.

Одинаковый `CLAUDE_CONFIG_DIR=/root/.config/moru-agents/subscription/claude` должен действовать для авторизации и ACP agent. Это отдельное постоянное хранилище, не временный каталог запуска и не обычный `/root/.claude`. Для login/status/logout предпочтителен `claude-agent-acp --cli ...`: он использует **тот же native executable**, что и adapter. Отдельно установленный global `claude` сейчас отличается на одну версию.

Технический интерфейс не доказывает разрешение использовать подписку в стороннем продукте. Актуальная [официальная документация Agent SDK](https://code.claude.com/docs/en/agent-sdk) содержит дословно:

> Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead.

Adapter поддерживает subscription login, но его наличие не является документом об одобрении Moru. Проверка не устанавливает наличие такого одобрения и не делает юридического вывода о персональном использовании этого Android-форка. Вариант B с экспортом токенов не устраняет это ограничение.

## Версии и исполняемые файлы

Пакеты установлены с точными версиями в отдельный npm prefix вне репозитория. Каждый probe получил новый пустой `HOME`, новый `CLAUDE_CONFIG_DIR`, приватный временный каталог и окружение без Anthropic/API/OAuth credentials. Реальные аккаунты, коды и токены не использовались. Команды исполнялись на обычном Linux x64 под **UID 1000**, Node **24.19.0**; это не Android/PRoot. Отдельного запуска под настоящим root не было: исходный `HOME=/root` не определяет UID процесса.

| Компонент | Проверенная версия | Источник |
| --- | --- | --- |
| `@agentclientprotocol/claude-agent-acp` | **0.85.0**, `engines.node >=22` | [npm](https://www.npmjs.com/package/@agentclientprotocol/claude-agent-acp/v/0.85.0), npm `gitHead` **c84845272fe3c55c1f97759f00ee48a1356fccae** |
| `@anthropic-ai/claude-code` | **2.1.287**, `engines.node >=22.0.0` | [npm](https://www.npmjs.com/package/@anthropic-ai/claude-code/v/2.1.287) |
| `@anthropic-ai/claude-agent-sdk` | **0.3.286**, точная dependency adapter | [npm](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk/v/0.3.286) |
| `@anthropic-ai/claude-agent-sdk-linux-x64` | **0.3.286**, native CLI сообщает **2.1.286** | [npm](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk-linux-x64/v/0.3.286) |
| `@agentclientprotocol/sdk` | **1.5.1**, точная dependency adapter | [npm](https://www.npmjs.com/package/@agentclientprotocol/sdk/v/1.5.1), npm `gitHead` **c77d9bd204b6a05a10137632e46e84908191f9de** |

У Moru исходный install script ставит `@anthropic-ai/claude-code` и `@agentclientprotocol/claude-agent-acp` без ограничения версии. Эта таблица описывает snapshot npm во время исследования, а не пакеты, уже установленные на телефоне.

`claude-agent-acp` — `node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js`. [Его `claudeCliPath()`](https://github.com/agentclientprotocol/claude-agent-acp/blob/c84845272fe3c55c1f97759f00ee48a1356fccae/src/acp-agent.ts#L1723) сначала учитывает `CLAUDE_CODE_EXECUTABLE`, иначе разрешает native optional dependency **SDK**, выбирая glibc/musl по Node runtime. Он не ищет global `claude` в `PATH`.

В этом prefix реально разрешился `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`, версия `2.1.286`; SHA-256 native файла: `fe503f65c6289d59c23e5b21ae44f03583f997dd33a2cbfc75ab4f96fb8fc73f`. Global CLI: `node_modules/@anthropic-ai/claude-code/bin/claude.exe`, версия `2.1.287`; SHA-256: `3920489a5109cff5786a1a392c25277408ff22bc796d5edb9c16a60e5a1718f0`. Оба — native Linux binaries, несмотря на `.exe` в npm bin manifest второго.

## Что реально отвечает ACP

Проведены реальные STDIO JSON-RPC initialize/session/new/session/prompt. `protocolVersion` — **1**. Исходный Moru объявляет file tools и `terminal` false, не объявляя auth capability; результат нового adapter — **`authMethods: []`**, а не login method, который можно просто вызвать через `authenticate`.

| Объявление клиента / режим agent | Фактические authMethods |
| --- | --- |
| Текущие capabilities Moru: `fs` false, `terminal: false`, без auth | Пустой массив |
| `clientCapabilities.auth.terminal: true` | `claude-ai-login`, тип `terminal`, args `['--cli', 'auth', 'login', '--claudeai']`; `console-login`, args `['--cli', 'auth', 'login', '--console']` |
| Legacy `clientCapabilities._meta['terminal-auth']: true` | Те же terminal methods; дополнительно `_meta['terminal-auth']` с конкретными `command`, `args`, `label` |
| Terminal auth + `NO_BROWSER=1` | Только `claude-login`, тип `terminal`, args `['--cli']`; описание предлагает `claude /login` в TUI |
| Terminal auth + agent flag `--hide-claude-auth` | Только `console-login`; подписочная авторизация скрыта |

Это подтверждено исполнением и [исходником initialize](https://github.com/agentclientprotocol/claude-agent-acp/blob/c84845272fe3c55c1f97759f00ee48a1356fccae/src/acp-agent.ts#L2422). Remote detection также учитывает `SSH_CONNECTION`, `SSH_CLIENT`, `SSH_TTY`, `CLAUDE_CODE_REMOTE`. Менять обычный `terminal: false` для этого не требуется: terminal tools и terminal authentication — разные capability fields. Однако [ACP требует](https://agentclientprotocol.com/protocol/v1/authentication), чтобы клиент объявлял `auth.terminal` только при возможности воспроизвести настроенный agent invocation в интерактивном терминале; наличие узкого raw-pipe native login service само по себе не означает реализацию всех terminal auth methods.

Инициализация также объявляет:

- `loadSession: true`, `sessionCapabilities.resume: {}` и другие session capabilities;
- image и embeddedContext prompt capabilities, HTTP и SSE MCP;
- `agentCapabilities.auth.logout: {}`;
- push-only extension `agentCapabilities._meta.authStatus: {}`. Реально пришёл `_auth/status_update` с `{authStatus: {kind: 'none', label: 'Not logged in'}}`.

У неавторизованного agent **`session/new` успешно создал session** с режимами `default`, `acceptEdits`, `plan`, `auto`, `bypassPermissions`. Первый prompt без инструментов вернул **`-32000`, `Authentication required`**. Поэтому успешные initialize/session/new не доказывают доступ к подписке. Реального model response не получено.

Вызов `authenticate({methodId: 'claude-ai-login'})` проверен отдельно: **`-32603 Internal error`**, `error.data.details = 'Method not implemented.'`. [Adapter реализует authenticate только для gateway методов](https://github.com/agentclientprotocol/claude-agent-acp/blob/c84845272fe3c55c1f97759f00ee48a1356fccae/src/acp-agent.ts#L2678). Согласно ACP, клиент **MUST NOT** передавать terminal method в `authenticate`: нужно запустить отдельный процесс с его args. Native login process — рабочий интерфейс для текущего Claude adapter.

ACP `logout` отдельно существует: [adapter запускает native `auth logout`, очищает in-memory routing и заново читает status](https://github.com/agentclientprotocol/claude-agent-acp/blob/c84845272fe3c55c1f97759f00ee48a1356fccae/src/acp-agent.ts#L3019). Этот RPC исходный Moru ещё не предоставляет; native CLI command доступен независимо от RPC. Исследование проверило native logout, но не этот RPC на авторизованном аккаунте.

## Native login: raw pipes работают

Следующие команды действительно исполнены без PTY:

```sh
claude auth login --claudeai
claude auth status --json
claude auth logout
claude-agent-acp --cli auth login --claudeai
claude-agent-acp --cli auth status --json
claude-agent-acp --cli auth logout
```

[`--cli` в adapter](https://github.com/agentclientprotocol/claude-agent-acp/blob/c84845272fe3c55c1f97759f00ee48a1356fccae/src/index.ts#L12) spawn-ит native CLI с `stdio: 'inherit'`, передаёт остальные args, сигналы и exit status. Login direct CLI `2.1.287` и wrapper/native `2.1.286` дошли до одинакового шага, требующего внешней авторизации аккаунта, и оставались запущенными до явной остановки probe.

Проверенная последовательность stdout, без самой секретной ссылки:

```text
Opening browser to sign in…
If the browser didn't open, visit: <private authorization link>
Paste code here if prompted >
```

Native CLI регистрирует readline на stdin, принимает отдельные строки и разделяет `line.trim()` по `#`: необходимы обе части, **`authorizationCode#state`**. Их передаёт native `handleManualAuthCodeInput`; обмен и проверка принадлежат CLI. Проверка отправила заведомо некорректную несекретную строку уже после появления prompt: stderr напечатал `Invalid code. Please make sure the full code was copied.`, и процесс продолжил ожидание. Это доказывает, что stdin не игнорируется; успешный обмен настоящего кода не проверен.

Следует сохранять stdin открытым до завершения процесса. Закрытие stdin не является успешной авторизацией. Кнопка отмены должна останавливать auth run и его native child, освобождая listener и временные файлы.

### Две разные ссылки

Ссылка, которую native **печатает** в stdout, и ссылка, которую передаёт в **`BROWSER`**, различаются. Нельзя обещать автоматический loopback callback на основании stdout-only parser.

| Интерфейс | Проверенное назначение |
| --- | --- |
| Напечатанный fallback | HTTPS authorization host **`claude.com`**; redirect на HTTPS `platform.claude.com`, путь `/oauth/code/callback`: пользователь получает полный код для ручного ввода |
| Вызов приватного `BROWSER` helper | Authorization host также `claude.com`; redirect на `http`/`localhost`, ephemeral port, путь `/callback`: автоматический local callback |

Параметры PKCE S256 и state присутствуют в обоих случаях. Значения URL/state/code/challenge не публиковались и в документ не включены. `NO_BROWSER=1` менял предлагаемый ACP method на TUI, но в проверенном native `auth login` не убирал вызов `BROWSER` и печать fallback.

Практический минимальный Android handoff для raw-pipe service: **`BROWSER=/bin/true`** только в auth процессе, приватно прочитать stdout fallback, открыть его через external browser и предложить manual code input. Реальная проверка с `/bin/true` получила те же инструкции, ссылку и ожидание; в output не было ANSI/OSC8. Такой путь не зависит от Android → guest loopback callback.

Для automatic callback нужен приватный `BROWSER` helper, который передаст именно browser URL в Moru без обычных stdout/stderr журналов. В этой Linux x64 проверке helper действительно вызван. Listener автоматически созданного callback принимал TCP с `127.0.0.1`; соединение с `::1` не принимал. **Android browser/PRoot/root-chroot доступность не проверена**. Не следует исправлять URL заменой redirect host, копировать query в другое OAuth flow или принимать callback самим Moru вместо native CLI.

У существующего Moru терминала есть OSC1337 `KelivoOpenURL` interceptor и `TerminalPage` открывает HTTP(S) через `LaunchMode.externalApplication`. Но установленного guest `xdg-open`/`BROWSER` helper для этого в исходном дереве не найдено. Текущий terminal handler при неудаче открывания показывает URI в snackbar; его нельзя использовать как защищённый auth handoff без изменения этого поведения. Обычный shared browser записывает visit history, поэтому авторизационные ссылки должны идти во внешний auth/browser UI, а не в agent-owned shared browser/history.

### Status и признаки подписки

`auth status --json` в пустом store вернул **exit 1**, `loggedIn: false`, `authMethod: 'none'`, `apiProvider: 'firstParty'`. `auth logout` вернул **exit 0**; повторная авторизация не нужна для idempotent logout. Wrapper результаты совпали с direct CLI.

Текущая [CLI reference](https://code.claude.com/docs/en/cli-reference.md) документирует status JSON и exit codes: 0 — logged in, 1 — logged out. `authMethod` — `none`, `claude.ai`, `oauth_token`, `api_key`, `api_key_helper`, `third_party`. `configDirectory` появился начиная с `2.1.268`; у обоих проверенных native versions он точно соответствовал переданному `CLAUDE_CONFIG_DIR`. `projectsDirectory` также указывал внутрь этого каталога. В пустом store CLI создавал `.claude.json` и backup внутри config dir, оставляя свежий `HOME` пустым.

Для подписочного UI нельзя считать произвольный `loggedIn: true` доказательством подписочной авторизации. Нужны согласованные **`authMethod == 'claude.ai'`**, first-party backend и CLI result. Readable source native `2.1.287` добавляет `subscriptionType` при `claude.ai` и может добавлять email, org ID/name; у API key может присутствовать `apiKeySource`. Moru должен оставить только нужные безопасные признаки и отбросить account attributes. Status — локальная диагностика выбранного источника, не оплаченный model request и не проверка действующей квоты.

`setup-token --help` проверен: команда требует Claude subscription и предназначена для long-lived token. Сам `setup-token` не запускался до выдачи токена. [Официальная документация](https://code.claude.com/docs/en/authentication.md#generate-a-long-lived-token) описывает годичный OAuth token, который печатается в терминал, **не сохраняется CLI** и передаётся в `CLAUDE_CODE_OAUTH_TOKEN`; его scope ограничен inference. Для варианта A он не нужен: он заставил бы Moru становиться хранителем bearer и утратил бы обычный CLI-managed refresh store.

## Storage, expiry, refresh и logout

[Официальная credential management документация](https://code.claude.com/docs/en/authentication.md#credential-management): Linux хранит `.credentials.json` с режимом **0600**; по умолчанию `~/.claude`, при `CLAUDE_CONFIG_DIR` — внутри указанного каталога. Это plaintext Linux store, а не Android Keystore. Private app/rootfs permissions остаются существенной границей. Каталог должен быть приватным, устойчивым между запусками и не попадать в chat/workspace exports или Moru backup credentials.

Readable code **публично опубликованного native npm binary `2.1.287`** дополнительно устанавливает:

- `claudeAiOauth` содержит access token, refresh token, `expiresAt`, scopes и сведения о plan; текущие версии также могут хранить `refreshTokenExpiresAt`/client ID.
- Время жизни access token берётся из серверного `expires_in`, а refresh token lifetime — из соответствующего ответа; нельзя объявлять «всегда 8 часов» или бессрочный refresh token по этому исследованию.
- CLI имеет cross-process OAuth refresh lock с identity владельца, reread store и compare-and-swap при сохранении: результат обновления не должен перезаписать другую уже сохранённую refresh-token identity. Credentials writes дополнительно сериализуются store write lock.
- Невалидный refresh grant помечает refresh token непригодным и может очистить его в store; новый login является recovery. [Документация](https://code.claude.com/docs/en/authentication.md#renew-an-expiring-login) описывает предупреждение за три дня до истечения login и ошибку `Login expired · Please run /login`, когда обновление уже невозможно.
- Native logout пытается revoke сохранённый refresh token через сервер, с timeout **5 секунд**, затем очищает локальный store. Ошибка revoke перехватывается с сообщением о продолжении local logout. **Exit 0 не доказывает успешный server-side revoke**, особенно offline.

Эти детали подтверждены статическим исследованием именно опубликованного native artifact, не исходниками открытого `anthropics/claude-code` репозитория. Реальные сохранение/rotation/expiry/revoke подписки в этом исследовании не исполнялись, поскольку действующий аккаунт не подключался.

Новый native code также учитывает **`CLAUDE_SECURESTORAGE_CONFIG_DIR` перед `CLAUDE_CONFIG_DIR`**. Эту execution variable нужно удалить из inherited env либо явно направить в тот же subscription dir: иначе UI status configDirectory и настоящий credential store могут разойтись. Это проверено по native code, но не заявлено как стабильная документированная public API переменная.

После logout Moru должен прекратить активные subscription agent процессы/сессии и auth попытки перед следующим запуском. У native/SDK есть credential caches; удаление файла самим Moru не заменяет logout. Env API keys, helper credentials и внешние provider credentials не обязаны исчезнуть от CLI logout; источник нужно проверить заново в очищенном subscription launch.

## Конкретное подключение к Moru

Исходные entry points: `acp_provider_input.dart` отвергает `config.isOAuth`; `AcpAgentSpec.launch` для Claude всегда экспортирует provider API key в `ANTHROPIC_API_KEY` и `ANTHROPIC_AUTH_TOKEN` вместе с endpoint/model/header overrides; `_agentEnvironment` объединяет сохранённые execution variables и launch env. Поэтому просто разрешить `isOAuth` и передать access token не реализует вариант A.

Для subscription режима нужен собственный launch input/source, отличимый от provider API key, и отдельный auth lifecycle:

1. Выбранный режим/agent auth хранится как настройка; credentials остаются внутри native store. API provider mode продолжает существовать отдельно.
2. Все операции используют один persistent `CLAUDE_CONFIG_DIR`, тот же executable wrapper, тот же выбранный Linux runtime и согласованную environment policy.
3. У subscription запуска отсутствуют Moru provider credentials и чужие `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`/token descriptor overrides, cloud-provider flags и custom endpoint/headers. Их [precedence выше сохранённого login](https://code.claude.com/docs/en/authentication.md#authentication-precedence). Model selection должен пользоваться native Claude моделями, а не случайным API provider alias. User/settings `apiKeyHelper` и managed policies тоже могут изменить выбранный источник — status проверяет его фактически.
4. Auth command работает через приватный `WorkspaceRuntime.run` с открытым stdin. **Не использовать обычный install/check journal `AcpAgentManager._run`** для login output: там stdout/stderr добавляются в UI log. ACP JSON parser тоже не является transport для plain native CLI output.
5. Output parser держит небольшой bounded private buffer, принимает только ожидаемый HTTPS vendor link, обрабатывает split chunks, передаёт URI напрямую внешнему browser launcher и очищает buffer при завершении. URL, code и любые native error fragments из auth process не попадают в RequestLogger, chat, stderr tail, backup или clipboard автоматически. Native success проверяется exit status и последующим CLI status, а не наличием ссылки.
6. Manual input передаётся только в stdin текущего auth attempt одной строкой `code#state`, никогда argv/env/chat. Stop/dispose/runtime change отменяет попытку и закрывает её process children. Успешный login создаёт новый agent process/query, чтобы SDK перечитал credentials.

Для auth launcher сохраняются существующие ограничения Android Linux: Node >=22, PATH с `/root/.npm-global/bin`, runtime-ready check, `emulateHardLinks: false`, existing FS/DNS compatibility, launch-directory lease. **Каждый native/agent запуск** получает свой приватный `CLAUDE_CODE_TMPDIR=/tmp/mc/<22 ASCII characters>` и process-owned `CLAUDE_CODE_CONTAINER_ID=moru-<id>`; leaf `/claude-0` остаётся <=44 bytes. Не следует делать длинный `CLAUDE_CONFIG_DIR` также временной базой.

PRoot fake root может дать `getuid()==0`, а inode сохранить Android UID: fresh temp dir сам по себе не устраняет проверку owner native CLI. Использовать уже принятую Moru схему, не общий `/tmp/claude-0`, не chown чужих directories и не глобальный UID shim. Подробное отдельное исследование: [claude-code-temp-ownership.md](claude-code-temp-ownership.md). Persistent auth store и temp cleanup не должны смешиваться.

Текущие PRoot/chroot launchers не создают network namespace: root helper делает private mount namespace, PRoot использует network телефона. Это основание для device probe, не доказательство callback доступности. Existing `AcpMcpProbe` проверяет фактический guest → Moru loopback; обратный Android browser → native auth listener нужен отдельно, если реализован automatic callback.

## Вариант B: экспорт OAuth credentials провайдера

Передать access token Moru в `ANTHROPIC_AUTH_TOKEN` или `CLAUDE_CODE_OAUTH_TOKEN` технически означает другой credential source (`oauth_token`), а не native login. Такой путь имеет дополнительные обязанности:

- Scope/client contract обычного provider OAuth и поддерживаемого native login должны совпасть; неподтверждённый bearer нельзя считать официально поддержанным subscription integration.
- Env token выше persistent CLI login в precedence и может отправиться на оставшийся custom endpoint. Native source описывает env token без refresh token/expiry; он не становится CLI-owned rotating login.
- Экспорт refresh token в `.credentials.json` заставляет Moru ProviderOAuthService и CLI обновлять одну token identity независимо. Moru map `_refreshes` сериализует только свои Dart запросы; она не координируется с native cross-process lock/CAS. Rotation/reuse/logout может сделать другую копию stale или revoked. Несколько чатов увеличивают число копий и owners.
- Нужны явные single-owner refresh, rotation propagation, source-scoped logout, protections от writes после отмены и secret-aware diagnostics. Копирование tokens без этого не является завершённым вариантом B.
- Ограничение сторонних продуктов в официальной SDK документации остаётся. `setup-token` не является обходом этого вопроса и создаёт долгоживущий секрет, которым пришлось бы владеть Moru.

Для текущей задачи вариант A оставляет lifecycle у upstream и имеет реально проверенный CLI interface, поэтому он предпочтителен технически.

## Границы результата

**Проверено исполнением:** npm install закреплённых версий; обе native версии; ACP initialize с пятью вариантами capability/env; empty-store session/new и auth-required prompt; terminal-method authenticate refusal; raw-pipe login до ожидания внешней авторизации; BROWSER invocation и suppress helper; distinct printed/manual и browser/loopback redirect; manual stdin rejection; native status/logout direct и wrapper; изоляция config/home; loopback IPv4/IPv6 TCP listener на Linux x64.

**Подтверждено source/docs, но не действующим аккаунтом:** native credential layout, expiry fields, refresh locks/CAS, remote revoke/local logout semantics, status subscription/account fields, setup-token lifetime/storage, eligibility/policy text.

**Не проверено здесь:** успешный account login, фактическая подписка/квота и model response, refresh rotation/revoke сервера, native CLI под настоящим UID 0, сохранение account credentials на Android arm64 glibc/musl, Web/browser handoff на телефоне, PRoot UID/permission behavior этой авторизации, root-chroot callback, TUI onboarding/manual login в PTY, Android app background/kill/recovery. Эти ограничения должны остаться видимыми в итоговом описании реализации; unauthenticated initialize не превращает их в пройденные проверки.

Все generated login links и raw auth output оставались в mode-0700 temporary research directory вне Moru; после проверки private raw captures удалены, sanitized summaries сохранены. Ни ссылка, ни код, ни токен не включены в tool/chat вывод или этот файл. Сохранённый в репозитории результат — только этот аудит.

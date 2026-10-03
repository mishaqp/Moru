# ACP: подписочная авторизация Codex, OpenCode и Kimi

Дата проверки: **01.10.2026 (UTC)**. Это отдельный аудит официальных
CLI/адаптеров и их состояния без учётных данных. Авторизованный запрос к
ChatGPT/Kimi, реальный refresh, квота и работа на Android **не проверены**.

## Результат и рекомендуемый путь A

Для Codex подходит отдельная учётная запись, которой владеет официальный
CLI: `codex login --device-auth`, затем обычный `codex-acp` с **тем же
`CODEX_HOME`**. Подписочный home должен отличаться от home режима провайдера
Moru: `/root/.config/moru-agents/subscription/codex` вместо
`/root/.config/moru-agents/codex`. Это позволяет сохранить оба режима, не
перезаписывая подписочную конфигурацию файлом с `model_provider = "moru"`.
Логин через CLI действительно дошёл до ожидания подтверждения аккаунта через
обычные stdout/stderr pipes; PTY для этого Codex-пути не требуется.

Подписочный запуск не должен получать `MORU_CODEX_API_KEY`,
`OPENAI_API_KEY`, `CODEX_API_KEY`, `OPENAI_BASE_URL`, `CODEX_CONFIG`,
`DEFAULT_AUTH_REQUEST`, `MODEL_PROVIDER` или конфигурацию custom gateway из
режима провайдера. Сохранённые настройки/ключи провайдера остаются его отдельным
режимом. Для подписки надо оставить официальный выбор backend/provider,
моделей и нативную работу с Responses. Access token не является API key.

До login/logout надо остановить процессы, читающие соответствующий auth home,
отменить предыдущую попытку входа и сериализовать эти операции. После входа
ACP-процесс надо запустить заново. На новом входе официальный CLI сначала
очищает предыдущую авторизацию; неудачная попытка поэтому не гарантирует
сохранение старого логина. Нативный процесс кеширует авторизацию, и изменение
файла другим процессом не является автоматическим переключением аккаунта.

## Проверенные версии и идентичность пакета

| Компонент | Опубликованный `latest` при проверке | Что проверено |
| --- | --- | --- |
| `@agentclientprotocol/codex-acp` | **2.1.1**, npm `gitHead` `68d7d2d5ddfc0ed5746f9f6130892dda685e65dd` | Установка, реальный ACP `initialize`/неавторизованный `session/new`, device elicitation и CLI passthrough |
| `@openai/codex` | **0.160.0**, tag `rust-v0.160.0` | Реальный `--version`, `login status`, `login --device-auth` до ожидания аккаунта, отмена и logout пустого home |
| `@zed-industries/codex-acp` | **0.16.0**, deprecated | Метаданные npm; этот пакет не установлен и не запущен в данном аудите |
| `opencode-ai` | **1.18.34**, tag `v1.18.34` | Установка, ACP initialize/new/prompt без credentials, legacy auth advertisement |
| `@moonshot-ai/kimi-code` | **2.1.1**, commit `f67e6398fb3210ad8ace970e2dfd5bcc984ed61f` | Установка, ACP initialize/new без credentials; source-level native login |
| `@agentclientprotocol/sdk` у Codex | **1.6.0** (dependency `^1.5.0`), ACP protocol 1 | Опубликованные types и актуальная спецификация v1 |

В каталоге Moru уже устанавливается **`@agentclientprotocol/codex-acp` вместе
с `@openai/codex`**, а не `@zed-industries/codex-acp`. npm явно помечает старый
Zed-пакет: «This package has been replaced by
@agentclientprotocol/codex-acp». Проверять старый бинарный адаптер вместо
реального пакета Moru нельзя. Codex 0.160.0 новее 0.159.3 из предыдущего аудита;
незакреплённый `latest` не означает, что последующая установка даст эти же
версии.

Первичные источники:

- [npm: текущий адаптер](https://www.npmjs.com/package/@agentclientprotocol/codex-acp/v/2.1.1), [package.json](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/package.json), [README](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/README.md).
- [npm: официальный Codex](https://www.npmjs.com/package/@openai/codex/v/0.160.0), [исходники release](https://github.com/openai/codex/tree/rust-v0.160.0).
- [npm: deprecated Zed-пакет](https://www.npmjs.com/package/@zed-industries/codex-acp/v/0.16.0).
- [OpenCode release source](https://github.com/anomalyco/opencode/tree/v1.18.34), [Kimi release source](https://github.com/MoonshotAI/kimi-code/tree/f67e6398fb3210ad8ace970e2dfd5bcc984ed61f).

## Codex: команды, бинарник и stdout/stderr

Адаптер 2.1.1 **не ищет произвольный `codex` в PATH**. Без `CODEX_PATH` он
разрешает `@openai/codex/bin/codex.js` через `createRequire(import.meta.url)`
от своего установленного модуля и запускает его через текущий Node с
`app-server`. Wrapper официального пакета выбирает optional platform package
и настоящий бинарник. На Android arm64/Linux используется
`@openai/codex-linux-arm64`, MUSL target. `CODEX_PATH`, если пользователь его
задал, выбирает другой executable. Источники:
[CodexJsonRpcConnection.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/CodexJsonRpcConnection.ts),
[официальный wrapper](https://github.com/openai/codex/blob/rust-v0.160.0/codex-cli/bin/codex.js).

В Moru отдельный официальный executable доступен как
`/root/.npm-global/bin/codex`, поскольку каталог явно ставит оба npm-пакета.
Это практичный основной интерфейс для карточки входа. Версию dependency,
разрешённой адаптером, надо проверять отдельно от глобального symlink: при
другом dependency tree они могут различаться.

В текущем адаптере есть альтернативный passthrough
`codex-acp cli login --device-auth`, `codex-acp cli login status`,
`codex-acp cli logout`. Он запускает **тот же** resolved backend, учитывает
`CODEX_PATH` и наследует stdio/env:
[CodexCli.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/CodexCli.ts).
`codex-acp cli login status` реально вернул native `Not logged in`/exit 1.
Но `codex-acp cli --version` в 2.1.1 выводит **версию адаптера**, потому что
[index.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/index.ts)
перехватывает любой `--version` раньше ветки `cli`. Не использовать эту
команду как проверку версии Codex. Bare `codex-acp login` также является
отдельной командой адаптера; не подменять ею native device login без проверки.

| Native команда | Канал и критерий | Проверка/ограничение |
| --- | --- | --- |
| `codex login --device-auth` | Device prompt в **stdout**, с ANSI; success/error в stderr. Завершение с 0 означает успешное сохранение логина | Реально выдал доверенную verification page, одноразовый код и ожидал аккаунт; отменён до входа |
| `codex login status` | **stderr**: `Logged in using ChatGPT`/exit 0; `Logged in using an API key - …`/exit 0; `Not logged in`/exit 1 | Пустой home реально дал exit 1. Отличие ChatGPT/API key подтверждено source; account login не завершён |
| `codex logout` | **stderr**: `Successfully logged out` либо `Not logged in`, exit 0; error exit 1 | Пустой home реально дал `Not logged in`/exit 0 |

`login status` проверяет **сохранённый тип авторизации**. Он не подтверждает
валидность access token, возможность refresh, подписочную квоту или успешный
backend request. Exit 1 также бывает при ошибке конфигурации/хранилища, поэтому
нельзя любое ненулевое завершение называть «не вошёл». API-key status печатает
маскированный фрагмент ключа — сохранять/показывать надо только классификацию.
Источник: [cli/src/login.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/cli/src/login.rs).

Device prompt печатается обычным `println!`. Verification page — фиксированный
`https://auth.openai.com/codex/device`, без query/state. После строки
`Enter this one-time code` идёт код; в реальном probe его длина была 10 и он
состоял из uppercase букв/цифр/дефиса. Сам код не записан в evidence. CLI
сообщает «expires in 15 minutes» и polling ограничен 15 минутами. Не считать
наблюдённую длину отдельным протокольным контрактом; разбирать ограниченный
prompt, удалять ANSI с учётом границ chunks, принимать только curated
verification URL/code в выделенную UI карточку. Raw login stdout/stderr нельзя
отправлять в ACP transcript, error journal, terminal history или диагностику.
В stderr probe дополнительно был несекретный warning о helper binaries под
`/tmp`, поэтому parser не должен требовать ровно одну строку.
Источник: [device_code_auth.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/login/src/device_code_auth.rs).

Login, status, logout и ACP должны использовать один guest runtime/mode,
одинаковый пользователь/HOME и постоянный `CODEX_HOME`; совпадения cwd
недостаточно. На phone root/proot переключение не должно случайно выбирать
другое keyring/home. Для воспроизводимого файлового store можно оставить
только `cli_auth_credentials_store = "file"` в отдельном подписочном config,
без `model_provider`, provider URL/key/headers из режима Moru.

## Что показал реальный Codex ACP

С чистыми HOME/`CODEX_HOME`, без существующего auth.json, provider override и
API keys:

- `initialize` → protocol 1, `agentInfo.version=2.1.1`, auth methods
  `api-key` и `chat-gpt`; методы не имеют `type`, то есть это `agent`.
- Capabilities: `loadSession`, image/embedded context, HTTP MCP;
  session resume/list/close/delete/fork/additionalDirectories/subagents;
  `auth.logout:{}` и extension `agentCapabilities._meta.authStatus:{}`.
- `session/new` → **JSON-RPC -32000 Authentication required**.
  Реальной session ID нет; `session/prompt` на подписку поэтому не выполнялся.
  Вызов с выдуманной ID не был бы проверкой неавторизованного model request.
- При `clientCapabilities.elicitation.url:{}` появляется
  `chat-gpt-device-code`. `authenticate` с этим ID реально вызвал
  `elicitation/create` с `mode:"url"`, URL и сообщением с кодом. Probe
  ответил cancel; адаптер отменил login и вернул -32602. Никакой аккаунт не
  был авторизован, auth.json не появился.

Browser-метод `chat-gpt` запускает `open(authUrl)` на стороне agent host и
ожидает native callback. На Android guest это не гарантирует открытие
Android-браузера. `NO_BROWSER=1` убирает этот метод из advertisement, но не
добавляет device method без URL elicitation capability. Без реализованной URL
elicitation нельзя объявить этот capability только ради появления кнопки.
В native CLI explicit `--device-auth` выбирает именно device flow; fallback
обычного `codex login` не является тем же обещанием.

Адаптер публикует отдельную `_auth/status_update` с `{authStatus}`; это
extension, а не generic ACP get-status. `kind` может быть
`none`, `account`, `api_key`, `gateway`, `external`; account payload может
содержать email/plan. Статус относится к agent-owned login и отдельно от
конфигурируемого gateway. Поддержка advertisement не означает, что текущий
Moru умеет этот push или что status доказывает доступную квоту.
Источники: [CodexAuthMethod.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/CodexAuthMethod.ts),
[CodexAcpClient.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/CodexAcpClient.ts),
[CodexAcpServer.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/CodexAcpServer.ts),
[AuthStatusMeta.ts](https://github.com/agentclientprotocol/codex-acp/blob/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd/src/AuthStatusMeta.ts).

## Storage, expiry и конкурентный refresh

В режиме `file` native storage — `$CODEX_HOME/auth.json`; ChatGPT record
содержит auth mode, ID/access/refresh tokens, account ID и `last_refresh`.
Файл создаётся с mode 0600; родитель должен быть закрытым mode 0700. Это
runtime secret, не настройка assistant/provider и не artifact для экспорта.
Native также поддерживает keyring/auto/ephemeral; перенос одного auth.json не
воспроизводит произвольный keyring store. Источники:
[storage.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/login/src/auth/storage.rs),
[token_data.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/login/src/token_data.rs).

Codex 0.160.0 обновляет ChatGPT token, когда JWT expiry приблизилась на
5 минут; при отсутствии разбираемого expiry fallback смотрит на
`last_refresh` старше 8 дней. Это не фиксированная продолжительность жизни
подписки/token. На `refresh_token_expired`, `refresh_token_reused`,
`refresh_token_invalidated` refresh становится permanent failure с требованием
повторного входа. Logout пытается revoke best-effort и удаляет локальные
stores; успешный локальный logout не является доказательством remote revoke.
Источник: [auth/manager.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/login/src/auth/manager.rs).

У native manager refresh защищён `Semaphore` **внутри процесса** и перед
refresh выполняется guarded reload. Это помогает заметить уже обновлённый
файл, но не является межпроцессной блокировкой на всю сетевую операцию:
два manager могут одновременно прочитать один refresh token. `file` storage
пишет truncate/write, не транзакцию между независимыми writers. Поэтому даже
в пути A нельзя обещать проверенную безопасность одновременного refresh
несколькими Codex-процессами с одним home. В данном аудите этот риск найден по
source; с реальным аккаунтом гонка не воспроизведена. Login/logout обязаны
останавливать такие процессы; существующий многопроцессный ACP lifecycle
надо учитывать отдельно при account validation.

## Путь B: OAuth Moru и импорт credentials

Это **не рекомендуемый default** и не готовый безопасный мост. Передача
access token через `api-key` меняет auth mode, а custom gateway не повторяет
официальный ChatGPT backend contract. Копирование Moru OAuth в native
`auth.json` создаёт двух владельцев rotation: Moru и Codex. Сериализация
`ProviderOAuthService._refreshes` действует только в Dart-сервисе; она не
блокирует native CLI/process и не сохраняет native rotated credentials обратно
в Moru. Два отдельных auth home с копией одного refresh token также не
устраняют server-side reuse.

Минимальная политика для будущего пути B: один владелец refresh на аккаунт;
account/generation-aware сериализация всей refresh+persist операции; сохранение
нового refresh token до выдачи access token; повторная проверка актуальности
account после ожидания; expiry/401 обрабатываются этим владельцем; invalid,
expired, reused или revoked token требуют re-login; login/logout инвалидируют
активные leases и останавливают процессы с прежним snapshot. Недостаточно
только atomic rename файла или общего mutex перед его записью. Пока это не
обеспечено между Moru и всеми native writers, пути A/B должны оставаться
независимыми авторизациями без импорта/синхронизации tokens.

В app-server существует `account/login/start` с
`type:"chatgptAuthTokens"` и callback refresh, но текущий release прямо
помечает интерфейс **`[UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE`**.
Адаптер 2.1.1 не рекламирует такой ACP auth method. Это не публичный стабильный
выход из проблемы ownership и не основание реализовывать недокументированную
инъекцию. Источник:
[protocol/v2/account.rs](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/app-server-protocol/src/protocol/v2/account.rs).

## ACP agent, device/browser и terminal

В текущей [спецификации ACP v1](https://agentclientprotocol.com/protocol/v1/authentication)
есть default `agent` method и explicit `type:"terminal"`.
`device`/`browser` не являются универсальными AuthMethod types. Для `agent`
используется `authenticate(methodId)`; конкретный агент выбирает browser,
elicitation или иной собственный канал. Для `terminal` клиент воспроизводит
свой configured agent executable и **базовые args/env/runtime**, добавляет
объявленные args/env, показывает отдельный интерактивный процесс, принимает
его exit 0, затем reconnect/initialize. Такой ID **нельзя** отправлять в
`authenticate`. Capability `clientCapabilities.auth.terminal:true` объявляют
только при реальной поддержке этого процесса.

Legacy `_meta['terminal-auth']` — отдельная совместимость конкретных агентов;
она не даёт права исполнять произвольный command из untrusted initialize
response. Built-in native команды можно выбирать из известного каталога Moru.

## OpenCode и Kimi: реальные различия

| Проверка | OpenCode 1.18.34 | Kimi Code 2.1.1 |
| --- | --- | --- |
| Без credentials: initialize | Успешен, protocol 1 | Успешен, protocol 1 |
| Auth method | `opencode-login`, без `type` | `login`, `type:"terminal"`, `args:["--login"]` |
| Дополнительная auth metadata | Legacy terminal descriptor только при `clientCapabilities._meta['terminal-auth']=true` | `KIMI_CODE_HOME` в method env и legacy descriptor с absolute installed binary |
| Без credentials: session/new | Успешен | -32000 Authentication required |
| Без credentials: session/prompt | Успешен на default **public `opencode/big-pickle`** | Не выполнялся: session/new не выдал ID |
| ACP authenticate | `opencode-login` возвращает `{}` и **не выполняет login** | `login` только re-check readiness; terminal ID не надо использовать так в новом клиенте |
| Native login | `opencode auth login` (alias `providers login`), provider/method-specific interactive flow | `kimi login` либо configured `kimi acp` + `--login`, device-code flow |

У OpenCode prompt действительно дал 2 символа assistant text, nonzero usage и
не содержал model error, при отсутствии auth.json. Это проверка бесплатного
public default, **не подписки OpenAI/Anthropic**. Успешный `session/new` или
`authenticate:{}` нельзя превращать в статус «подписка подключена». Native
`opencode auth list` перечисляет credential types/provider и активные env vars;
оно не является подтверждением server-side OAuth. `auth logout [provider]`
удаляет выбранную запись из `$XDG_DATA_HOME/opencode/auth.json`
(по умолчанию `~/.local/share/opencode/auth.json`). Login поддерживает
`--provider`/`--method`; конкретный browser/device/manual-code flow задаёт
provider plugin. Источники:
[acp/service.ts](https://github.com/anomalyco/opencode/blob/v1.18.34/packages/opencode/src/acp/service.ts),
[providers.ts](https://github.com/anomalyco/opencode/blob/v1.18.34/packages/opencode/src/cli/cmd/providers.ts),
[auth/index.ts](https://github.com/anomalyco/opencode/blob/v1.18.34/packages/opencode/src/auth/index.ts).

Для Kimi основной terminal descriptor требует запуск **`kimi acp --login`**,
если исходная invocation была `kimi acp`; native `kimi login` ведёт в тот же
shared flow. HOME/`KIMI_CODE_HOME` должны совпадать с будущим ACP и не иметь
временной provider-конфигурации Moru. Авторизацию нельзя считать отдельным
config-only объектом: тот же home содержит sessions/store/cache/logs. В этом
аудите Kimi login не запускался и не проверялись реальные token storage,
refresh и subscription quota; эти детали не следует приписывать CLI по
аналогии с Codex. Источники:
[auth-methods.ts](https://github.com/MoonshotAI/kimi-code/blob/f67e6398fb3210ad8ace970e2dfd5bcc984ed61f/packages/acp-server/src/auth-methods.ts),
[acp.ts](https://github.com/MoonshotAI/kimi-code/blob/f67e6398fb3210ad8ace970e2dfd5bcc984ed61f/apps/kimi-code/src/cli/sub/acp.ts),
[login.ts](https://github.com/MoonshotAI/kimi-code/blob/f67e6398fb3210ad8ace970e2dfd5bcc984ed61f/apps/kimi-code/src/cli/sub/login.ts),
[server.ts](https://github.com/MoonshotAI/kimi-code/blob/f67e6398fb3210ad8ace970e2dfd5bcc984ed61f/packages/acp-server/src/server.ts).

## Evidence и границы воспроизведения

Все установки/probes выполнялись вне repository в свежем private temporary
prefix `/tmp/moru-acp-subscription-blz7zm_3`, с отдельным HOME и agent home на
каждый scenario, Node **24.19.0**, Linux x64, физический UID **1000**.
Сохранены только sanitized summaries, без кодов, credentials, auth URL с state,
account email или raw login output:

- `codex-acp-probe.json` — два initialize, auth gate и отменённая URL elicitation.
- `codex-native-login-probe.json` — native version/status/device-account-required/cancel/logout.
- `codex-cli-passthrough-probe.json` — native status через adapter `cli`.
- `other-agents-probe.json` — OpenCode/Kimi ACP initialize/new/prompt summaries.
- `opencode-response-probe.json` — выбранный public model, отсутствие auth.json,
  assistant response length/error/usage booleans из isolated read-only SQLite.
- `probe_codex.py`, `probe_native_login.py`, `probe_other.py` — scripts;
  stdout только allowlisted summaries, device values только в памяти до cancel.

`sudo` в этом executor отсутствует. Root/chroot, PRoot stat translation,
private mount namespace и Android arm64 login/ACP/tool execution здесь не
проверены. Свежий `CODEX_HOME` **не заменяет** root daemon isolation: fixed
`/tmp/codex-daemon-<euid>` остаётся отдельным native guard. Login probe и
неавторизованный ACP new не доходят до shell sandbox, поэтому их успех не
опровергает ownership blocker. Соблюдать действующую изоляцию Moru из
[AGENTS.md](../../AGENTS.md) и
[agent-tools-ownership.md](agent-tools-ownership.md): fresh private bind только
в run namespace, без глобального getuid shim, chown существующих daemon dirs,
общих mount changes или ослабления workspace permissions.

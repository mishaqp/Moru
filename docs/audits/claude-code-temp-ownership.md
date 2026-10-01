# Claude ACP: владелец временного каталога в PRoot

Дата проверки: **2026-10-01, UTC**. Исходный каталог Moru:
`f1293c5184af31f740dd40e5550c4ec2e529a745`,
`lib/core/services/acp/acp_agent_catalog.dart`. Этот документ фиксирует аудит
опубликованных npm-пакетов, выбранное исправление и границы воспроизведения.

## Вывод

Причина ошибки `Temp directory /tmp/claude-0 is owned by uid 10575, expected 0`
согласуется с различием между виртуальным `getuid() = 0` в PRoot `--root-id`
и владельцем inode, возвращаемым `stat`/`fstat`. Точное такое различие
воспроизведено настоящим adapter и его native CLI: ACP `initialize` проходит,
а `session/new` возвращает `-32603 Internal error` с ошибкой владельца в
`error.data.details`.

**Один свежий `CLAUDE_CODE_TMPDIR` не устраняет несовпадение UID.** Это база
пути; проверяется дочерний каталог `${CLAUDE_CODE_TMPDIR}/claude-${getuid()}`.
При отсутствующем дочернем каталоге upstream сначала создаёт его, затем сразу
проверяет владельца. Изначальное отсутствие leaf не является обходом проверки.
Существующий leaf допустим при совпадающем владельце. Сама база и её родители
этой функцией на UID/режим не проверяются.

В проверенных native версиях есть встроенная upstream-ветка:
`getuid() === 0 && CLAUDE_CODE_CONTAINER_ID` допускает несовпадение владельца,
сохраняет проверку directory/`O_NOFOLLOW` и пишет `tempdir_owner_mismatch`.
Она также возвращается **до** исправления режима на `0700`. Итоговый способ
для Moru — собственный неперсональный container ID в env одного запуска
и новый приватный `CLAUDE_CODE_TMPDIR` с режимом `0700` и `umask 077`.
Это использование существующей ветки upstream; наличие публичного стабильного
контракта для этой переменной данным аудитом не установлено.

## Итоговые пути и владение запуском

Обычный запуск Claude в Moru использует root `/tmp/mc`. Для каждого запуска
генерируются 16 байт UUID v4, кодируемые в **22 ASCII-символа base64url без `=`**:

```text
token                       = <22 символа base64url UUID v4>
CLAUDE_CODE_TMPDIR           = /tmp/mc/<token>
CLAUDE_CODE_CONTAINER_ID     = moru-<token>
MORU_ACP_TEMP_DIR            = /tmp/mc/<token>
проверяемый upstream leaf    = /tmp/mc/<token>/claude-0
```

База занимает **30 байт**, leaf при `getuid()=0` — **39 байт**. Это сохраняет
путь внутри лимита native `childProcessTmpDir` и не переводит Bash helper
на общий `/tmp/claude-0`. Старый вариант с длинной базой под
`/root/.config/moru-agents/run-tmp/claude` для обычного запуска не используется.
Явный override `configDirectory` в каталоге имеет отдельный путь; при таком
override также необходимо учитывать длину производного leaf.

Подготовление/cleanup в `acp_launch_directories.dart` хранит владение запуском
отдельно от persistent Claude home/session:

- Managed root должен быть обычным приватным directory `0700` с собственным
  marker `.moru-acp-launches-v1`. Root открывается с `O_DIRECTORY | O_NOFOLLOW`;
  дальнейшие записи, rename и удаления привязаны к `/proc/self/fd/<rootFd>`.
  Проверки inode/device и realpath обнаруживают подмену исходного root.
  Сам root тоже публикуется через staging с готовым marker: убийство helper
  между mkdir и записью marker не оставляет заблокированный root. Claim и
  рекурсивное удаление открывают отдельные run/child descriptors с `O_NOFOLLOW`.
- Run сначала создаётся как `.preparing-<helperPID>-<starttime>-<token>` с `0700`,
  получает `.owner` с `0600`, затем переименовывается через этот descriptor.
  Shell перед `exec` делает `umask 077` и обновляет owner в фазу `running`.
- Owner record содержит PID, `/proc` starttime, boot ID, UID и фазу. Sweep
  защищает активные in-memory leases, ещё живые owner PID и native children
  с `MORU_ACP_TEMP_DIR`/`CLAUDE_CODE_TMPDIR` в process env. PID без starttime
  не считается достаточной идентичностью процесса.
- Закрытие Moru run ждёт transport `onClose`, затем запускает удаление.
  Cleanup дополнительно проверяет процессы; timeout закрытия сам по себе
  не даёт права удалить каталог живого CLI. Неизвестный owner, нечитаемый
  `/proc` или продолжающий жить child оставляют run для последующего sweep.

Эта схема следует текущему прочитанному исходнику Moru; ниже отдельно указаны
выполненные native проверки. Данный аудит не объявляет Android lifecycle,
race-проверки helper или model API проверенными этими `session/new` тестами.

## Что реально установилось

В исходном каталоге устанавливаются без `@version`, `^version` или другого
ограничения:

```sh
npm install -g --prefix /root/.npm-global --no-audit --no-fund \
  @anthropic-ai/claude-code @agentclientprotocol/claude-agent-acp
```

Таким образом, каталог Moru непинованный. Значения ниже — результат разрешения
npm **во время этого аудита**, а не заявление о версии на телефоне.

| Пакет | Фактическая версия | Ограничение / Node |
| --- | --- | --- |
| `@anthropic-ai/claude-code` | `2.1.287` | Moru не задаёт версию; npm `engines.node >=22.0.0` |
| `@agentclientprotocol/claude-agent-acp` | `0.85.0` | Moru не задаёт версию; npm `engines.node >=22` |
| Вложенный `@anthropic-ai/claude-agent-sdk` | `0.3.286` | Adapter задаёт точно `0.3.286`; Node `>=18.0.0` |
| Вложенный `@anthropic-ai/claude-agent-sdk-linux-x64` | `0.3.286` | Точная optional dependency SDK; встроенный Claude **`2.1.286`** |
| Вложенный `@agentclientprotocol/sdk` | `1.5.1` | Точная dependency adapter |
| `diff`, `zod` | `9.0.0`, `4.6.5` | Точные dependencies adapter |

На этой машине: Linux x64, обычный UID `1000`, Node `v24.19.0`, npm `11.9.0`.
ARM64-пакеты здесь не запускались. Исходный `AcpAgentSpec` для Claude имел
default minimum Node `18.0.0`; это отличается от текущих требований adapter,
но не объясняет воспроизведённую ошибку: здесь Node 24.

Установка и сбор метаданных выполнены **вне репозитория**:

```sh
npm view @anthropic-ai/claude-code version engines dist.integrity dist.tarball --json
npm view @agentclientprotocol/claude-agent-acp version engines dependencies dist.integrity dist.tarball --json
npm install -g --prefix /tmp/moru-claude-audit \
  --cache /tmp/moru-claude-audit-npm-cache --no-audit --no-fund --ignore-scripts \
  @anthropic-ai/claude-code @agentclientprotocol/claude-agent-acp
npm ls -g --prefix /tmp/moru-claude-audit --depth=2 --json
```

`--ignore-scripts` использован для чтения опубликованных файлов без lifecycle
scripts. Optional native binary SDK установился и реально запускался. Из-за
пропуска postinstall standalone `bin/claude` не использовался; проверялся
явный файл платформенного пакета. Оба native `--version` с пустым auth env и
отдельным config/home подтвердили `2.1.287` и `2.1.286` соответственно.

Registry integrity для standalone:
`sha512-V5WRpA+p41siSlf/Ujxjm//RtYvySxH/p9/rh6zRxNoHeBzqTgSDw3nP8PgtACM/KcVx/g5TFUNdVkq51dfg0g==`.
Для adapter:
`sha512-kTN7UiyosRtnwh7RisqNx1+/JkaMRZnO9HYLdYGoxJx3mUY73VB1iw7v7t61ewyZgYZd2GPf0Fuk1TrtfIaKeg==`.

## Какой CLI запускает adapter

`dist/acp-agent.js:626`, `claudeCliPath()`, проверяет
`CLAUDE_CODE_EXECUTABLE`, затем разрешает optional native package **относительно
вложенного SDK**, включая определение glibc/musl. `createSession()` задаёт
`pathToClaudeCodeExecutable` этим путём (`:6669`), вызывает `query()` (`:6788`)
и ожидает `q.initializationResult()` (`:6798`).

Значит, обновление только standalone `@anthropic-ai/claude-code` не доказывает,
что изменился падающий CLI. В этой установке adapter запускал встроенный
Claude `2.1.286`, несмотря на standalone `2.1.287`.

В SDK/npm нового формата код CLI находится также в Bun-embedded JS chunks
внутри ELF. Извлечён опубликованный chunk, содержащий подсказку
`Set CLAUDE_CODE_TMPDIR to a directory you control`:

| Файл | Offset chunk в ELF | SHA-256 извлечённого chunk |
| --- | --- | --- |
| Standalone `claude-code-linux-x64/claude` | `198808822` | `f108ac863aa043dccd659566e71e3fa2b2f6459cf36e631f02b6bb262e8c2ed7` |
| SDK `claude-agent-sdk-linux-x64/claude` | `196882442` | `c30c17ab05f82793cd47a5dc938bb443526ca2dea9d2bc74d5c4d0ac87150bfe` |

SHA-256 самих ELF: standalone
`3920489a5109cff5786a1a392c25277408ff22bc796d5edb9c16a60e5a1718f0`;
SDK `fe503f65c6289d59c23e5b21ae44f03583f997dd33a2cbfc75ab4f96fb8fc73f`.

Воспроизводимая схема извлечения, без запуска бинаря:

```python
from pathlib import Path
b = Path(native_binary_path).read_bytes()
hint = b'Set CLAUDE_CODE_TMPDIR to a directory you control, or ask an administrator to remove it.'
i = b.find(hint, 180_000_000)  # в данных проверенных ELF: область JS, не таблица строк
assert i >= 0
start = b.rfind(b'// @bun @bytecode', 0, i)
end = b.find(b'\x00// @bun @bytecode', i)
assert start >= 0 and end > start
Path(output_path).write_bytes(b[start:end])
```

## Точная область проверки

В SDK chunk функции называются `cb` (база), `y` (leaf), `T` (создание),
`mSe` (проверка). В standalone соответствуют `Lb`, `S`, `I`, `Ywe`.
Короткие фрагменты опубликованного SDK кода:

```js
function cb(){let e=a.CLAUDE_CODE_TMPDIR;if(e)return e;return l()}
function y(){return`claude-${process.getuid?.()??0}`}
// Из T(e):
let t=p(cb(),y());
if(t!==e.ensured){
  if(typeof process.getuid==="function")d(t,{recursive:!0,mode:448}),mSe(t);
  else try{d(t,{recursive:!0,mode:448})}catch{}
  e.markEnsured(t)
}
// Из mSe(e):
i=A(r,f.O_RDONLY|f.O_DIRECTORY|f.O_NOFOLLOW);
let n=R(i);
if(n.uid!==t){
  if(t===0&&a.CLAUDE_CODE_CONTAINER_ID){
    te("warn","tempdir_owner_mismatch",{observed_uid:n.uid});return
  }
  throw Error(`Temp directory ${e} is owned by uid ${n.uid}, expected ${t}. Refusing to use it \u2014 another user may have pre-created it. ${o}`)
}
if((n.mode&511)!==448)O(i,448)
```

Aliases: `l=os.tmpdir`, `p=path.join`, `d=mkdirSync`, `A=openSync`,
`R=fstatSync`, `O=fchmodSync`; `448 = 0700`, `511 = 0777`.

Последовательность и ограничения:

1. Непустой env-путь выбирается напрямую; иначе используется `os.tmpdir()`.
   Нет особого исключения для `/tmp` или проверки доверенного root-parent.
2. `mkdirSync(..., recursive:true, mode:0700)` создаёт leaf либо оставляет
   существующий. Сразу после него вызывается проверка.
3. Удаляются завершающие разделители. Leaf открывается с
   `O_RDONLY | O_DIRECTORY | O_NOFOLLOW`; `fstat` проверяет открытый объект.
   Symlink на самом leaf отвергается; функция не запрещает symlink в родителе.
4. `ELOOP`/`ENOTDIR` дают отказ directory/symlink. При `EACCES` есть отдельный
   `lstat` для сообщения о чужом UID либо ошибке читаемости/поиска пути.
   Container exception не перехватывает эти ошибки открытия.
5. Обычная ветка требует `fstat.uid === process.getuid()`, затем исправляет
   permission bits на `0700` через descriptor. Root/container exception
   пропускает **UID и эту коррекцию режима**, но выполняется после безопасного
   открытия directory. Descriptor закрывается в `finally`.
6. Успешный root temp path memoized в пределах процесса/host context.
   `plugin-tool-staging` дополнительно создаётся и проверяется этой же функцией.
   `childProcessTmpDir` после получения проверенного leaf возвращает его при
   `Buffer.byteLength(leaf) <= 44`. При большей длине пытается использовать
   `${os.tmpdir()}/claude-${uid}` с той же проверкой; fallback не означает
   успешную проверку первоначального leaf. Base-only helper также сохраняет
   env-базу только при длине до 44 байт включительно.

Точная граница из SDK `gSe()` и standalone `Xwe()`:

```js
// gSe(): yQn = 44
let e=D.of(j().host),t=T(e);if(Buffer.byteLength(t)<=yQn)return t;
// Xwe(): Mrr = 44
let e=R.of(U().host),t=I(e);if(Buffer.byteLength(t)<=Mrr)return t;
```

Тела обеих published функций дополнительно извлечены без изменений и вызваны
в отдельном `vm` с наблюдаемым `os.tmpdir` fallback: **39 и 44 байта** сохраняют
configured leaf, **45 байт** входят в fallback. Все шесть assertions прошли
(`check-native-temp-length.cjs`, `temp-length-results.json` в audit prefix).

Отдельный опубликованный файл SDK `extractFromBunfs.js` содержит `safeTempBase()`:
тот же env base + `claude-${uid}`, `mkdir`, затем `lstat.isDirectory`, совпадение
UID и `chmod(0700)`. **Container exception в этом helper отсутствует.** Он нужен
для извлечения файла из `$bunfs`/`~BUN`; при обычном реальном npm-пути функция
сразу возвращает исходный путь. Проверенный Node/npm adapter выбирает реальный
platform binary и не идёт через такое извлечение.

## Побочные эффекты `CLAUDE_CODE_CONTAINER_ID`

Полный поиск имени в опубликованных JS chunks обоих ELF и SDK `.mjs` нашёл
следующие назначения; в SDK ELF имя встретилось в семи chunks:

- Env schema — строка (`H.str()`), без требования чужого UUID/container.
- Ветка временного каталога root/container, описанная выше.
- HTTP-заголовок `x-claude-remote-container-id` со значением env.
- Telemetry: `claudeCodeContainerId`, collector `facts.containerId`.
- Разрешение `tool_progress` для Bash/PowerShell также при отсутствии
  `CLAUDE_CODE_REMOTE`.
- Список защищённого launch env: settings не должны подменить container identity.
- Справочные названия источников ошибочного HTTP header.

Активации remote login/auth либо привязки к чужой remote session одной этой
переменной в найденных uses нет; `CLAUDE_CODE_REMOTE_SESSION_ID`, auth tokens
и remote-mode переменные независимы. Свой случайный ASCII `moru-<UUID>`
прошёл реальные `initialize` и `session/new`. Он не должен содержать имя
пользователя, путь workspace, ключ или существующий чужой container/session ID.

## Почему «Check / initialize работает» не доказывает работу чата

`initialize()` adapter (`dist/acp-agent.js:1167`) возвращает протокол и
capabilities. Auth probe запускается в фоне и не блокирует ответ. Только
`session/new` создаёт `query`, запускает native CLI и ожидает его SDK initialize.
После отказа native CLI SDK `getProcessExitError()` сохраняет stderr в ошибке.
ACP SDK `dist/jsonrpc.js:errorToResult()` преобразует обычный `Error` в
`-32603 Internal error`, сохраняя текст в `data.details`.

Для уже созданной сессии дополнительные temp consumers могут запускаться на
`session/prompt` или при tools. В данном native воспроизведении отказ происходит
уже на `session/new`, поэтому prompt до API не доходит. Формулировка «после
первого запуска» сама по себе не доказывает успешный первый model turn. Если на
телефоне действительно был успешный prompt при том же UID и без container
exception, необходимы версии/полный stderr и хронология процессов; только
этим аудитом такой более поздний отказ не объясняется.

## Воспроизведения и результаты

Все фикстуры, npm cache, scripts и сырые результаты находятся под
`/tmp/moru-claude-audit*`, вне репозитория. Они временные. Credentials пользователя
не использовались: запускали с отдельными HOME/config/cwd, явным минимальным env,
**фиктивным** `ANTHROPIC_API_KEY=moru-audit-dummy-no-credentials`,
`ANTHROPIC_BASE_URL=http://127.0.0.1:9`, отключённой telemetry и auto-update.
Сеть к provider не требовалась; успешный `session/new` не подтверждает model API.

### Извлечённые функции, реальный filesystem

`reproduce-temp-ownership.cjs` извлекает тела обеих published функций без
изменений и выполняет их в отдельном `vm`. Только `process.getuid()` в этом
`vm` задаётся как `0`; настоящие `fs` операции возвращают UID `1000`.
Это моделирование PRoot, а не изменение process UID или реальных защит CLI.

| Условие | CLI 2.1.287 и SDK CLI 2.1.286 |
| --- | --- |
| Fresh leaf отсутствует, virtual UID 0, owner нового inode 1000 | Отказ `owned by uid 1000, expected 0`, даже после создания `0700` |
| Совпадающий owner, leaf `0777` | Успех, leaf исправлен на `0700` |
| Parent `0777` | Parent не меняется |
| Parent symlink, нормальный leaf | Принимается |
| Leaf symlink, в том числе root/container | Отказ `not a directory` |
| Root/container, чужой owner, leaf `0777` | Успех, режим остаётся `0777` |
| Nonroot/container, чужой owner | Отказ |
| После успешной проверки изменить mode и повторить через memo | Повторная базовая проверка не выполняется |

14 проверок для двух версий завершились без assertion failures. Команда:

```sh
node /tmp/moru-claude-audit/reproduce-temp-ownership.cjs
```

Результат: `/tmp/moru-claude-audit/reproduction.json`.

### Настоящий adapter и native CLI, чужой UID

`sudo`/`fakeroot` и настоящий root-chroot здесь отсутствуют. Доступны user и mount
namespaces. В отдельном namespace `unshare --user --map-root-user --mount`
собственный host UID 1000 отображается в UID 0. Host-root directory `/run/lock`
становится чужим unmapped UID 65534. Его bind только на тестовый leaf, затем
`remount,bind,ro`, создаёт расхождение без `chown`, patch, preload или отключения
проверок. Mounts исчезают вместе с namespace; исходный `/run/lock` не меняется.

```sh
mkdir -p /tmp/moru-claude-audit/native-repro/base/claude-0
unshare --user --map-root-user --mount sh -c '
  mount --make-rprivate / &&
  mount --bind /run/lock /tmp/moru-claude-audit/native-repro/base/claude-0 &&
  mount -o remount,bind,ro /tmp/moru-claude-audit/native-repro/base/claude-0 &&
  python3 /tmp/moru-claude-audit/probe-acp.py
'
```

Probe отправляет по STDIO два JSON-RPC запроса, ожидая ответ первого:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"moru-local-audit","version":"1"}}}
{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/tmp/moru-claude-audit/native-repro/project","mcpServers":[]}}
```

Результат без container ID:

```text
getuid = 0; leaf uid = 65534; leaf permission bits = 0777
initialize: SUCCESS
session/new: -32603, "Internal error"
data.details:
  Claude Code process exited with code 1. stderr: Temp directory
  /tmp/moru-claude-audit/native-repro/base/claude-0 is owned by uid 65534,
  expected 0. Refusing to use it — another user may have pre-created it.
```

Затем в env **одного тестового процесса** добавлен новый
`CLAUDE_CODE_CONTAINER_ID=moru-<UUID>` (`probe-acp.py --container`). Тот же
readonly foreign leaf: `initialize` и `session/new` успешны, получены
`sessionId`, modes и model/config options. Сырое evidence:
`native-repro/result.json`, `native-repro/container-result.json`.

Повторный запуск и два одновременных запуска в отдельных bases также дали
успешные `initialize` и `session/new`:

```sh
unshare --user --map-root-user --mount sh /tmp/moru-claude-audit/run-native-matrix.sh
```

Evidence: `native-repeat/container-result.json`,
`native-concurrent-a/container-result.json`,
`native-concurrent-b/container-result.json`.
Все три процесса имели свой `moru-<UUID>`, отдельные config/home/project и base;
внутри каждого `getuid=0`, foreign leaf UID 65534.

Дополнительный контроль: fresh base/leaf, созданный самим namespace root,
возвращает `getuid=0`, `stat.uid=0`, mode `0700`; без container ID оба запроса
успешны (`native-matching-owner/result.json`). Это проверяет нормальное отношение
UID/owner, характерное для настоящего root. Это **не** тест Android root-chroot.

### Повтор с итоговой короткой базой

После выбора `/tmp/mc/<22>` native matrix повторена с итоговой формой env.
В отдельном mount namespace `/tmp` заменён временным tmpfs; исходный npm audit
prefix привязан через заранее открытый directory descriptor.
Таким образом, `/tmp/mc` и его fixtures существовали только внутри namespace,
не пересекались с параллельными тестами и исчезли при его завершении.
Foreign leaf снова создан readonly bind `/run/lock`: `getuid=0`, inode UID 65534.

```sh
unshare --user --map-root-user --mount \
  python3 /tmp/moru-claude-audit/run-native-short-matrix.py
```

| Запуск | Base / leaf, байт | `initialize` | `session/new` |
| --- | --- | --- | --- |
| Первый свежий | 30 / 39 | Успех | Успех |
| Повторный свежий | 30 / 39 | Успех | Успех |
| Одновременный A | 30 / 39 | Успех | Успех |
| Одновременный B | 30 / 39 | Успех | Успех |

Все четыре запуска имели разные bases и `CLAUDE_CODE_CONTAINER_ID=moru-<same22>`.
Assertions подтвердили UID mismatch, оба успешных JSON-RPC ответа и длины путей.
Evidence под `/tmp/moru-claude-audit`:
`native-short-first/container-result.json`,
`native-short-repeat/container-result.json`,
`native-short-concurrent-a/container-result.json`,
`native-short-concurrent-b/container-result.json`.

Foreign readonly leaf имел permission bits `0777` как контролируемая фикстура;
это не предлагаемый режим production. Базы были `0700`, исходный `/run/lock`
не изменялся, real protections не патчились. Проверено создание SDK sessions;
запросов к model API и проверки ответа provider здесь не было.

## Проверки на телефоне перед признанием исправления

1. Снять версии в действующем Linux runtime: Node, adapter, standalone Claude,
   вложенный SDK, его `claudeCodeVersion` и реальный platform binary.
   `npm ls -g --prefix /root/.npm-global --depth=2` полезнее одного
   `claude --version`. Не выводить provider env целиком.
2. Для конкретного ACP запуска проверить `/tmp/mc/<22>` и его `/claude-0`,
   длины **30/39 байт**, permission bits `0700`,
   guest `node -p 'process.getuid()'` и UID из `fstat`. Терминал не обязан
   наследовать env ACP; измерения должны относиться к тому же runtime/запуску.
3. На PRoot выполнить Check, создание сессии, первый и второй prompt; затем
   Stop и новое создание сессии. Проверить новый base/container ID, сохранение
   persistent Claude home/session и отсутствие старого `/tmp/claude-0` в
   используемых путях. Старый каталог не удалять как часть диагностики.
4. Выполнить два чата одновременно: разные private bases, обе сессии работают,
   остановка одной не удаляет base второй или её native child.
5. Проверить удаление process-owned base после штатного native stop/exit,
   ошибки запуска и detach, а также безопасный sweep после перезапуска приложения.
   Живой native child при ещё закрывающемся ACP channel должен сохранять свой
   каталог; нельзя считать один timeout подтверждением смерти.
6. Отдельно повторить в настоящем root-chroot, если он доступен на телефоне:
   matching UID 0, leaf `0700`, обычная ветка ownership; переключение режимов
   не должно менять UID/path правила других агентов.
7. При использовании Anthropic-compatible provider проверить полный prompt:
   он получает дополнительный `x-claude-remote-container-id`; init-only тесты
   не доказывают принятие этого заголовка provider и не проверяют его ответы.

Свежая приватная base нужна для изоляции и отсутствия предсозданного leaf;
без root/container ветки она не компенсирует PRoot UID mismatch. Глобальные
`getuid`/`stat` shims, `chmod 777`, удаление общего `/tmp/claude-0`, downgrade
защит и изменение PRoot identity не использовались.

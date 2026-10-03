# Аудит владения файлами у агентов и Linux-инструментов

Дата: 2026-10-01. Проверены пакеты, которые действительно устанавливает
`lib/core/services/acp/acp_agent_catalog.dart`, и связанные инструменты из
`lib/core/services/sandbox/environment_dependencies.dart`. Версии в каталоге
Moru не закреплены; ниже зафиксирован результат разрешения npm на дату аудита.

Все четыре агента — Codex, OpenCode, Kimi и DeepSeek — ответили на ACP
`initialize` **и** `session/new` при `getuid()/geteuid() = 0` и существующих HOME,
конфигурации и workspace владельца Android UID 10575. Это не доказывает работу
всех shell-команд: у Codex отдельно воспроизведён отказ `workspaceWrite` в root
после PRoot из-за владельца `/tmp/codex-daemon-0`.

## Проверенная среда и пределы результата

Артефакты и распакованные пакеты сохранены вне репозитория, в
`/tmp/moru-tools-audit/{packages,source,installed,probes,metadata}`.
Исходники исследовались до выбора обхода; гипотезы проверялись отдельными
локальными командами. Изменения владельцев выполнялись только на искусственных
fixtures внутри одноразовых контейнеров.

Основной контейнер: Debian 12, x86_64, Node 24.21.0, npm 11.19.0, Git 2.39.5,
OpenSSH 9.2p1 Debian-2+deb12u10, tmux 3.3a, Debian PRoot 5.1.0.
Контейнер запущен из `public.ecr.aws/docker/library/node:24-bookworm-slim`;
Docker Hub вернул anonymous pull rate limit. Унаследованные HTTP-прокси и
проверка TLS сохранены; сертификат среды подключался только для доверия TLS.
Значения учётных данных не выводились. Дополнительно прочитаны исходники
Git 2.52.0, OpenSSH 10.0p2, npm 11.9.0 и pip 26.2.1 из cloud executor.

Два режима:

| Режим | Процесс | Существующие HOME/workspace/config | Новые файлы |
| --- | --- | --- | --- |
| PRoot | `docker exec -u 10575:10575 … proot -0 …` | Физический UID 10575 | Физический UID 10575 |
| root | Настоящий root контейнера, без подмены UID | Физический UID 10575 | UID 0 |

Для проверки private mount namespace использованы дополнительные одноразовые
privileged-контейнеры. Это модель нужных Linux-условий, не испытание APK на
Android: ARM64, SELinux, Android kernel и поставляемый Moru PRoot требуют
проверки на телефоне. Нативные ARM64-пакеты распакованы и исследованы, динамический
smoke выполнен на x86_64. Запросов к LLM не было: конфигурации содержали фиктивный
ключ и адрес `http://127.0.0.1:1`; `session/prompt` не вызывался.

Установки для анализа зависимостей использовали `--ignore-scripts`. Это не
проверка сборки `node-pty`/Koffi или всех терминальных функций. В обычном install
Moru postinstall остаётся включённым.

## Разрешённые версии и источники

| Компонент каталога | npm package / фактическая версия | Исследованный материал |
| --- | --- | --- |
| Codex CLI | `@openai/codex@0.159.3` | npm launcher; официальный ARM64 native package; x64 native из изолированной установки; Rust release source |
| Codex ACP | `@agentclientprotocol/codex-acp@2.1.1` | Опубликованный `dist/index.js`; зависимость Codex разрешилась в 0.159.3 |
| OpenCode | `opencode-ai@1.18.34` | npm launcher/postinstall; upstream source |
| OpenCode ARM64 glibc | `opencode-linux-arm64@1.18.34` | Официальный ELF ARM64, interpreter `/lib/ld-linux-aarch64.so.1` |
| OpenCode ARM64 musl | `opencode-linux-arm64-musl@1.18.34` | Официальный ELF ARM64, interpreter `/lib/ld-musl-aarch64.so.1` |
| OpenCode smoke | `opencode-linux-x64@1.18.34` | Официальный x64 native executable |
| Kimi | `@moonshot-ai/kimi-code@2.1.1` | Опубликованный `dist/main.mjs`, workers, postinstall и native assets |
| DeepSeek | `@deepseek-ai/dsh@0.2.0-rc.2` | Опубликованные модули и реально разрешённые транзитивные зависимости |

ARM64-вариант Codex — npm alias `@openai/codex-linux-arm64` на
`@openai/codex@0.159.3-linux-arm64`, а не другой независимо разрешаемый пакет.
Бинарник находится в `vendor/aarch64-unknown-linux-musl/bin/codex`.

Источники с фиксированным revision:

- [Codex rust-v0.159.3](https://github.com/openai/codex/tree/01fc69f4026735edfdf6789820549727a4867b11), commit `01fc69f4026735edfdf6789820549727a4867b11`.
- [Codex ACP](https://github.com/agentclientprotocol/codex-acp/tree/68d7d2d5ddfc0ed5746f9f6130892dda685e65dd), npm `gitHead` `68d7d2d5ddfc0ed5746f9f6130892dda685e65dd`.
- [OpenCode v1.18.34](https://github.com/anomalyco/opencode/tree/aec0b9a6d8898f68f923aaf08b7306d931fd9d76), commit `aec0b9a6d8898f68f923aaf08b7306d931fd9d76`.
- [Kimi опубликованный пакет 2.1.1](https://www.npmjs.com/package/@moonshot-ai/kimi-code/v/2.1.1) и [upstream](https://github.com/MoonshotAI/kimi-code).
- [DeepSeek опубликованный пакет 0.2.0-rc.2](https://www.npmjs.com/package/@deepseek-ai/dsh/v/0.2.0-rc.2) и [upstream](https://github.com/deepseek-ai/deepseek-harness).
- [Git v2.52.0](https://github.com/git/git/tree/v2.52.0), [OpenSSH V_10_0_P2](https://github.com/openssh/openssh-portable/tree/V_10_0_P2), [tmux 3.3a](https://github.com/tmux/tmux/tree/3.3a).

У Kimi и DSH npm `gitHead` отсутствовал; для них первичное свидетельство —
именно versioned tarball, а не плавающая ветка GitHub. Дополнительные зависимости:
`@deepseek-ai/dsh-spill-local@0.2.0-rc.2`,
`node-addon-native-custom-loader@0.1.7`, `@anthropic-ai/sdk@0.124.0`,
`ws@8.22.0`; `node-pty@1.1.0` у Kimi и `1.2.0-beta.15` у DSH.
Полные SHA-256 tarballs записаны в `metadata/tarball-sha256.json`.

## Почему один Node stat не доказывает отказ нативной программы

На одном и том же файле физического UID 10575 получен следующий результат
`probes/stat-syscalls.c` под честным PRoot:

```text
getuid = 0; geteuid = 0
stat.uid = 0; fstat.uid = 0; fstatat.uid = 0
statx.uid = 10575
Node fs.stat.uid = 10575
```

PRoot 5.1 переводит владельца в старых stat syscalls, но не в данном `statx`.
Поэтому JavaScript-проверка `fs.stat(...).uid !== process.getuid()` действительно
срабатывает, а Git/OpenSSH/tmux и проверенный MUSL Codex могут видеть UID 0.
Другая libc, версия PRoot или ABI могут изменить эту границу. В настоящем root
все эти API возвращают физический UID 10575 для старых файлов.

## Матрица наблюдений

«Подтверждено» означает выполненный локальный probe в описанной среде.
«Исходники» означает найденное условие и прослеженный результат, без
утверждения об отказе на телефоне.

| Компонент / операция | PRoot | Настоящий root с Android-owned данными | Уровень и последствия |
| --- | --- | --- | --- |
| Codex ACP `initialize` + `session/new` | Оба успешны | Оба успешны | Подтверждено; UID не блокирует стандартный STDIO startup |
| OpenCode ACP `initialize` + `session/new` | Оба успешны | Оба успешны | Подтверждено; блокирующий owner check в проверенном коде не найден |
| Kimi ACP `initialize` + `session/new` | Оба успешны | Оба успешны | Подтверждено; конфигурация и persistent home читаются |
| DeepSeek ACP `initialize` + `session/new` | Оба успешны | Оба успешны | Подтверждено; ACP сообщает свою внутреннюю `agentInfo.version=0.0.1`, package version при этом 0.2.0-rc.2 |
| Codex `command/exec`, `workspaceWrite`, daemon-dir физического UID 10575 | Owner guard пройден; nested sandbox exit 182 | Exit 1: `error building bubblewrap command: app-server socket directory must be a user-owned directory with mode 0700` | Подтверждён root blocker shell sandbox после PRoot; отдельно от успешного ACP startup |
| Codex `workspaceWrite`, private bind fresh `/tmp/md/<22>` | Не требуется для проверенного native owner guard | Exit 0 / `audit-ok` при существующих `.git/.agents/.codex/.aws`; без `.aws` отдельный bwrap mkdir EACCES | Подтверждено в privileged namespace с HOME UID 10575/0700 и workspace UID 10575/0755; Android execution ещё требует проверки |
| Новый `AcpLaunchDirectories` helper через `/proc/self/fd` | prepare/claim/remove/sweep успешны; физический UID 10575 | Успешны также через kernel `chroot /`; UID 0 | Подтверждено; claimed live и surviving SDK child сохраняются, после смерти удаляются |
| Codex Unix listener в Android-owned parent | Listener создан, физический UID 10575 | Exit 1: `socket parent must be owned by the user or root…` | Подтверждено; дополнительный transport, не STDIO ACP |
| Codex shell snapshot transport | Ошибка materialize допускает fallback | Ошибка materialize допускает fallback | Исходники; это само по себе не запрет shell tool |
| Kimi / Anthropic SDK credentials UID | Warning, функция возвращается | По тому же условию warning | Исходники Kimi; SDK 0.124.0 warning воспроизведён под PRoot; group/world mode checks отдельно могут throw |
| DSH spill write | Успешна, файл UID 10575 | Новый файл UID 0 | PRoot запись подтверждена; cleanup UID-check не защищает путь записи |
| DSH spill cleanup | Android-owned root пропущен с warning | Старый Android-owned root также не проходит равенство UID | PRoot warning подтверждён; cleanup best-effort, не ошибка activation |
| npm global install в отдельный prefix/cache | Успешна, local Codex tarball | Успешна | Подтверждено; сам UID mismatch не равен npm install failure |
| `npm doctor` owner check | Отказ диагностической проверки | Старые UID 10575 не совпадают с 0 | Прямой вызов проверяющего метода подтверждён под PRoot; не install guard |
| Git repository ownership | `git status` успешен: legacy stat видит 0 | `git status` exit 128, dubious ownership | Подтверждено; точное `safe.directory=/workspace` даёт exit 0 |
| SSH implicit `/root/.ssh/config`, UID 10575, mode 0600 | `ssh -G` успешен: fstat видит 0 | Exit 255: `Bad owner or permissions on /root/.ssh/config` | Подтверждено; также затрагивает использующие ssh scp/sftp и Git SSH transport |
| SSH private key owner | Не строгая owner-equality rejection | Сам чужой UID не является таким запретом | `authfile.c`: mode check применяется при `st_uid == getuid()`; ключи и конфиг нельзя смешивать в один диагноз |
| ssh-agent peer credentials | Probe отказал на `bind: Bad address` с ptrace warning | Fresh root agent отвечает «The agent has no identities» | PRoot отказ не доказан как UID mismatch; source содержит отдельный peer UID check |
| tmux default `/tmp/tmux-0` | Свежий PRoot tmux успешен | После PRoot exit 1: `directory /tmp/tmux-0 has unsafe permissions` | Подтверждено для старого каталога UID 10575; точный `tmux -S` в отдельном каталоге успешен в обоих режимах |
| sshd `StrictModes` / authorized_keys | Зависит от stat translation и account UID | Owner 10575 не является root account UID 0 | Исходники `safe_path`/`safe_path_fd`; полноценная авторизация сервера не проверялась |
| pip 26.2.1 cache ownership | Зависит от stat translation Python | Root cache чужого UID отключается | Исходники; warning и `cache_dir=None`, не запрет установки |

Первый npm PRoot probe получил EACCES на **tarball audit fixture**, которому
cloud executor оставил mode 0600. После предоставления этому публичному пакету
доступа для чтения тот же install завершился успешно. Этот EACCES не учитывается
как owner-check дефект npm.

## Codex: точный блокирующий путь и проверка изоляции

В [`uds/src/daemon_directory.rs`](https://github.com/openai/codex/blob/01fc69f4026735edfdf6789820549727a4867b11/codex-rs/uds/src/daemon_directory.rs)
путь строится из `fs::canonicalize("/tmp")`, затем `codex-daemon-{geteuid()}`.
Это **не** `env::temp_dir()`: `TMPDIR` и `CODEX_HOME` этот путь не заменяют.
Каталог должен быть обычным directory, иметь UID текущего процесса и mode 0700.
Guard вызывается в `linux-sandbox/src/bwrap.rs:create_filesystem_args`, поэтому
ему не нужен отдельно запущенный daemon.

Опубликованный Codex ACP `dist/index.js` выбирает по умолчанию режим `agent`,
который использует `workspace-write`. `command/exec` принимает тот же shape
sandbox policy, что thread/turn execution. Для воспроизведения запрос отправлен
непосредственно в Codex app-server, без LLM и без изменения ACP approval mode:

```json
{"id":2,"method":"command/exec","params":{"command":["/bin/sh","-c","printf audit-ok"],"cwd":"/workspace","sandboxPolicy":{"type":"workspaceWrite","writableRoots":["/workspace"],"networkAccess":true,"excludeTmpdirEnvVar":false,"excludeSlashTmp":false},"timeoutMs":5000}}
```

При root и старом daemon-dir UID 10575 получен owner error и exit 1. Контроль
`dangerFullAccess` вернул exit 0 / `audit-ok`; это контроль гипотезы, **не**
рекомендуемое изменение разрешений. Отключать shell tool или менять approval
semantics для исправления владельца не требуется.

`exec-server/src/shell_snapshot.rs` отдельно обрабатывает materialize failure:
первичный probe превращает ошибку в отсутствие descriptor transport, а ошибка
replay пишет `cannot prepare shell snapshot transport; using normal startup`
и возвращает `Ok(None)`. Поэтому одного вызова daemon guard из snapshot code
недостаточно, чтобы объявить shell snapshot блокирующим. Для `bwrap` ошибка
пропагируется и воспроизведена.

Проверена узкая схема: private mount namespace с `MS_REC|MS_PRIVATE`, fresh
source UID 0/mode 0700, bind **только** на `/tmp/codex-daemon-0`.
Старый mountpoint сохранил UID 10575, mode 0700 и тот же inode после выхода
namespace. UID guard внутри namespace прошёл. Широкое изменение `/tmp`, HOME
или workspace не выполнялось.

Первый source под `/root/…/private-codex-run` позволил пройти UID guard, но
не выполнить команду: `Can't mkdir parents for /root/…/private-codex-run:
Permission denied`. `linux-sandbox/src/daemon_mounts.rs` маскирует также
доступные aliases source-каталога. Это причина повторить пробу с фактическим
новым production path `/tmp/md/<22-character base64url id>`.

Новый private bind, созданный actual helper, прошёл owner guard и выполнил
`printf audit-ok` в **`workspaceWrite`**, exit 0. HOME оставался UID 10575/mode
0700, workspace — UID 10575/mode 0755, source имел UID 0/mode 0700. После выхода
namespace старый `/tmp/codex-daemon-0` сохранил UID 10575/mode 0700/тот же inode;
fresh source удалён helper. Это успешный sandbox execution test в privileged
Linux-контейнере, без изменения approval mode и без запроса к LLM.
Bind execution-пробы использовали снимок helper SHA-256 `a79402b2…`;
для окончательного lifecycle-снимка ниже отдельно повторены helper smoke.

Успех имеет существенное условие: в artificial workspace уже существовали
четыре защищённых metadata-каталога `.git`, `.agents`, `.codex`, `.aws`. Их
список задан `protocol/src/permissions.rs`; владение осталось UID 10575.
Без `.aws` тот же scoped bind прошёл UID guard, затем получил
`bwrap: Can't mkdir /workspace/.aws: Permission denied`. Ранее control private
tmpfs дошёл до отсутствующего `.agents`; обычный Docker также ограничивает
user namespaces. Это отдельные sandbox/DAC условия. Создание fixture `.aws`
служило контролем причины, а не предложением менять workspace пользователей.
Работу обычного Android-owned workspace без этих каталогов данный результат
не подтверждает; global chmod/chown workspace не предлагается.

`moru_chroot.c:prepare` уже создаёт отдельный mount namespace для каждого run.
Повторно извлечён **raw constant**, без правки JavaScript, из
`lib/core/services/acp/acp_launch_directories.dart` в
`/tmp/moru-tools-audit/launch-directories.cjs`. SHA-256 проверенного снимка:
`59fb605226c0481f8fd3d14888b9750df1defbdf7664f8d398af8d35f7b0d882`.
Текущие production roots — `/tmp/mc` (Claude) и `/tmp/md` (root Codex), run name
содержит ровно 22 base64url-символа. Helper требует managed marker и mode 0700,
выполняет операции относительно открытого `/proc/self/fd/<fd>`, создаёт run
через staging + rename, сохраняет phase и исходный UID процесса в `.owner`,
повторно проверяет стабильность `/proc` перед очисткой.
Окончательный снимок публикует managed root только после записи marker в
bootstrap stage; брошенные stages проверяются по PID/start. `claim` и чтение
`.owner` привязаны также к run fd, открытому с `O_NOFOLLOW`. Рекурсивная уборка
открывает fd каждого дочернего каталога и использует anchored unlink/rmdir;
`fs.rm` по pathname не применяется.

Этот снимок выполнил `prepare`, `claim`, `codex-target`, `remove`, orphan sweep
ровно по одному разу под честным PRoot UID 10575 и настоящим root через kernel
`chroot /`, с новыми managed roots для проверки bootstrap. Все
FD-anchored операции работали. Fresh directories имели mode 0700 и физический
UID 10575 в PRoot / 0 в root; record сохранял именно физический process UID.
Explicit remove убрал неиспользованный `prepared` run при живом владельце.
`claimed` live run, `prepared` run с inherited env и surviving SDK child после
смерти записанного adapter owner сохранялись; после завершения соответствующих
процессов удалялись. Следующая preparation удалила abandoned claimed run.
Live/protected preparations сохранялись; существующий daemon target не
изменялся. Эти проверки lifecycle дополняют, а не заменяют shell execution test.

## Другие агенты: найденные условия

В Kimi 2.1.1 опубликованный `dist/main.mjs:825` сравнивает owner credentials с
`process.getuid()`, но вызывает `onWarn`. Это Anthropic workload identity,
не обычный Moru TOML config. Mode 0600 следует сохранить: group/world read/write
проверки действительно бросают `WorkloadIdentityError`. Нельзя исправлять этот
warning подменой UID у всех Node-процессов.

У DSH `dsh-spill-local/lib/index.js:137` строгая формула
`stats.uid === process.geteuid() && (stats.mode & 0o022) === 0` участвует в
startup cleanup discovery/sweep. Неподходящий root пропускается с warning.
`saveTextFile` пишет mode 0600 через exclusive `wx`, session directory mode 0700;
`saveText` не вызывает owner guard. Локальный probe сохранил spill-файл UID
10575 и затем получил skipped-unsafe-root warning при cleanup. Практическое
следствие PRoot — возможное накопление spill-файлов, не отказ ACP.

`node-addon-native-custom-loader@0.1.7` использует UID в имени cache-directory,
но не требует `stat.uid == getuid()`. Cache проверяется SHA-256; hard-link
failure имеет rename fallback, затем loading original source. Это другой
механизм, который нельзя объявлять UID blocker только по наличию `getuid`.

У OpenCode проверены `packages/opencode/src`, launcher/postinstall и strings
обоих ARM64 ELF. Найдены runtime/npm-library UID references, но не
подтверждён fatal owner-equality guard в ACP/config/project path. Отсутствие
такого результата не является гарантией для каждого plugin/provider или новой
версии Bun. Подтверждён именно startup + new session в обоих режимах.

## Что делать с остальными инструментами

Для Git оставить доверие конкретному `/workspace`, которое уже предусмотрено
Moru. Подтверждён control `git -c safe.directory=/workspace … status`.
Вложенные самостоятельные репозитории и worktrees требуют собственных точных
entries после проверки реального расположения; `/workspace` не означает
доверие произвольному вложенному репозиторию. Wildcard trust не нужен.

Для SSH различать owner отказ пользовательского config, mode отказ ключа и
peer credentials ssh-agent. В root обычный Android-owned `~/.ssh/config` может
сломать Git SSH transport до соединения. Нужен отдельный согласованный подход
к app-managed SSH config / root scratch, без переназначения владельца всего
HOME. Не отключать `StrictModes` сервера или permission checks глобально.
`ssh-agent` под PRoot проверить отдельно на Android: ошибка bind/ptrace из
данного контейнера не устанавливает причину peer UID mismatch.

Для tmux предпочесть явно выбранный socket (`tmux -S …`) в управляемом
каталоге нужного запуска, сохраняя существующие серверы других сессий. Этот
control проверен. Простое удаление `/tmp/tmux-0` при каждом старте уничтожило
бы пользовательские сессии и не предлагается.

Для npm не применять UID shim или рекурсивное `chown` prefix/cache по сообщению
`doctor`. Сначала различить диагностическое несовпадение владельца и настоящий
EACCES операции. Для pip чужой root cache можно заменить отдельным явно
указанным cache path или отключить cache только в конкретной операции; это
задача скорости/хранилища, не обязательный блокер агента.

Для DSH при необходимости сделать отдельную политику уборки только
доказанно app-managed spill roots, сохраняя symlink, mode и ancestor защиты.
Сейчас warning не требует отключать защиту cleanup. Для Kimi менять нечего по
одному UID warning; для OpenCode ownership workaround по результатам данного
аудита не обоснован.

## Команды и сохранённые свидетельства

Имена пакетов взяты из `AcpAgentSpec.builtIn`, не угаданы по executable name.
Начальное разрешение:

```sh
npm view @openai/codex version repository dist.tarball dist.integrity engines --json
npm view @agentclientprotocol/codex-acp version repository dist.tarball dist.integrity --json
npm view opencode-ai version dist.tarball dist.integrity --json
npm view @moonshot-ai/kimi-code version repository dist.tarball dist.integrity engines --json
npm view @deepseek-ai/dsh version repository dist.tarball dist.integrity --json
```

Пакеты распакованы отдельно, установки не затрагивали global npm пользователя:

```sh
audit_dir=/tmp/moru-tools-audit
npm pack @openai/codex@0.159.3 @agentclientprotocol/codex-acp@2.1.1 --ignore-scripts --pack-destination "$audit_dir/packages" --json
npm pack opencode-ai@1.18.34 opencode-linux-arm64@1.18.34 opencode-linux-arm64-musl@1.18.34 opencode-linux-x64@1.18.34 --ignore-scripts --pack-destination "$audit_dir/packages" --json
npm pack @openai/codex@0.159.3-linux-arm64 @moonshot-ai/kimi-code@2.1.1 @deepseek-ai/dsh@0.2.0-rc.2 --ignore-scripts --pack-destination "$audit_dir/packages" --json
npm install --prefix "$audit_dir/installed/codex" --ignore-scripts --no-audit --no-fund @openai/codex@0.159.3 @agentclientprotocol/codex-acp@2.1.1
npm install --prefix "$audit_dir/installed/kimi" --ignore-scripts --no-audit --no-fund @moonshot-ai/kimi-code@2.1.1
npm install --prefix "$audit_dir/installed/deepseek" --ignore-scripts --no-audit --no-fund @deepseek-ai/dsh@0.2.0-rc.2
```

Основные поиски, дополненные чтением вызывающего кода:

```sh
rg -n 'getuid|geteuid|\.uid\(\)|\.st_uid' source/codex-rust-v0.159.3/codex-rs --glob '*.rs'
rg -n 'process\.get[eu]id|\b(st|stat|stats)\.uid' source/moonshot-ai-kimi-code-2.1.1/package/dist installed/deepseek/node_modules --glob '*.{js,mjs}'
rg -n 'getuid|geteuid|\b(st|stat|stats)\.uid' source/opencode-1.18.34/packages/opencode/src --glob '*.ts'
strings source/openai-codex-0.159.3-linux-arm64/package/vendor/aarch64-unknown-linux-musl/bin/codex > /tmp/moru-tools-audit/metadata/codex-arm64-all-strings.txt
```

Набор smoke запускается в контейнере `moru-tools-ownership`; `/audit` —
read-only bind каталога артефактов. Например:

```sh
docker --host=unix:///var/run/docker.sock exec -u 10575:10575 moru-tools-ownership proot -0 node /audit/probes/acp-smoke.mjs proot codex
docker --host=unix:///var/run/docker.sock exec moru-tools-ownership node /audit/probes/acp-smoke.mjs root codex
docker --host=unix:///var/run/docker.sock exec -u 10575:10575 moru-tools-ownership proot -0 /audit/probes/stat-syscalls /root/proot-fixture/identity
docker --host=unix:///var/run/docker.sock exec moru-tools-ownership node /audit/probes/codex-exec.mjs root
docker --host=unix:///var/run/docker.sock exec -u 10575:10575 moru-tools-ownership proot -0 node /audit/probes/launch-dir-helper-v2.mjs proot /tmp/mc-proot-helper-final
docker --host=unix:///var/run/docker.sock exec moru-tools-ownership chroot / /usr/local/bin/node /audit/probes/launch-dir-helper-v2.mjs root /tmp/md-root-helper-final
docker --host=unix:///var/run/docker.sock run --rm --privileged --env AUDIT_PRECREATE_AWS=1 --mount type=bind,src=/tmp/moru-tools-audit,dst=/audit,readonly --entrypoint /bin/sh public.ecr.aws/docker/library/node:24-bookworm-slim /audit/probes/codex-private-bind-v2.sh
```

Для остальных ACP smoke последний аргумент — `opencode`, `kimi`, `deepseek`.
Контейнер нужно подготовить `probes/setup-fixture.mjs`, создать `/workspace` и
назначить fixtures UID 10575; намеренно не делать это в настоящем HOME/workspace.
Cloud-команды дополнительно очищали Docker endpoint/context/TLS selectors,
сохраняя Docker config, proxy и CA. Последний privileged private-namespace
probe — `probes/codex-private-bind-v2.sh`; без `AUDIT_PRECREATE_AWS=1` он
воспроизводит отдельный scaffold/DAC отказ. Эти fixtures не являются
production setup scripts.

| Файл в `/tmp/moru-tools-audit/metadata` | Свидетельство |
| --- | --- |
| `acp-{proot,root}-{codex,opencode,kimi,deepseek}.json` | Восемь успешных `initialize` + `session/new` |
| `native-proot.json`, `native-root.json` | Git, SSH config/agent, tmux, root npm install; первый npm PRoot EACCES fixture |
| `npm-proot-install.log` | Исправленный readable-fixture npm install успешен |
| `node-owner-proot.json` | SDK warning при credentials UID 10575; отказ только npm doctor метода |
| `spill-proot.json` | DSH успешная запись и skipped cleanup warning |
| `codex-exec-root-android-daemon.json` | Подтверждённый root workspaceWrite owner blocker |
| `codex-exec-proot.json` | PRoot guard пройден; exit 182 следующего sandbox слоя |
| `codex-proot-unix.log`, `codex-root-unix.log` | Различие native Unix listener и его parent owner check |
| `codex-exec-root-owned-daemon.json` | Устранён только owner error; затем namespace restriction обычного Docker |
| `codex-private-bind{,-repo}.jsonl` | Private bind UID guard; прежние UID/mode/inode mountpoint сохранены; отдельный bwrap alias/DAC отказ |
| `codex-private-tmpfs.jsonl` | Дополнительный control одного leaf; отдельный workspace scaffold/DAC отказ |
| `codex-private-bind-v2.jsonl` | Новый `/tmp/md/<22>` + actual helper; UID guard пройден, затем missing `.aws` mkdir EACCES |
| `codex-private-bind-v2-preexisting-metadata.jsonl` | Успешный `workspaceWrite` exit 0; old target UID/mode/inode сохранены, source cleanup успешен |
| `launch-helper-final-source.json` | Окончательный raw helper SHA-256 и путь исходного Dart constant |
| `launch-helper-final-{proot,root}.json` | Окончательный helper с atomic root bootstrap + per-run fd; prepared/claimed/SDK-child lifecycle, orphan sweep, target unchanged |
| `launch-helper-v2-{source,proot,root}.json` | Предыдущий FD-anchored root snapshot, использованный также для bind execution-проб |
| `launch-helper-{proot,root}.json` | Исторический smoke предыдущего helper; для итогового снимка использовать `final` |
| `tarball-sha256.json`, `native-pack.json`, `*-ownership-strings.txt` | Версии/целостность и binary strings |

Дополнительный smoke: Claude native 2.1.287 +
ACP 0.85.0 успешно выполнили `initialize` и `session/new` в обоих режимах с
fresh scratch mode 0700 и `CLAUDE_CODE_CONTAINER_ID`. Старый `/tmp/claude-0`
UID 10575 оставлен без изменений. Артефакты `acp-{proot,root}-claude.json`;
основной разбор Claude находится в `docs/audits/claude-code-temp-ownership.md`.

Следующая проверка на телефоне должна выполнить реальную shell-команду Codex
в обычном ACP режиме до и после root/PRoot переключения, проверить private bind
alias isolation при Android-owned HOME/workspace и подтвердить, что завершение
одного агента не меняет владельцев или сокеты другой живой сессии. Сначала
нужен этот результат; успешного `initialize` для такого вывода недостаточно.

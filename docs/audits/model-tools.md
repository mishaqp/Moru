# Аудит инструментов модели

Проверены все 46 определений объединённого каталога (оба режима памяти,
локальные, workspace и search), все 27 действий browser_use, встроенный MCP fetch
и общие пути MCP/подтверждений/приватности/Stop. Отключённые Android-инструменты
тоже остаются в проверке схем и зарезервированных имён. Версия — 0.1.47+48.

Изменения ограничены доказанными небольшими ошибками. Новых правил подтверждения,
публичных имён, миграций настроек или фоновых lifetime не вводится. Каждый
функциональный fix проверен регрессией, которая сначала воспроизводила ошибку.
Перечень схем и граница конвертации — [tool-schemas.md](../tool-schemas.md).

## Результаты по инструментам

| Инструмент | Что найдено и проверено | Итог |
| --- | --- | --- |
| calculate | Заявленные операторы/функции есть; ошибки parse/math структурированы. Нестрогие типы и отсутствие вычислительного лимита — D7/D8. | Обработчик без изменений. |
| get_time_info | Пустые аргументы, небольшая структура даты/зоны, без записи. | Ошибок не найдено. |
| clipboard_tool | read/write, text только для write; null не должен стать строкой. Нестрогий тип текста/неограниченный результат — D7/D8. | Device null удаляется перед native call. |
| text_to_speech | Успех означает запуск проигрывания; звук может идти в фоне. Нестрогий текст/длина — D7/D8. | Подтверждения и playback сохранены. |
| ask_user_input_v0 | Цикл генерации ID мог зависнуть; заменённая заявка и dispose оставляли Future. Cross-chat ID/владелец — D6. | Исправлены ID, отмена замены/dispose и поздний request. |
| get_screen_time | top 1–50, Usage Access, interval; null optional мешал native defaults. | Исправлен общий device bridge. |
| calendar_query | Экранирование title, limit 1–100, calendar filter; поля ограничены числом строк, не общим объёмом — D7. | Исправлен optional-null bridge. |
| calendar_create | Обязательные title/start, writable calendar и интервал до insert. All-day end отличается от обычного. | Null bridge и описание next-local-day; подтверждение/live permission в caller. |
| calendar_update | event_id, ограничения recurring, пустые строки/[] — явный сброс; null optional мог менять событие. | Null bridge; повторная проверка прав после согласия. |
| calendar_delete | Writable event и существование до удаления, удаление серии описано. | Caller отказывает без службы согласия; полный доступ сохранён. |
| get_current_location | Native permission/BUSY/20s timeout; Stop поколения не связан с native request — D4. | Сервис без изменений. |
| phone_control | Все действия enum сопоставлены native/root: чтение, tap/long_press/set_text/scroll/swipe, навигация, list_apps/open_app. Native screen ограничен, password скрыт, snapshot одноразовый. Root отличался. | Root скрывает password и потомков; ошибка list_apps становится ROOT_FAILED. Native optional null удаляется. Большие root вопросы — D3/D4/D8. |
| root_shell | Команда String <=8k, timeout 1–300, хвосты stdout/stderr по 16 KiB и truncated. Классификатор чтения небезопасен — D3. | Политика сохранена; проблемы классификатора документированы. |
| manage_scheduled_tasks | list/create/update/delete, расписание/assistant/target до save. Null weekdays/start/end мог отменить прежние значения. | Null как отсутствие; явный '' остаётся сбросом. D4/D7/D8 остаются. |
| mini_apps | Проверены list/read/write/remove/errors/versions/rollback/jobs/run_job/server/delete_job/delete. value:null — данные; один ключ может вернуть до 5 MiB — D7. | Добавлен null roundtrip, strict fallback. Удаления сохраняют согласие. |
| manage_assistants | Все 8 действий, каждый вид settings/clear; null optional, regex bool и неfinite numbers расходились со схемой; заголовки попадали в public result/args. | Исправлены null/валидация/редакция результата, аргументов, истории и согласия; raw настройки остаются raw. Старые секреты сохраняются в приватном redaction-set при rotation. D5/D7/D9 остаются. |
| manage_mcp | Все 15 действий, live IDs, конфиг/patch/import/cwd/workspace/null; test.error раскрывал секрет другого сервера. | Null optional пропускается; cwd/workspace null-сброс сохранён non-strict. Ошибки редактируются по всем серверам. Новое согласие при повторе ID. |
| spend_control | status/compact/set_limits, положительные конечные budgets, atomic patch, live права и Stop. Strict optional null ошибочно считался изменением. | Null limits/clear/вложенных полей = отсутствие; явный clear отключает лимит. |
| report_problem | ZIP/journal/metadata bounded, allowlist, секреты очищаются до ZIP; Share использует checked descriptor/private snapshot, срок24 h. Always allow запрещён. | Сервис без изменений; описание согласовано с полным доступом. |
| memory_read | Scope/ids/type/limit, enableMemory, нет записи; aggregate bounds — D7. | Без изменений обработчика. |
| memory_update | Неверные content/scope могли попасть в Smart Add/запись. Отмена LLM переходила в fallback и запись. | Обязательная String content и supplied scope проверяются до работы; per-item Smart Add проверяет captured Stop до записи и вместо fallback. |
| memory_edit | Обязательный content приводился к String. | Неверный content отклоняется до записи. |
| memory_delete | Живые ID/scope, structured errors; captured commit guard — D4. | Существующее поведение сохранено. |
| memory_search_profile | Поиск по разрешённой памяти/profile, нет записи; объём — D7. | Без изменений обработчика. |
| update_user_profile | Missing/null value мог стереть ключ вместо ошибки. Поэлементный частичный успех — существующий контракт. | Требуется String value; только '' явно удаляет значение. |
| chat_search | Past-recall gate, assistant scope, limit<=20, сниппеты. Полные summaries не имеют общего cap — D7. | Scope и существующая выборка сохранены. |
| create_memory | Legacy required content приводился из bool/number; временный чат сохранял запись. | String до записи, временные чаты запрещены как в v2. |
| edit_memory | Legacy fractional id приводился к int; запись чужого assistant редактировалась по общему id. | Integer/content validation; owner проверяется внутри сериализованной операции store. |
| delete_memory | Legacy общий id позволял удалить чужую запись; temporary-chat gate отсутствовал. | Integer, owner и temporary checks до записи; чужой id даёт memory_not_found. |
| search_web | Пустая/non-string query могла отправиться в сеть. Ошибки/объём результатов — D7/D5. | Query валидируется до сетевой работы. |
| shell | Workspace/runtime/cwd/timeout/background и foreground Stop. Разрешение могли отозвать во время согласия. | Enabled проверяется снова перед запуском. Background jobs сохраняются. D1/D2/D9 остаются. |
| shell_output | Conversation-scoped job ID, wait0–120, хвост8k/4k. Runtime capture теряется между сервисами — D2. | Без смены lifecycle; redesign предложен. |
| read_file | Checked descriptor, paging32 KiB и binary256 B; image read без byte cap — D7. | Граница файлов сохранена. |
| write_file | null/non-string content мог обнулить или заменить файл. | String проверяется до согласия/записи; '' допустим. |
| edit_file | null/non-string old/new_string мог испортить файл. Полный исходный файл не bounded — D7. | Оба String до записи; '' для замены допустим. |
| list_dir | Checked traversal, cap500, materialization до cap — D7. | Без изменений. |
| glob | Checked traversal, cap500, корень workspace по умолчанию. | Без изменений. |
| grep | >2MiB/binary пропускаются; limit и целая строка без общего cap — D7. | Без изменений. |
| update_plan | Неверные entries/status молча терялись и заменяли план. Совет exactly-one-progress не соответствует всем допустимым планам — D8. | Все step/status проверяются до replace; tolerant saved-history parser сохранён. |
| publish_mini_app | Missing/null path публиковал cwd; неString превращался в путь. | path валидируется до install. Async commit lifecycle — D9. |
| browser_use | Все 27 действий, settings action gate, подтверждения мутаций, challenge/auth/history и bounded чтение. | type String; fetch<=65536; stale auth title не записывается под новым URL; disabled action после согласия отклоняется. D1/D4/D7/D8 остаются. |
| get_weather | Зарезервирован, не доступен Android. | Схема проверяется; dispatch не включён. |
| get_health_summary | Зарезервирован HealthKit, не доступен Android. | Схема проверяется; dispatch не включён. |
| reminders_query | Зарезервирован, не доступен Android. | Схема проверяется; dispatch не включён. |
| reminders_create | Зарезервирован, не доступен Android. | Схема проверяется; dispatch не включён. |
| reminders_complete | Зарезервирован, не доступен Android. | Схема проверяется; dispatch не включён. |
| MCP / встроенный kelivo_fetch | Маршрут live, коллизии встроенных имён, privacy, original schema, optional-null. Fetch GET/POST, max_length<=20k, POST continuation запрещён; транспортные ограничения — D10. | Сохранены minimum/maximum/unions; MCP не вызывается без необходимого согласия; synthetic null удаляется перед сервером. |

## Browser: все действия

| Действия | Проверка и итог |
| --- | --- |
| open, observe | http(s), readiness/challenge и компактное состояние; auth URL не сохраняется в публичную историю. |
| screenshot | Snapshot принадлежит chat/tab/action; private authenticated page identity не публикуется, bytes сохраняются для checked image результата. |
| click, hover | Element/coordinates и viewport; click требует согласия, hover сохраняет текущую политику. Нестрогий numeric parsing — D8. |
| type, submit, press_key | Required target/text/key, form validation, согласие/challenge. type больше не очищает поле при missing/null text. |
| scroll, back, forward, reload | Direction/bounds/history, bounded settle и Stop; текущие политики сохранены. |
| read, collect, outline | Read100–65536, corpus128 KiB, cache24/4 MiB/45min; collect<=200 и scrolls<=30. Raw mode/enum coercion — D8. |
| wait_for, wait_stable | selector/state, Stop и bounded timeout; false-result отмечается как not-found/unstable. Shared minimum200 против effective500 у wait_stable — D8. |
| eval_js, fetch | Согласие на JS/HTTP mutation, JS guard без обещания sandbox; output64Ki/fetch65536. Native JS wait — D4. |
| export_cookies | Workspace, согласие и action gate после ожидания; результат содержит путь/имена, не значения cookies. Unsafe file export — D1. |
| tabs, new_tab, switch_tab, close_tab | Opaque IDs, max5, reuse WebView, concurrent reservation; неизвестный tab возвращает ошибку. |
| set_mode, done, close | Exact desktop/mobile, completion/close lifecycle. Summary cap и concurrent action owner — D7/D4. |

## Общие исправления и сохранённые правила

- Согласие относится к конкретным исходным аргументам. Одинаковый ID с другими
  аргументами отменяет прежнюю заявку и создаёт новую. Сравнивается приватная
  неизменяемая копия, а не редактированная карточка. Идентичный повтор совместим.
- Если подтверждение необходимо, отсутствие ToolApprovalService возвращает
  `approval_unavailable`. Сохранённый глобальный полный доступ пропускает согласие,
  включая report_problem/manage_mcp/spend_control. Для этих трёх нет отдельного
  «Всегда разрешать»; private MCP input остаётся отдельным Save/Cancel.
- После ожидания проверяются отмена, текущий assistant/tool и action settings.
  ask_user также проверяет владельца/права после ответа. Ошибки caller становятся
  structured tool error, не заканчивают целый ответ.
- ToolCallArgumentPrivacy/McpToolPrivacy продолжают отделять execution от public
  arguments/results/history. Для assistant settings добавлена public-copy
  редакция header secrets с сохранением протокольных ID/enum. Глобального нового
  фильтра произвольного текста или настройки приватности не введено.
- Stop закрывает существующие approval/ask futures и карточки поколения,
  останавливает foreground workspace. Явные background shell jobs живут дальше.
  Гарантию физической отмены уже начатого native действия этот аудит не добавляет.

## Крупные проблемы, оставленные без изменения

| ID | Наблюдение/доказательство | Предложение |
| --- | --- | --- |
| D1 | `ToolOutputOffloader` строит `outputs/<raw toolCallId>.txt`; `../../outside` записывает за пределами outputs. Cookie export пишет через File по предсказуемому имени и следует внешней symlink. Обе записи воспроизведены на временных файлах с синтетическими данными. | Независимое безопасное имя; captured WorkspaceFileAccess и parent descriptor для создания/записи/chmod. Не ограничиваться lexical check или переоткрытием пути. Требуется совместное изменение владельца и storage API. |
| D2 | `_backgroundJobs` хранит runtime только в WorkspaceToolsService; следующий ответ создаёт новый сервис, shell_output может использовать текущий runtime вместо runtime job. | Cancellation owner в registry/run, scoped by conversation; тест двух поколений и смены runtime. Stop ответа не должен убивать фоновые jobs. |
| D3 | `RootShellTool.isReadOnly` считает читающими `env sh -c ...`, произвольный `/data/local/tmp/cat`, `logcat -d -c/-f`, `sort --output`, `date` с установкой и `dumpsys battery set`. Проверен только классификатор, реальные команды не исполнялись. | Trusted executable resolution и безопасные аргументы каждой команды. Это меняет решения о согласии, поэтому отдельная задача. |
| D4 | Per-item Smart Add теперь отказывает после отмены LLM. Batch Smart Add и последующие async repository commits, root/native/device/queued mini-app/task work не всегда имеет commit guard. Browser использует один mutable stop signal; direct JS await может зависнуть, неожиданный PlatformException оставляет activity pending. | Captured generation/owner guard перед commit; process cancellation; action tokens/serialization для браузера; finally только для собственной карточки. Проверить каждую async границу, не заявлять физическую отмену native side effect без доказательства. |
| D5 | Известные/classified assistant header secrets теперь скрыты, но для новых секретов в произвольном body/prompt нет private-input/reference контракта. Search/fetch exceptions могут раскрыть неизвестные credentials в URL/тексте. | Явные private inputs/reference с существующим secret approval UI; privacy для URL/header/error, без миграции raw execution настроек. |
| D6 | Ask-user хранит pending по одному toolCallId, без conversation/generation key; параллельные чаты могут заменить/ответить друг другу. | Scoped key и captured owner, cancelForRun; тест одинаковых ID в разных чатах. Текущая замена не оставляет Future, но redesign не выполнен. |
| D7 | Результаты mini-app одного ключа до 5 MiB, tasks с полными prompts, memory/profile/chat summaries/search/clipboard/assistant списки; image/edit/grep/dir resource materialization не имеют общего byte/char cap. | Согласовать paging/chunk handles, bounded summaries и явный truncated; лимитировать до decode/allocation. Нельзя молча обрезать сохранённый JSON и менять формат приложений. |
| D8 | Clipboard/TTS/calculate/scheduled и часть workspace/browser/root принимает coercion или fallback invalid enum; root координаты/текст/XML static file отличаются от native; update_plan exactly-one-progress остаётся советом. | Action-specific typed validation и согласованные условные схемы; root/native protocol parity. Совместимость валидных старых аргументов и изменения строгих отказов решить отдельно. |
| D9 | Workspace context/runtime captured at generation start; write/edit после outside-write consent и publish install не везде повторно проверяют live switch/owner. Manager rollback/trust snapshots не универсально transactional. | Guard перед каждой записью/commit и tests revoke/Stop после await; сохранить текущие правила разрешённых зон/подтверждения. |
| D10 | Built-in fetch сначала буферизует всё HTTP-body; нет явного timeout/cancel/body budget. Public-only/history-known URL и отсутствие auth заявлены в описании, но scheme-only engine этого не обеспечивает. | Streaming byte limits/timeout/cancel и отдельное решение history/origin/header policy. POST продолжения остаются запрещены. |

D1–D10 не исправлены: они требуют изменения storage/lifecycle/policy/валидной
совместимости, выходящего за небольшой fix. Это обнаруженные границы работы,
а не утверждение о полной защите или полном покрытии Android E2E.

## Воспроизводимость и проверки

Новые регрессии находятся рядом с существующими: `tool_schema_*`, handler policy
и browser approval, approval identity, assistant public-copy privacy, ask-user,
workspace mutation/plan/publish/revocation, browser type/fetch/title, local bridge,
root privacy/failure, scheduled/spend/MCP/assistant null, memory/profile/legacy и отмена Smart Add.
Fetch-JS тест исполняет production JS в Node на локальной синтетической странице;
provider тесты перехватывают настоящий request body локально.

Локальный общий затронутый прогон: **2476 passed** в **240 файлах**. После
последних исправлений отдельно повторены память — **164 passed**, и
MCP/normalizer/HTTP-provider/handler — **133 passed**. Это пересекающиеся наборы,
их числа не складываются. `dart analyze --fatal-infos lib test integration_test`
проходит без замечаний; форматирование изменённых Dart и `git diff --check`
прошли. Python policy/APK verifier/release keep rules: **14 + 6 + 3**.
Автоматический PR CI фильтрует только master; ручной debug workflow тоже
пропускает полный Flutter-набор. Для указанной feature-базы полный прогон
выполняется локально; workflow не изменён.
Полный `flutter test --no-pub --reporter expanded`: **8193 passed**.
Во время этого прогона Dart-исходники не менялись (проверено SHA-256);
форматирование **54 изменённых Dart-файлов** не требует правок.
APK и физический телефон в этой задаче не проверялись; live provider API,
native Android Stop/permission и крупные пункты D1–D10 остаются отдельной
проверкой/работой.

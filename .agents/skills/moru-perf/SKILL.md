---
name: moru-perf
description: Use when Moru has UI lag, slow frames, delayed chat sending or streaming, or excessive widget rebuilds.
---

# Производительность Moru

Готовый результат — устранённая измеренная причина задержки и сопоставимые числа до/после. Ограничения пользователя на объём, тесты, сборки и версию имеют приоритет над скилом; не запускай запрещённые проверки.

Для платформенных границ см. [Moru product scope — read first](../../../AGENTS.md#moru-product-scope--read-first), для измерений — [Benchmarks are not tests](../../../AGENTS.md#benchmarks-are-not-tests). Правила выбора контекста и минимальной правки: [Главные правила](../../../docs/prompting-codex.md#главные-правила).

## Где искать причину

| Симптом | Источник |
| --- | --- |
| Отправка, первые токены, приход карточки в длинном чате | [long_chat_send_bench.dart](../../../test/perf/long_chat_send_bench.dart), [ChatUiWork](../../../lib/features/chat/utils/chat_ui_work.dart) |
| Прокрутка ленты | [timeline_scroll_bench.dart](../../../test/perf/timeline_scroll_bench.dart) |
| Перестройки всей темы | [app_theme_rebuild_bench.dart](../../../test/perf/app_theme_rebuild_bench.dart) |
| Кадры на Android-устройстве | [FlutterLogger](../../../lib/core/services/logging/flutter_logger.dart), существующий `report_problem` |

При включённом журнале Flutter `FlutterLogger` собирает кадры дольше 100 мс в ограниченные сводки не чаще раза в секунду: количество, total/build/raster самого долгого кадра. Они входят в ZIP и `recent_events`; это не полная трасса каждого кадра. Сохраняй действующие согласие и приватность `report_problem`, см. пункт Problem reports в [Chat features that already exist — do not reimplement](../../../AGENTS.md#chat-features-that-already-exist--do-not-reimplement) и [PR #94](https://github.com/mishaqp/Moru/pull/94).

## Измерение и минимальная правка

Зафиксируй воспроизводимый сценарий, размер истории, устройство/контейнер, Flutter и режим сборки. Сравни одинаковый прогретый сценарий до/после; для открытия используй новые объекты истории, чтобы кэш прошлого открытия не скрывал работу.

Выбирай подходящий файл из [test/perf](../../../test/perf/). `*_bench.dart` печатают времена без `expect()`; успешный выход команды не доказывает ускорение. Например, из корня репозитория:

```sh
flutter test test/perf/long_chat_send_bench.dart --reporter expanded
flutter test test/perf/long_chat_send_bench.dart --enable-vmservice --dart-define=CPU_PROFILE=true --dart-define=PERF_OUTPUT=/tmp/moru-long-chat --reporter expanded
```

Этот debug widget benchmark измеряет `drawFrame` (build/layout/paint, без raster), а не release FrameTiming на телефоне. Смотри `buildMaxMs`, `buildP90Ms`, `uiMaxMs`, `uiP90Ms`, id построенных сообщений и счётчики работы; frames/Timeline и необязательный CPU-профиль сохраняются в `/tmp`.

Если виджету нужна часть Provider, используй `context.select` вместо подписки через `watch` на весь объект. Реальный пример из [chat_message_widget.dart](../../../lib/features/chat/widgets/chat_message_widget.dart):

```dart
final userName = context.select<UserProvider, String>((u) => u.name);
```

Сохраняй узкие подписки и правильную инвалидацию, а не добавляй глобальный кэш виджетов:

- [decodeTimelineToolPart](../../../lib/features/chat/widgets/timeline_projection.dart) использует `Expando` по неизменяемому `ToolCallPart`: новый payload должен дать новый снимок даже при прежних id/version; weak-кэш не удерживает удалённые части.
- В [chat_message_widget.dart](../../../lib/features/chat/widgets/chat_message_widget.dart) кэш `ComputerStep` дополнительно учитывает ordinal и захваченный `ToolDisplayRedaction`; не переиспользуй результат с другим фильтром показа.
- [_CachedChatMessage](../../../lib/features/home/widgets/message_list_view.dart) живёт в смонтированной строке и проверяет `inputs`; потомки продолжают получать изменения темы, настроек, TTS и подтверждений. Не удерживай callback с размонтированным context.
- Для тяжёлой чистой обработки данных подходит `compute` с передаваемым снимком, без Provider/BuildContext и побочных UI-действий. Пример — `_prettyJson` и порог 64 × 1024 кодовых единиц UTF-16 в [log_viewer_page.dart](../../../lib/features/settings/pages/log_viewer_page.dart); после ожидания сохраняй проверку `mounted`.

## Критерий готовности

В отчёте укажи сценарий, сопоставимые max/p90, число build/JSON-декодирований, причину ускорения и оставшуюся задержку. Если замеры запрещены, явно отдели проверенные факты от неподтверждённого ускорения.

Ориентир [PR #96](https://github.com/mishaqp/Moru/pull/96): в его сценарии худший build отправки 63,26 → 35,29 мс, первых токенов 42,33 → 13,70 мс; build при потоке 465 → 69, JSON-декодирования 198 → 0. Первое открытие осталось выше 50 мс. Это исторический сравнительный замер, не обещание текущих результатов на Android.

# Схемы и примеры локальных инструментов

## Контракт новой или изменённой схемы

Совместимость со strict function calling OpenAI и Gemini проверяется при каждой правке схемы, включая добавление поля или действия существующего инструмента.

- Для OpenAI strict у каждого object, включая вложенные объекты и элементы массивов, требуется `additionalProperties: false`; `required` перечисляет все свойства. Необязательность выражается nullable-значением, а не пропуском имени из `required`. Проверь, что null остаётся допустимым после фактического преобразования и отправки.
- Для Gemini проверь итоговый допустимый набор REST Schema полей, типы и enum, представление nullable-значений, `required` и `items` массивов. OpenAI-схема сама по себе не доказывает совместимость с Gemini.
- В обработчике проверь отсутствие поля, null и явный сброс по контракту действия. Дополнительные поля другого действия, присланные strict-вызовом, не должны превращать чтение в изменение. Потеря nullable или искажение `required` в преобразовании означает, что совместимость ещё не подтверждена.

## Реальные границы преобразования

- [toResponsesToolsFormat](../../../lib/core/services/api/providers/openai/responses_api.dart) переносит параметры и уже заданный `strict` в Responses API. Он не выставляет `strict` автоматически и не добавляет `required`, `additionalProperties: false` или nullable-типы.
- Текущий MCP-путь не гарантирует strict-форму: `ToolHandlerService.sanitizeToolParametersForProvider` разворачивает локальные `$ref`, берёт первый вариант `anyOf`/`oneOf`/`allOf` и первый тип из массива `type`, отбрасывает `nullable`, сохраняет исходный `required`. Этот sanitizer применяется к MCP, а не автоматически ко всем локальным определениям.
- Поэтому нельзя считать `type: ['string', 'null']` сохранившим null через MCP sanitizer или обещать общую strict-поддержку на основании передачи флага. Сверяй исходную локальную схему и фактический путь отправки; семантику отсутствующего значения, null и сброса проверяй в обработчике.
- Gemini отправляет определения через [google_common.dart](../../../lib/core/services/api/providers/google_common.dart) и `cleanSchemaForGemini(..., stringEnumOnly: true)` в [chat_api_helpers.dart](../../../lib/core/services/api/chat_api_helpers.dart). Чистка оставляет допустимые REST Schema поля, удаляет `additionalProperties`, exclusive bounds и `uniqueItems`; для enum сохраняет строки, у boolean/чисел снимает enum с сохранением типа. Добавляет недостающие `items` массивов и свойства для имён из `required`. Не полагайся на эти запасные формы вместо точного определения инструмента.
- Локальные схемы и MCP sanitizer проходят разные пути. Сам `cleanSchemaForGemini` допускает `nullable` и `anyOf`, но MCP sanitizer отбрасывает `nullable` и сворачивает варианты до этой чистки.

## Проверенные места проверки

| Случай | Существующий тест |
|---|---|
| Имена и безусловное резервирование | [built_in_tool_names_test.dart](../../../test/features/home/services/built_in_tool_names_test.dart) |
| Подтверждение, владелец и отмена | [tool_approval_service_test.dart](../../../test/features/home/services/tool_approval_service_test.dart) |
| Полный доступ и гонка обновления настроек | [report_problem_tool_test.dart](../../../test/features/home/services/report_problem_tool_test.dart) |
| Приватные поля, отказы, полный доступ, MCP | [mcp_manager_tool_test.dart](../../../test/features/home/services/mcp_manager_tool_test.dart) |
| Частичные аргументы, отмена, ошибки и retry | [tool_call_argument_privacy_test.dart](../../../test/core/services/api/tool_call_argument_privacy_test.dart) |
| MCP-схемы и ограничения провайдеров | [tool_handler_service_test.dart](../../../test/features/home/services/tool_handler_service_test.dart) |
| Gemini: ограничения и enum | [constraints](../../../test/gemini_tool_schema_constraints_test.dart), [enum](../../../test/gemini_tool_schema_enum_test.dart) |
| Дополнительные поля от strict-вызова не меняют чтение `status` | [spend_control_tool_test.dart](../../../test/features/home/services/spend_control_tool_test.dart) |
| Схема и значения settings ассистента | [assistant_manager_tool_test.dart](../../../test/features/home/services/assistant_manager_tool_test.dart) |

Эти тесты не доказывают общую нормализацию OpenAI strict nullable/required: такой гарантии в текущем коде нет.

## Примеры PR

- [#95](https://github.com/mishaqp/Moru/pull/95) — управление MCP из чата и приватный ввод секретов.
- [#97](https://github.com/mishaqp/Moru/pull/97) — исправления секретов `manage_mcp` и выбора рабочей папки чата.
- [#99](https://github.com/mishaqp/Moru/pull/99) — полное управление MCP, повторное использование приватных значений и очистка опубликованных аргументов.

## Пример поиска

Задача: «Добавить действие `manage_mcp`, которому нужен токен». Начни с `McpManagerTool` и `ToolHandlerService`; найди приватную карточку в `ToolApprovalService` и фильтр `ToolCallArgumentPrivacy`. В полном доступе оставь ввод недостающего токена, исключи индивидуальное «Всегда разрешать», проверь публикацию отклонённых аргументов и итоговую схему каждого провайдера. Токен не становится аргументом модели.

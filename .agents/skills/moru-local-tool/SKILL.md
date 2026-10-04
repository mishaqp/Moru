---
name: moru-local-tool
description: Use when adding or changing a model-callable local tool in Moru, its approval or private arguments, or the manage_assistants schema for a user-facing Assistant field.
---

# Локальные инструменты Moru

Инструкции пользователя имеют приоритет над навыком. Границы продукта и уже готовые инструменты смотри в [AGENTS.md](../../../AGENTS.md), разделы «Moru product scope — read first» и «Chat features that already exist — do not reimplement».

## Точки входа

| Что меняется | Где смотреть |
|---|---|
| Имя, доступность, схема, необходимость подтверждения | `LocalToolNames` и `LocalToolsService` в [local_tools_service.dart](../../../lib/features/home/services/local_tools_service.dart) |
| Исполнение и актуальные разрешения | [ToolHandlerService](../../../lib/features/home/services/tool_handler_service.dart) |
| Подтверждение и приватный ввод | [ToolApprovalService](../../../lib/features/home/services/tool_approval_service.dart) |
| Настройки и подпись инструмента | [local tools tab](../../../lib/features/assistant/pages/assistant_settings_edit_local_tools_tab.dart), [local_tool_labels.dart](../../../lib/features/home/services/local_tool_labels.dart) |

## Контракт правки

1. Найди ближайший существующий инструмент и расширяй его путь. Новое имя добавь в `LocalToolNames.all`: [BuiltInToolNames](../../../lib/features/home/services/built_in_tool_names.dart) резервирует эти имена для исключения коллизий с MCP даже при выключенном инструменте. Обнови явный список в [built_in_tool_names_test.dart](../../../test/features/home/services/built_in_tool_names_test.dart); проверь [каталог схем](../../../lib/core/services/tools/built_in_tool_catalog.dart), если инструмент должен появиться в редакторе.
2. Согласуй описание, схему аргументов, обработчик, переключатель ассистента и доступность. Проверяй аргументы в обработчике до изменения состояния; схема провайдера не заменяет проверку. Для нового пользовательского поля [Assistant](../../../lib/core/models/assistant.dart) синхронизируй `manage_assistants`: схему settings, чтение, применение, проверку значений и сброс, когда поле поддерживает сброс, в [AssistantManagerTool](../../../lib/features/home/services/assistant_manager_tool.dart).
3. Выбери подтверждение по действию. Используй существующие `LocalToolNames.requiresApprovalFor` и `ToolApprovalService`; после ожидания снова проверь актуальное разрешение и живого владельца ответа. Отказ, отмена или недоступное обязательное подтверждение должны завершить вызов без изменения состояния.
4. Учитывай сохранённое `SettingsProvider.toolAutoApproveAll`, включая изменение настройки до обновления сервиса. Полный доступ пропускает согласие; недостающий секрет по-прежнему требует приватного ввода. Индивидуальное «Всегда разрешать» доступно не всем: `ToolApprovalRequest.requiresExplicitConsent` исключает его для `report_problem`, `manage_mcp` и `spend_control`.
5. Секреты вводит пользователь в приватных полях карточки. Не помещай их в модельные аргументы, результат, историю или журнал. [ToolCallArgumentPrivacy](../../../lib/core/services/api/tool_call_argument_privacy.dart) разделяет исходные аргументы исполнения и очищенные копии для модели, стрима и продолжения запроса; сохраняй политику через `register`/`propagate` при обёртках обработчика. Для MCP используй существующий [McpToolPrivacy](../../../lib/core/services/mcp/mcp_tool_privacy.dart), включая отклонённые вызовы и повторные запросы.

## Схемы и проверка

Каждая новая или изменённая схема должна быть совместима со strict function calling OpenAI и Gemini. Проверяй итоговую форму **после** преобразования: для OpenAI рекурсивно закрытые object-схемы (`additionalProperties: false`), все свойства в `required`, необязательные значения через nullable; для Gemini — допустимую REST Schema форму. В обработчике различай отсутствие значения, null и явный сброс по контракту действия. Текущий код не обеспечивает общую strict-нормализацию: переданный флаг `strict` не доказывает совместимость. Требования и реальные ограничения — в [references.md](references.md).

Выбирай проверки по изменённому поведению: имена и opt-in; чтение против изменения; отказ, отмена и отзыв разрешения; обычное согласие и полный доступ; приватный ввод и отсутствие секретов в опубликованных копиях; итоговые схемы провайдеров. Выполняй только разрешённые пользователем проверки. Для документационной задачи достаточно сверить ссылки и символы, без запуска приложения или его тестов.

После пользовательской правки применяй `moru-release-notes`. Общие правила проверок смотри в [AGENTS.md](../../../AGENTS.md), разделы «Pre-commit checklist» и «Tests must be deterministic».

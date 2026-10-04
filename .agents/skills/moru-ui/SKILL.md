---
name: moru-ui
description: Use when adding a screen or widget to Moru, or changing an existing Android screen's layout or interaction.
---

# Интерфейс Moru

Готовый результат — изменение в существующем Android-интерфейсе, которое сохраняет тему, доступность управления и адаптивную раскладку. Границы пользователя, включая запрет тестов, сборок и изменения версии, имеют приоритет над скилом.

Основные правила: [UI guidelines](../../../AGENTS.md#ui-guidelines) и [Architecture](../../../AGENTS.md#architecture). Платформенные границы: [Moru product scope — read first](../../../AGENTS.md#moru-product-scope--read-first). Применяй минимальную правку из [Главных правил](../../../docs/prompting-codex.md#главные-правила).

## Общие компоненты и примеры

Ищи эквивалент в [lib/shared/widgets](../../../lib/shared/widgets/) и [lib/shared/dialogs](../../../lib/shared/dialogs/) перед созданием нового компонента. Названия `Ios*` здесь обозначают стиль общих Android-виджетов.

| Нужный элемент | Проверенный источник |
| --- | --- |
| Группа строк или содержимое карточки | [SectionCard](../../../lib/shared/widgets/section_card.dart): `children` или `child`, при необходимости `dividers` |
| Панель с заголовком, раскрытием и прокруткой | [CustomBottomSheet / showCustomBottomSheet](../../../lib/shared/widgets/custom_bottom_sheet.dart): `builder` получает `ScrollController` |
| Подписанное поле | [IosFormTextField](../../../lib/shared/widgets/ios_form_text_field.dart): для отдельной подписи `inlineLabel: false` |
| Форма с открытой клавиатурой | [FormSheet / showFormSheet](../../../lib/shared/widgets/form_sheet.dart): `viewInsets`, ограничение высоты и прокрутка |
| Готовая панель настройки нескольких полей | [SpendLimitsSettings](../../../lib/features/stats/widgets/spend_limits_settings.dart), добавлена в [PR #98](https://github.com/mishaqp/Moru/pull/98) |
| Карточка подтверждения с приватными полями | [McpManagementApproval](../../../lib/features/chat/widgets/mcp_management_approval.dart), [PR #99](https://github.com/mishaqp/Moru/pull/99) |

Передавай полученный `ScrollController` содержимому панели: `SpendLimitsSettings` уже соединяет `showCustomBottomSheet`, `ListView`, `SectionCard` и `IosFormTextField`. Это ориентир композиции, а не причина копировать связанную логику расходов.

Иконки бери из `lucide_icons_flutter`; для старых имён в соседнем коде есть [lucide_adapter.dart](../../../lib/icons/lucide_adapter.dart). Новые `Icons.*` из Material не добавляй. Для движения используй существующие [общие анимации](../../../lib/shared/animations/) и зависимости `flutter_animate` / `animations`.

## Тема и раскладка

- Используй `Theme.of(context).colorScheme` и [семантические цвета](../../../lib/theme/app_semantic_colors.dart) (`context.appColors`, `context.overlaySurface`); сохрани читаемость в светлой/тёмной теме и режиме «Стекло». Для стеклянного фона чата см. [ChatFrostedBackdrop](../../../lib/features/chat/widgets/frosted/chat_frosted_backdrop.dart).
- Сохраняй [HomeDesktopScaffold](../../../lib/features/home/pages/home_desktop_layout.dart), [AppBreakpoints.tablet](../../../lib/shared/responsive/breakpoints.dart) и существующие ветки `isWide`: они обслуживают Android-планшеты, складные устройства и ландшафт. Не создавай desktop-реализацию.
- Учитывай `MediaQuery.textScalerOf(context)` и масштаб 1.3: подпись, значение, ошибка и действия должны оставаться читаемыми. Не ограничивай системный масштаб ради фиксированной высоты.
- При клавиатуре сохраняй доступ к полю и кнопкам, ограничивай высоту панели, учитывай `MediaQuery.viewInsetsOf(context).bottom` и прокрутку. Перед добавлением отступа проверь, учитывает ли его уже общий компонент.
- Освобождай созданные контроллеры, слушатели и таймеры. В карточках подтверждения сохраняй обработку отмены/сохранения и приватный путь ввода из `McpManagementApproval`; значения секретов не должны попадать в аргументы модели, историю или журнал.

Для изменения браузера дополнительно прочитай только пункты Browser and Computer в [Chat features that already exist — do not reimplement](../../../AGENTS.md#chat-features-that-already-exist--do-not-reimplement): сохраняй живой WebView и его ancestry, подтверждения и существующие действия.

## Проверка результата

Проверь затронутый экран на узком Android-телефоне, планшете и в ландшафте, с обычным текстом и масштабом 1.3, с клавиатурой и без неё, в светлой/тёмной теме и «Стекле». Сверь доступность действий, переполнение, прокрутку и focus, а не только один скриншот.

Выбирай проверки по изменению и разрешённому объёму. Для существующих форм/подтверждений начни с [spend_control_widgets_test.dart](../../../test/features/home/widgets/spend_control_widgets_test.dart) и [mcp_management_approval_test.dart](../../../test/features/chat/widgets/mcp_management_approval_test.dart); требования к Dart-проверкам находятся в [Pre-commit checklist](../../../AGENTS.md#pre-commit-checklist). Не выдавай чтение теста или проверку раскладки без устройства за проведённый Android-прогон.

В итоге назови изменённый экран, переиспользованный компонент, выполненные проверки и то, что осталось проверить на устройстве. Новые пользовательские строки проведи через существующую локализацию из [Architecture](../../../AGENTS.md#architecture).

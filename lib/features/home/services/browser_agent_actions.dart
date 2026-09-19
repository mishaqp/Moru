/// Canonical list of `browser_use` actions, shared by the tool dispatcher
/// and the Browser settings page so the two can never drift apart.
class BrowserAgentAction {
  const BrowserAgentAction({
    required this.id,
    required this.requiresApproval,
    required this.labelRu,
    required this.labelEn,
    required this.descriptionRu,
    required this.descriptionEn,
  });

  final String id;

  /// Matches [LocalToolNames.requiresApprovalFor]'s per-action list: whether
  /// this action is gated by an approval prompt when full tool trust is off.
  final bool requiresApproval;
  final String labelRu;
  final String labelEn;
  final String descriptionRu;
  final String descriptionEn;
}

class BrowserAgentActions {
  const BrowserAgentActions._();

  static const List<BrowserAgentAction> all = [
    BrowserAgentAction(
      id: 'open',
      requiresApproval: false,
      labelRu: 'Открыть URL',
      labelEn: 'Open URL',
      descriptionRu: 'Переход по http/https-ссылке.',
      descriptionEn: 'Navigate to an http/https URL.',
    ),
    BrowserAgentAction(
      id: 'observe',
      requiresApproval: false,
      labelRu: 'Осмотреть страницу',
      labelEn: 'Observe page',
      descriptionRu: 'Список видимых элементов и текста.',
      descriptionEn: 'List visible elements and text.',
    ),
    BrowserAgentAction(
      id: 'read',
      requiresApproval: false,
      labelRu: 'Прочитать текст',
      labelEn: 'Read text',
      descriptionRu: 'Извлечение полного читаемого текста страницы.',
      descriptionEn: 'Extract the full readable page text.',
    ),
    BrowserAgentAction(
      id: 'wait_for',
      requiresApproval: false,
      labelRu: 'Ожидать элемент',
      labelEn: 'Wait for element',
      descriptionRu: 'Пауза до появления/исчезновения CSS-селектора.',
      descriptionEn: 'Pause until a CSS selector reaches a state.',
    ),
    BrowserAgentAction(
      id: 'back',
      requiresApproval: false,
      labelRu: 'Назад',
      labelEn: 'Back',
      descriptionRu: 'Переход назад в истории браузера.',
      descriptionEn: 'Go back in browser history.',
    ),
    BrowserAgentAction(
      id: 'forward',
      requiresApproval: false,
      labelRu: 'Вперёд',
      labelEn: 'Forward',
      descriptionRu: 'Переход вперёд в истории браузера.',
      descriptionEn: 'Go forward in browser history.',
    ),
    BrowserAgentAction(
      id: 'reload',
      requiresApproval: false,
      labelRu: 'Обновить страницу',
      labelEn: 'Reload',
      descriptionRu: 'Перезагрузка текущей страницы.',
      descriptionEn: 'Reload the current page.',
    ),
    BrowserAgentAction(
      id: 'scroll',
      requiresApproval: false,
      labelRu: 'Прокрутить',
      labelEn: 'Scroll',
      descriptionRu: 'Прокрутка страницы вверх/вниз.',
      descriptionEn: 'Scroll the page up or down.',
    ),
    BrowserAgentAction(
      id: 'close',
      requiresApproval: false,
      labelRu: 'Закрыть браузер',
      labelEn: 'Close browser',
      descriptionRu: 'Закрытие окна общего браузера.',
      descriptionEn: 'Close the shared browser window.',
    ),
    BrowserAgentAction(
      id: 'click',
      requiresApproval: true,
      labelRu: 'Нажать',
      labelEn: 'Click',
      descriptionRu: 'Нажатие на элемент.',
      descriptionEn: 'Click an element.',
    ),
    BrowserAgentAction(
      id: 'type',
      requiresApproval: true,
      labelRu: 'Ввести текст',
      labelEn: 'Type',
      descriptionRu: 'Ввод текста в поле, включая выпадающие списки.',
      descriptionEn: 'Type into a field, including dropdowns.',
    ),
    BrowserAgentAction(
      id: 'submit',
      requiresApproval: true,
      labelRu: 'Отправить форму',
      labelEn: 'Submit',
      descriptionRu: 'Отправка формы.',
      descriptionEn: 'Submit a form.',
    ),
    BrowserAgentAction(
      id: 'press_key',
      requiresApproval: true,
      labelRu: 'Нажать клавишу',
      labelEn: 'Press key',
      descriptionRu: 'Синтез события клавиатуры (например, Enter).',
      descriptionEn: 'Synthesize a keyboard event (e.g. Enter).',
    ),
    BrowserAgentAction(
      id: 'eval_js',
      requiresApproval: true,
      labelRu: 'Выполнить JavaScript',
      labelEn: 'Run JavaScript',
      descriptionRu: 'Выполнение произвольного JS на странице.',
      descriptionEn: 'Run arbitrary JavaScript on the page.',
    ),
  ];

  static bool isKnown(String id) => all.any((a) => a.id == id);
}

import '../../../core/services/browser/browser_agent_session.dart';

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
      labelRu: 'Дождаться элемента на странице',
      labelEn: 'Wait for something to appear on the page',
      descriptionRu: 'Пауза, пока часть страницы не появится или не исчезнет.',
      descriptionEn: 'Pause until part of the page appears or disappears.',
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
      id: 'done',
      requiresApproval: false,
      labelRu: 'Готово',
      labelEn: 'Done',
      descriptionRu: 'Сигнал, что задача в браузере выполнена.',
      descriptionEn: 'Signal that the browser task is complete.',
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
      labelRu: 'Выполнить код на странице',
      labelEn: 'Run code on the page',
      descriptionRu:
          'Может прочитать или изменить что угодно на открытой странице.',
      descriptionEn: 'Can read or change anything on the currently open page.',
    ),
  ];

  static bool isKnown(String id) => all.any((a) => a.id == id);

  static BrowserAgentAction? byId(String id) {
    for (final action in all) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// A short, localized status line for [activity] (the browser page's status
/// bar and "Show recent" log). Falls back to the raw action id if it somehow
/// doesn't match a known action, rather than showing nothing. Success and
/// the still-[BrowserActivityOutcome.running] state read the same — only a
/// [BrowserActivityOutcome.failed] call gets a visible marker, matching how
/// rikkahub-agent's own action trail only annotates failures.
String browserActivityLabel(BrowserActivity activity, {required bool ru}) {
  final action = BrowserAgentActions.byId(activity.action);
  final label = action == null
      ? activity.action
      : (ru ? action.labelRu : action.labelEn);
  final detail = activity.detail;
  final base = (detail == null || detail.isEmpty) ? label : '$label: $detail';
  switch (activity.outcome) {
    case BrowserActivityOutcome.failed:
      return ru ? '$base — не удалось' : '$base — failed';
    case BrowserActivityOutcome.notFound:
      return ru ? '$base — не найдено' : '$base — not found';
    case BrowserActivityOutcome.running:
    case BrowserActivityOutcome.ok:
      return base;
  }
}

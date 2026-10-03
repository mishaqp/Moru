import 'dart:convert';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../shared/pages/webview/browser_mini_window.dart';
import '../models/computer_step.dart';

/// Both Computer surfaces expand the same browser and retain its controller.
Future<void> openComputerStepBrowser(
  ComputerStep step, {
  String? conversationId,
}) async {
  final session = BrowserAgentSession.instance;
  Map result = const {};
  try {
    final decoded = jsonDecode(step.result);
    if (decoded is Map) result = decoded;
  } on FormatException {
    // An unfinished step may not have a result yet.
  }
  final target = computerActionUri(
    (result['url'] ?? step.arguments['url'])?.toString(),
  );
  if (session.isAttached) {
    if (session.ownerConversationId == null ||
        session.ownerConversationId == conversationId) {
      final tabId = result['tab_id'] ?? step.arguments['tab_id'];
      final tab = session.tabs.value
          .where(
            (tab) =>
                (tabId != null && tab.id == tabId.toString()) ||
                (target != null && computerActionUri(tab.url) == target),
          )
          .firstOrNull;
      if (tab != null && !tab.active && computerActionUri(tab.url) != null) {
        await session.switchTab(tab.id);
      }
    }
    await openSharedBrowser();
  } else if (target != null) {
    await openSharedBrowser(startUrl: target.toString());
  } else {
    await openSharedBrowser();
  }
}

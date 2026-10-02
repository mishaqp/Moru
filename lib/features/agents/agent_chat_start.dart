import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/models/assistant.dart';
import '../../core/models/agent_auth_mode.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/services/acp/acp_agent_catalog.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/notification_service.dart';

/// The assistant that talks through [spec], created on first use.
Future<Assistant> assistantForAgent(
  AssistantProvider assistants,
  AcpAgentSpec spec, {
  AgentAuthMode? authMode,
}) async {
  await assistants.loaded;
  for (final assistant in assistants.assistants) {
    if (assistant.agentId != spec.id) continue;
    if (authMode == null || assistant.agentAuthMode == authMode) {
      return assistant;
    }
    final updated = assistant.copyWith(agentAuthMode: authMode);
    await assistants.updateAssistant(updated);
    return updated;
  }
  final id = await assistants.addAssistant(name: spec.name);
  final assistant = assistants
      .getById(id)!
      .copyWith(agentId: spec.id, agentAuthMode: authMode);
  await assistants.updateAssistant(assistant);
  return assistant;
}

/// Opens a new chat with [spec]: its assistant becomes current and the app
/// goes back to the chat screen.
Future<void> startAgentChat(BuildContext context, AcpAgentSpec spec) async {
  final assistants = context.read<AssistantProvider>();
  final chats = context.read<ChatService>();
  final navigator = Navigator.of(context);
  final assistant = await assistantForAgent(assistants, spec);
  await assistants.setCurrentAssistant(assistant.id);
  final conversation = await chats.createConversation(
    title: spec.name,
    assistantId: assistant.id,
  );
  navigator.popUntil((route) => route.isFirst);
  NotificationService.openConversation(conversation.id);
}

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/models/assistant.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/services/acp/acp_agent_catalog.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/notification_service.dart';

/// The assistant that talks through [spec], created on first use.
Future<Assistant> assistantForAgent(
  AssistantProvider assistants,
  AcpAgentSpec spec,
) async {
  await assistants.loaded;
  for (final assistant in assistants.assistants) {
    if (assistant.agentId == spec.id) return assistant;
  }
  final id = await assistants.addAssistant(name: spec.name);
  final assistant = assistants.getById(id)!.copyWith(agentId: spec.id);
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

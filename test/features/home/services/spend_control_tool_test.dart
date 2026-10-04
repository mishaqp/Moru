import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_helpers.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/spend_control_tool.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';
import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsProvider settings;
  late ToolApprovalService approvals;
  var compactions = 0;
  var allowed = true;
  setUp(() async {
    final harness = await createBusinessTestHarness();
    settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    approvals = ToolApprovalService();
    compactions = 0;
    allowed = true;
    addTearDown(settings.dispose);
    addTearDown(approvals.dispose);
  });
  SpendControlTool tool({bool withApprovals = true}) => SpendControlTool(
    settings: settings,
    approvals: withApprovals ? approvals : null,
    checkAllowed: () {
      if (!allowed) throw StateError('permission_denied');
    },
    readStatus: () async => SpendControlStatus(
      chat: const ChatTokenSummary(
        input: 50,
        output: 10,
        cached: 20,
        replies: 1,
      ),
      today: const ChatTokenSummary(
        input: 50,
        output: 10,
        cached: 20,
        replies: 1,
      ),
      limits: settings.spendLimits,
      day: DateTime(2026, 10, 4),
    ),
    compact: () async {
      compactions++;
      return {'ok': true, 'conversation_id': 'compacted'};
    },
  );
  Map<String, dynamic> decode(String value) =>
      jsonDecode(value) as Map<String, dynamic>;

  test('tool is opt-in and status never asks for approval', () async {
    expect(
      LocalToolsService.isEnabledForAssistant(
        LocalToolNames.spendControl,
        Assistant(id: 'default', name: 'Default'),
      ),
      isFalse,
    );
    expect(
      LocalToolNames.requiresApprovalFor(LocalToolNames.spendControl, {
        'action': 'status',
      }),
      isFalse,
    );
    final result = decode(
      await tool().execute(
        {'action': 'status'},
        toolCallId: 'status',
        conversationId: 'c',
      ),
    );
    expect(result['chat']['cached_tokens'], 20);
    expect(approvals.pendingRequests, isEmpty);
  });
  for (final action in ['compact', 'set_limits']) {
    final args = {
      'action': action,
      if (action == 'set_limits') 'limits': {'chat_tokens': 100},
    };
    test(
      '$action waits for fresh confirmation and denial has no effect',
      () async {
        expect(
          LocalToolNames.requiresApprovalFor(LocalToolNames.spendControl, args),
          isTrue,
        );
        for (var i = 0; i < 2; i++) {
          final pending = tool().execute(
            args,
            toolCallId: 'change',
            conversationId: 'c',
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            approvals.pendingRequests.single.requiresExplicitConsent,
            isTrue,
          );
          expect(compactions, 0);
          expect(settings.spendLimits.enabled, isFalse);
          approvals.deny('change', conversationId: 'c');
          expect(decode(await pending)['error'], 'approval_denied');
        }
      },
    );
    test(
      '$action executes after confirmation and full trust skips it',
      () async {
        final pending = tool().execute(
          args,
          toolCallId: 'change',
          conversationId: 'c',
        );
        await Future<void>.delayed(Duration.zero);
        approvals.approve('change', conversationId: 'c');
        expect(decode(await pending)['ok'], isTrue);
        await settings.setToolAutoApproveAll(true);
        expect(
          decode(
            await tool().execute(
              args,
              toolCallId: 'trusted',
              conversationId: 'c',
            ),
          )['ok'],
          isTrue,
        );
        expect(approvals.pendingRequests, isEmpty);
        expect(
          action == 'compact'
              ? compactions == 2
              : settings.spendLimits.chatTokens == 100,
          isTrue,
        );
      },
    );
    test(
      '$action fails closed when consent is unavailable or permission changes',
      () async {
        expect(
          decode(
            await tool(
              withApprovals: false,
            ).execute(args, toolCallId: 'absent', conversationId: 'c'),
          )['error'],
          'approval_unavailable',
        );
        final pending = tool().execute(
          args,
          toolCallId: 'change',
          conversationId: 'c',
        );
        await Future<void>.delayed(Duration.zero);
        allowed = false;
        approvals.approve('change', conversationId: 'c');
        expect(decode(await pending)['error'], 'permission_denied');
        expect(compactions, 0);
        expect(settings.spendLimits.enabled, isFalse);
      },
    );
  }
  test('set_limits validates atomically and preserves other budgets', () async {
    await settings.setToolAutoApproveAll(true);
    await settings.setSpendLimits(const SpendLimits(dailyUsd: 5));
    final invalid = decode(
      await tool().execute(
        {
          'action': 'set_limits',
          'limits': {'chat_tokens': 100, 'daily_usd': -1},
        },
        toolCallId: 'bad',
        conversationId: 'c',
      ),
    );
    expect(invalid['error'], 'invalid_arguments');
    expect(settings.spendLimits.chatTokens, isNull);
    expect(settings.spendLimits.dailyUsd, 5);
    await tool().execute(
      {
        'action': 'set_limits',
        'limits': {'chat_tokens': 100},
      },
      toolCallId: 'ok',
      conversationId: 'c',
    );
    expect(settings.spendLimits.dailyUsd, 5);
    expect(settings.spendLimits.chatTokens, 100);
  });

  test('schema uses Gemini-compatible numeric types and clearable budgets', () {
    final schema = cleanSchemaForGemini(
      SpendControlTool.definition['function']['parameters']
          as Map<String, dynamic>,
      stringEnumOnly: true,
    );
    final properties = schema['properties'] as Map;
    final limits = (properties['limits'] as Map)['properties'] as Map;
    for (final key in ['chat_usd', 'daily_usd']) {
      expect((limits[key] as Map)['type'], 'number');
    }
    for (final key in ['chat_tokens', 'daily_tokens']) {
      expect((limits[key] as Map)['type'], 'integer');
    }
    expect((properties['clear'] as Map)['items']['enum'], [
      'chat_usd',
      'chat_tokens',
      'daily_usd',
      'daily_tokens',
    ]);
  });

  test(
    'clear removes only approved budgets and rejects conflicting edits',
    () async {
      await settings.setSpendLimits(
        const SpendLimits(chatUsd: 0.5, dailyTokens: 1000),
      );
      final pending = tool().execute(
        {
          'action': 'set_limits',
          'clear': ['chat_usd'],
        },
        toolCallId: 'clear',
        conversationId: 'c',
      );
      await Future<void>.delayed(Duration.zero);
      expect(settings.spendLimits.chatUsd, 0.5);
      expect(approvals.pendingRequests.single.requiresExplicitConsent, isTrue);
      approvals.approve('clear', conversationId: 'c');
      final cleared = decode(await pending);
      expect(cleared['ok'], isTrue);
      expect(settings.spendLimits.chatUsd, isNull);
      expect(settings.spendLimits.dailyTokens, 1000);
      for (final args in [
        {
          'action': 'set_limits',
          'clear': ['hard_stop'],
        },
        {
          'action': 'set_limits',
          'limits': {'daily_tokens': 2000},
          'clear': ['daily_tokens'],
        },
      ]) {
        expect(
          decode(
            await tool().execute(args, toolCallId: 'bad', conversationId: 'c'),
          )['error'],
          'invalid_arguments',
        );
        expect(settings.spendLimits.dailyTokens, 1000);
      }
    },
  );
}

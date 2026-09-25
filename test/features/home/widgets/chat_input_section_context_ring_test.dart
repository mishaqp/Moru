import 'dart:async';

import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/providers/asr_provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/quick_phrase_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/features/home/widgets/chat_input_section.dart';
import 'package:Kelivo/features/home/widgets/context_usage_ring.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BusinessPreferences preferences;

  setUp(() {
    preferences = createBusinessTestPreferences();
  });

  Future<SettingsProvider> pumpComposer(
    WidgetTester tester, {
    required int? contextTokensUsed,
  }) async {
    final settings = SettingsProvider(preferences);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => AssistantProvider(preferences: preferences),
          ),
          ChangeNotifierProvider(create: (_) => AsrProvider()),
          ChangeNotifierProvider(
            create: (_) => McpProvider(preferences: preferences),
          ),
          ChangeNotifierProvider(
            create: (_) => QuickPhraseProvider(preferences: preferences),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatInputSection(
              inputBarKey: GlobalKey(),
              chatModelProviderKey: 'SomeProvider',
              chatModelId: 'claude-sonnet-4-5',
              chatModelIsConversationOverride: true,
              inputFocus: FocusNode(),
              inputController: TextEditingController(),
              mediaController: ChatInputBarController(),
              isTablet: false,
              isLoading: false,
              isToolModel: (_, _) => true,
              isReasoningModel: (_, _) => false,
              isReasoningEnabled: (_) => false,
              contextTokensUsed: contextTokensUsed,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('the ring shows the fill against the model window', (
    tester,
  ) async {
    await pumpComposer(tester, contextTokensUsed: 50000);
    final ring = tester.widget<ContextUsageRing>(find.byType(ContextUsageRing));
    expect(ring.usedTokens, 50000);
    expect(ring.windowTokens, 200000);
  });

  testWidgets('no ring before the first reply', (tester) async {
    await pumpComposer(tester, contextTokensUsed: null);
    expect(find.byType(ContextUsageRing), findsNothing);
  });

  testWidgets('token stats turned off hide the ring', (tester) async {
    final settings = await pumpComposer(tester, contextTokensUsed: 50000);
    // The flag flips and notifies synchronously; the write finishes later.
    unawaited(settings.setShowTokenStats(false));
    await tester.pump();
    expect(find.byType(ContextUsageRing), findsNothing);
  });
}

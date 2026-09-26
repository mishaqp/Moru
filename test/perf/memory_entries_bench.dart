import '../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/memory_entry.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/memory_provider.dart';
import 'package:Kelivo/core/providers/memory_provider_v2.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/memory/memory_repository.dart';
import 'package:Kelivo/features/settings/pages/memory_entries_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

// Explicit benchmark; timings are observations, not regression assertions.
void main() {
  testWidgets('memory entries: open and rebuild with 500 entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    late MemoryProviderV2 memory;
    late AssistantProvider assistants;
    late SettingsProvider settings;
    late MemoryProvider legacy;
    await tester.runAsync(() async {
      final harness = await createBusinessTestHarness();
      final chat = ChatDatabaseRepository(harness.database);
      await chat.ensureReady();
      final repo = MemoryRepository(harness.preferences);
      for (var i = 0; i < 500; i++) {
        await repo.create(
          scope: MemoryScope.global,
          type: MemoryType.values[i % MemoryType.values.length],
          content: 'Memory number $i about something the user said once',
          source: MemorySource.manual,
        );
      }
      memory = MemoryProviderV2(repository: repo, chatRepository: chat);
      await memory.refresh();
      assistants = AssistantProvider(preferences: harness.preferences);
      await assistants.loaded;
      settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      legacy = MemoryProvider(preferences: harness.preferences);
    });
    final open = Stopwatch()..start();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: assistants),
          ChangeNotifierProvider.value(value: memory),
          ChangeNotifierProvider.value(value: legacy),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MemoryEntriesPage(),
        ),
      ),
    );
    open.stop();
    var cards = 0;
    void visit(Element e) {
      if (e.widget.runtimeType.toString() == 'MemoryEntryCard') cards++;
      e.visitChildren(visit);
    }

    tester.binding.rootElement!.visitChildren(visit);
    final samples = <int>[];
    for (var i = 0; i < 30; i++) {
      // A write elsewhere, e.g. the memory pipeline after a reply.
      memory.notifyListeners();
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      if (i >= 5) samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'MEMORY_ENTRIES entries=${memory.entries.length} cardsBuilt=$cards '
      'openUs=${open.elapsedMicroseconds} '
      'rebuildMedianUs=${samples[samples.length ~/ 2]}',
    );
  });
}

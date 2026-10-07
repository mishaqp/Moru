import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/memory/memory_tools.dart';
import 'package:Kelivo/core/services/search/search_tool_service.dart';
import 'package:Kelivo/core/services/memory/memory_prompts.dart';
import 'package:Kelivo/core/services/tools/built_in_tool_catalog.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/features/home/services/built_in_tool_names.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  test('BuiltInToolNames.all reserves search, memory, and local names', () {
    expect(
      BuiltInToolNames.all,
      containsAll(<String>[
        SearchToolService.toolName,
        'builtin_search',
        ...MemoryTools.allToolNames,
        ...MemoryTools.legacyToolNames,
        ...LocalToolNames.all,
      ]),
    );
    expect(SearchToolService.toolName, 'search_web');
    expect(
      BuiltInToolNames.all,
      containsAll(const ['create_memory', 'edit_memory', 'delete_memory']),
    );
    expect(LocalToolNames.all.toSet().length, LocalToolNames.all.length);
    expect(
      LocalToolsService.definitions.keys.toSet(),
      LocalToolNames.all.toSet(),
    );
    for (final entry in LocalToolsService.definitions.entries) {
      expect(entry.value['function']['name'], entry.key);
    }
    final catalogNames = <String>{};
    for (final legacy in [false, true]) {
      final entries = BuiltInToolCatalog.entries(
        lang: MemoryPromptLang.en,
        legacyMemoryMode: legacy,
      );
      final names = entries.map((entry) => entry.name).toList();
      expect(
        names.toSet().length,
        names.length,
        reason: 'No built-in collisions',
      );
      catalogNames.addAll(names);
    }
    expect(BuiltInToolNames.all, {
      ...catalogNames,
      ...LocalToolNames.all,
      ...WorkspaceToolsService.toolNames,
      'builtin_search',
    });
  });
}

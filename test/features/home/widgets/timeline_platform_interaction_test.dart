import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  const platforms = <TargetPlatform>[TargetPlatform.android];

  for (final platform in platforms) {
    testWidgets('$platform uses its timeline input surface contract', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final listController = ListController();
      addTearDown(listController.dispose);
      final processing = ValueNotifier<String?>(null);
      addTearDown(processing.dispose);
      var userScrollIntentCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageListView(
              scrollController: scrollController,
              listController: listController,
              messages: const [],
              byGroup: const {},
              versionSelections: const {},
              reasoning: const {},
              reasoningSegments: const {},
              contentSplits: const {},
              toolParts: const {},
              translations: const {},
              selecting: false,
              selectedItems: const {},
              dividerPadding: EdgeInsets.zero,
              processingFilesMessageId: processing,
              onUserScrollIntent: () => userScrollIntentCount++,
            ),
          ),
        ),
      );

      final list = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(
        list.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(find.byType(Scrollbar), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });
  }
}

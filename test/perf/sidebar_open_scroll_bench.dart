import 'dart:io';

import '../support/business_test_harness.dart';

import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tag_provider.dart';
import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/widgets/side_drawer.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

/// Explicit debug widget benchmark: real SideDrawer build/layout/paint, without
/// Android raster, database hydration or image decoding. The service supplies
/// already-loaded summaries, as it does when the user opens the drawer.
/// Run explicitly: flutter test test/perf/sidebar_open_scroll_bench.dart
void main() {
  final binding = _FrameBinding();

  for (final count in const [200, 1000]) {
    for (final tablet in const [false, true]) {
      for (final glass in const [false, true]) {
        testWidgets('sidebar count=$count tablet=$tablet glass=$glass', (
          tester,
        ) async {
          final directory = Directory.systemTemp.createTempSync(
            'sidebar-bench-',
          );
          final previousPaths = PathProviderPlatform.instance;
          PathProviderPlatform.instance = _BenchPaths(directory.path);
          tester.view.physicalSize = tablet
              ? const Size(2400, 1800)
              : const Size(1170, 2532);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          addTearDown(() {
            PathProviderPlatform.instance = previousPaths;
            directory.deleteSync(recursive: true);
          });

          late final SettingsProvider settings;
          late final AssistantProvider assistants;
          late final BackupReminderProvider backup;
          late final TagProvider tags;
          late final UserProvider user;
          late final UpdateProvider update;
          await tester.runAsync(() async {
            // Native SQLite work and its write queue must start in the real
            // async zone; otherwise Glass's writes can wait on the fake clock.
            final preferences = createBusinessTestPreferences();
            settings = SettingsProvider(preferences);
            assistants = AssistantProvider(preferences: preferences);
            backup = BackupReminderProvider(
              preferences: preferences,
              autoLoad: false,
            );
            tags = TagProvider(preferences: preferences);
            user = UserProvider(preferences: preferences);
            update = UpdateProvider();
            await settings.loaded;
            await assistants.loaded;
            await backup.load(startTimer: false);
            if (glass) await settings.setGlassTheme(true);
          });

          final openUi = <int>[];
          final openBuild = <int>[];
          var openWidgetBuilds = 0;
          var openListBuilds = 0;
          var openRowsComputes = 0;
          var openListReads = 0;
          var openConversationReads = 0;
          var openThumbnailReads = 0;
          _SummaryChatService? service;

          Widget root(_SummaryChatService chat, {bool opened = true}) =>
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ChatService>.value(value: chat),
                  ChangeNotifierProvider.value(value: settings),
                  ChangeNotifierProvider.value(value: assistants),
                  ChangeNotifierProvider.value(value: backup),
                  ChangeNotifierProvider.value(value: tags),
                  ChangeNotifierProvider.value(value: user),
                  ChangeNotifierProvider.value(value: update),
                ],
                child: MaterialApp(
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.centerLeft,
                      child: opened
                          ? SideDrawer(
                              userName: 'User',
                              assistantName: 'Assistant',
                              embedded: tablet,
                              embeddedWidth: 300,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              );

          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          try {
            // Prime framework/font work with a disposable drawer. Every timed
            // opening gets fresh Conversation and service objects and a new
            // SideDrawer state, so its row memo cannot survive the last opening.
            for (var opening = 0; opening < 11; opening++) {
              final previousService = service;
              service = _SummaryChatService(count);
              // Keep the app/localizations mounted, as they are when opening
              // the sidebar from chat, while discarding the old drawer state.
              await tester.pumpWidget(root(service, opened: false));
              previousService?.dispose();
              final listBefore = SideDrawer.debugConversationListBuildCount;
              final rowsBefore = SideDrawer.debugSidebarRowsComputeCount;
              var builds = 0;
              debugOnRebuildDirtyWidget = (_, _) => builds++;
              binding.lastBuildUs = 0;
              final watch = Stopwatch()..start();
              await tester.pumpWidget(root(service));
              watch.stop();
              debugOnRebuildDirtyWidget = null;
              if (opening > 0) {
                openUi.add(watch.elapsedMicroseconds);
                openBuild.add(binding.lastBuildUs);
                openWidgetBuilds += builds;
                openListBuilds +=
                    SideDrawer.debugConversationListBuildCount - listBefore;
                openRowsComputes +=
                    SideDrawer.debugSidebarRowsComputeCount - rowsBefore;
                openListReads += service.listReads;
                openConversationReads += service.conversationReads;
                openThumbnailReads += service.thumbnailReads;
              }
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pump();
            }

            final chat = service!;
            final position = _conversationPosition(tester);
            final elements = _countElements(tester);
            final tiles = find
                .byType(SideDrawer.debugChatTileType)
                .evaluate()
                .length;

            // Warm both directions, settling entry animations before measuring
            // ordinary incremental scrolling through the real virtualized list.
            for (var i = 0; i <= 20; i++) {
              position.jumpTo(position.maxScrollExtent * i / 20);
              await tester.pump(const Duration(milliseconds: 500));
            }
            position.jumpTo(0);
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump();
            chat.resetReads();
            final listBefore = SideDrawer.debugConversationListBuildCount;
            final rowsBefore = SideDrawer.debugSidebarRowsComputeCount;
            var scrollWidgetBuilds = 0;
            debugOnRebuildDirtyWidget = (_, _) => scrollWidgetBuilds++;
            final scrollUi = <int>[];
            final scrollBuild = <int>[];
            var maxTiles = tiles;
            for (var frame = 0; frame < 80; frame++) {
              binding.lastBuildUs = 0;
              final watch = Stopwatch()..start();
              final target = position.pixels + 120;
              position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
              await tester.pump(const Duration(milliseconds: 16));
              watch.stop();
              scrollUi.add(watch.elapsedMicroseconds);
              scrollBuild.add(binding.lastBuildUs);
              final live = find
                  .byType(SideDrawer.debugChatTileType)
                  .evaluate()
                  .length;
              if (live > maxTiles) maxTiles = live;
            }
            debugOnRebuildDirtyWidget = null;

            // ignore: avoid_print
            print(
              'SIDEBAR_RESULT count=$count layout=${tablet ? 'tablet' : 'phone'} '
              'glass=$glass size=${tablet ? '800x600' : '390x844'} '
              'openSamples=${openUi.length} ${_stats('openUi', openUi)} '
              '${_stats('openBuild', openBuild)} '
              'openWidgetBuilds=$openWidgetBuilds openListBuilds=$openListBuilds '
              'openRowsComputes=$openRowsComputes openListReads=$openListReads '
              'openConversationReads=$openConversationReads openThumbnailReads=$openThumbnailReads '
              'elements=$elements tiles=$tiles maxTiles=$maxTiles '
              'scrollSamples=${scrollUi.length} ${_stats('scrollUi', scrollUi)} '
              '${_stats('scrollBuild', scrollBuild)} '
              'scrollWidgetBuilds=$scrollWidgetBuilds '
              'scrollListBuilds=${SideDrawer.debugConversationListBuildCount - listBefore} '
              'scrollRowsComputes=${SideDrawer.debugSidebarRowsComputeCount - rowsBefore} '
              'scrollListReads=${chat.listReads} '
              'scrollConversationReads=${chat.conversationReads} '
              'scrollThumbnailReads=${chat.thumbnailReads}',
            );
          } finally {
            debugOnRebuildDirtyWidget = null;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 500));
            service?.dispose();
            settings.dispose();
            assistants.dispose();
            backup.dispose();
            tags.dispose();
            user.dispose();
            update.dispose();
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}

String _stats(String prefix, List<int> values) {
  final sorted = List<int>.of(values)..sort();
  String ms(int value) => (value / 1000).toStringAsFixed(2);
  return '${prefix}P90Ms=${ms(sorted[(sorted.length * .9).ceil() - 1])} '
      '${prefix}MaxMs=${ms(sorted.last)}';
}

ScrollPosition _conversationPosition(WidgetTester tester) {
  final scrollables = find.descendant(
    of: find.byType(SideDrawer),
    matching: find.byType(Scrollable),
  );
  return tester
      .stateList<ScrollableState>(scrollables)
      .map((state) => state.position)
      .reduce((a, b) => a.maxScrollExtent > b.maxScrollExtent ? a : b);
}

int _countElements(WidgetTester tester) {
  var count = 0;
  void visit(Element element) {
    count++;
    element.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return count;
}

class _FrameBinding extends AutomatedTestWidgetsFlutterBinding {
  int lastBuildUs = 0;

  @override
  void drawFrame() {
    final watch = Stopwatch()..start();
    try {
      super.drawFrame();
    } finally {
      lastBuildUs = watch.elapsedMicroseconds;
    }
  }
}

class _SummaryChatService extends ChatService {
  _SummaryChatService(int count) {
    final date = DateTime.now();
    // Anchor at local noon so hourly run times do not change date sections or
    // the visible rows; production grouping still uses today's date boundaries.
    final now = DateTime(date.year, date.month, date.day, 12);
    conversations = [
      for (var i = 0; i < count; i++)
        Conversation(
          id: 'bench-$i',
          title: 'Conversation $i: a saved sidebar topic',
          createdAt: now.subtract(Duration(hours: i)),
          updatedAt: now.subtract(Duration(hours: i)),
          isPinned: i < 4,
        ),
    ];
    byId = {
      for (final conversation in conversations) conversation.id: conversation,
    };
  }

  late final List<Conversation> conversations;
  late final Map<String, Conversation> byId;
  int listReads = 0;
  int conversationReads = 0;
  int thumbnailReads = 0;

  void resetReads() {
    listReads = 0;
    conversationReads = 0;
    thumbnailReads = 0;
  }

  @override
  bool get initialized => true;

  @override
  int get conversationListRevision => 1;

  @override
  List<Conversation> getAllConversations() {
    listReads++;
    return List<Conversation>.of(conversations);
  }

  @override
  Conversation? getConversation(String id) {
    conversationReads++;
    return byId[id];
  }

  @override
  Future<List<String>> recentImageUris(String conversationId, {int limit = 3}) {
    thumbnailReads++;
    return Future.value(const <String>[]);
  }
}

class _BenchPaths extends PathProviderPlatform {
  _BenchPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';
  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

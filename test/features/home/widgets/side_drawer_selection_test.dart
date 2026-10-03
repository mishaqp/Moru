import 'dart:async';
import 'dart:io';

import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/tag_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/models/chat_folder.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/chat/pages/chat_archive_page.dart';
import 'package:Kelivo/features/home/widgets/chat_thumbnails.dart';
import 'package:Kelivo/features/chat/widgets/chat_gradient_background.dart';
import 'package:Kelivo/features/home/widgets/sidebar_glass.dart';
import 'package:Kelivo/features/home/widgets/side_drawer.dart';
import 'package:Kelivo/features/home/widgets/sidebar_selection_bars.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

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

class _TestChatService extends ChatService {
  final List<String> timelineCalls = <String>[];
  int notifyCount = 0;
  List<Conversation>? _stubConversations;
  int? _stubRevision;
  bool? _stubInitialized;

  void poke() => notifyListeners();

  void seedConversationsForTest(List<Conversation> conversations) {
    _stubConversations = conversations;
    _stubRevision = (_stubRevision ?? super.conversationListRevision) + 1;
    notifyListeners();
  }

  void stageConversationsBeforeInitialization(
    List<Conversation> conversations,
  ) {
    _stubConversations = conversations;
    _stubRevision = (_stubRevision ?? super.conversationListRevision) + 1;
    _stubInitialized = false;
  }

  void completeInitializationForTest() {
    _stubInitialized = true;
    notifyListeners();
  }

  @override
  bool get initialized => _stubInitialized ?? super.initialized;

  @override
  int get conversationListRevision =>
      _stubRevision ?? super.conversationListRevision;

  @override
  List<Conversation> getAllConversations() {
    if (_stubConversations != null) {
      if (_stubInitialized == false) return const <Conversation>[];
      return List<Conversation>.of(_stubConversations!);
    }
    return super.getAllConversations();
  }

  @override
  void notifyListeners() {
    notifyCount++;
    super.notifyListeners();
  }

  @override
  Future<LoadedTimelinePage?> loadTimelinePage(
    String conversationId, {
    String? beforeRevisionId,
    String? afterRevisionId,
    String? aroundRevisionId,
    bool fromStart = false,
    int limit = 40,
  }) {
    timelineCalls.add(conversationId);
    return super.loadTimelinePage(
      conversationId,
      beforeRevisionId: beforeRevisionId,
      afterRevisionId: afterRevisionId,
      aroundRevisionId: aroundRevisionId,
      fromStart: fromStart,
      limit: limit,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final services = <ChatService>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'kelivo_side_drawer_selection_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SideDrawer.debugConversationListBuildCount = 0;
    SideDrawer.debugSidebarRowsComputeCount = 0;
    SideDrawer.debugRequestConversationListHostRebuild = null;
    SideDrawer.debugEnterSelectionMode = null;
    AppSnackBarManager().dismissAll();
  });

  tearDown(() async {
    AppSnackBarManager().dismissAll();
    for (final service in services) {
      await service.close();
    }
    services.clear();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  _TestChatService createService() {
    final service = _TestChatService();
    services.add(service);
    return service;
  }

  Future<void> asAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Lets the database finish a write the UI started, pumping until
  /// [done] holds.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      // Advances the test clock too, for timers the write sets.
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpDrawer(
    WidgetTester tester,
    ChatService service, {
    bool globalSearchMode = false,
    String globalSearchQuery = '',
    Locale locale = const Locale('en'),
    ValueNotifier<Locale>? localeListenable,
    bool embedded = true,
    bool showBottomBar = false,
    FutureOr<void> Function(String id, {bool closeDrawer})?
    onSelectConversation,
    FutureOr<void> Function({bool closeDrawer})? onNewConversation,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settingsPrefs = createBusinessTestPreferences();
    final assistantPrefs = createBusinessTestPreferences();
    final backupPrefs = createBusinessTestPreferences();
    final tagPrefs = createBusinessTestPreferences();
    final userPrefs = createBusinessTestPreferences();
    final settings = SettingsProvider(settingsPrefs);
    Widget materialFor(Locale currentLocale) {
      return MaterialApp(
        locale: currentLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Draws app notifications, as the app's root does.
        builder: (context, child) => AppSnackBarOverlay(child: child!),
        home: Scaffold(
          body: SideDrawer(
            userName: 'User',
            assistantName: 'Assistant',
            embedded: embedded,
            globalSearchMode: globalSearchMode,
            globalSearchQuery: globalSearchQuery,
            showBottomBar: showBottomBar,
            onSelectConversation: onSelectConversation,
            onNewConversation: onNewConversation,
          ),
        ),
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: service),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => AssistantProvider(preferences: assistantPrefs),
          ),
          ChangeNotifierProvider(
            create: (_) => BackupReminderProvider(preferences: backupPrefs),
          ),
          ChangeNotifierProvider(
            create: (_) => TagProvider(preferences: tagPrefs),
          ),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
          ChangeNotifierProvider(
            create: (_) => UserProvider(preferences: userPrefs),
          ),
        ],
        child: localeListenable == null
            ? materialFor(locale)
            : ValueListenableBuilder<Locale>(
                valueListenable: localeListenable,
                builder: (_, currentLocale, __) => materialFor(currentLocale),
              ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'entering selection does not recompute sidebar rows or bump revision',
    (tester) async {
      await asAndroid(() async {
        final service = createService();
        late final String alphaId;
        await tester.runAsync(() async {
          await service.init();
          alphaId = (await service.createConversation(title: 'Alpha')).id;
          await service.createConversation(title: 'Beta');
        });
        await pumpDrawer(tester, service);
        expect(find.text('Alpha'), findsOneWidget);

        final computes = SideDrawer.debugSidebarRowsComputeCount;
        final revision = service.conversationListRevision;
        expect(SideDrawer.debugEnterSelectionMode, isNotNull);

        SideDrawer.debugEnterSelectionMode!(alphaId);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(SideDrawer.debugSidebarRowsComputeCount, computes);
        expect(service.conversationListRevision, revision);
        expect(find.byType(SidebarSelectionHeader), findsOneWidget);
      });
    },
  );

  testWidgets(
    'multi-select delete removes conversations with one ChatService notify',
    (tester) async {
      await asAndroid(() async {
        final service = createService();
        late final String alphaId;
        await tester.runAsync(() async {
          await service.init();
          alphaId = (await service.createConversation(title: 'Alpha')).id;
          await service.createConversation(title: 'Beta');
          await service.createConversation(title: 'Gamma');
        });
        await pumpDrawer(tester, service);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Gamma'), findsOneWidget);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SideDrawer)),
        )!;
        final notifyBaseline = service.notifyCount;

        SideDrawer.debugEnterSelectionMode!(alphaId);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(l10n.sideDrawerSelectionTitle(1)), findsOneWidget);

        await tester.tap(find.text('Beta'));
        await tester.pump();
        expect(find.text(l10n.sideDrawerSelectionTitle(2)), findsOneWidget);

        await tester.tap(find.text(l10n.sideDrawerSelectionSelectAll));
        await tester.pump();
        expect(find.text(l10n.sideDrawerSelectionTitle(3)), findsOneWidget);
        expect(find.text(l10n.sideDrawerSelectionDeselectAll), findsOneWidget);

        final notifyBeforeDelete = service.notifyCount;
        expect(notifyBeforeDelete, notifyBaseline);

        await tester.tap(find.text(l10n.sideDrawerSelectionDelete).first);
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.sideDrawerSelectionDeleteConfirmTitle),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);

        final confirmButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            TextButton,
            l10n.sideDrawerSelectionDelete,
          ),
        );
        expect(confirmButton, findsOneWidget);
        await tester.tap(confirmButton);
        await tester.pump();
        // deleteConversations does sqlite + asset-maintenance dart:io; those
        // hops complete in the real async zone and need interleaved pumps.
        for (var i = 0; i < 40; i++) {
          if (service.notifyCount > notifyBeforeDelete) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        expect(service.notifyCount, notifyBeforeDelete + 1);
        expect(service.getConversation(alphaId), isNull);
        expect(find.text('Alpha'), findsNothing);
        expect(find.text('Beta'), findsNothing);
        expect(find.text('Gamma'), findsNothing);
        expect(find.byType(SidebarSelectionHeader), findsNothing);
      });
    },
  );

  testWidgets(
    'external delete updates selection header count and disables empty actions',
    (tester) async {
      await asAndroid(() async {
        final service = createService();
        late final String alphaId;
        late final String betaId;
        await tester.runAsync(() async {
          await service.init();
          alphaId = (await service.createConversation(title: 'Alpha')).id;
          betaId = (await service.createConversation(title: 'Beta')).id;
        });
        await pumpDrawer(tester, service);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SideDrawer)),
        )!;

        SideDrawer.debugEnterSelectionMode!(alphaId);
        await tester.pump();
        await tester.tap(find.text('Beta'));
        await tester.pump();
        expect(find.text(l10n.sideDrawerSelectionTitle(2)), findsOneWidget);
        expect(
          tester
              .widget<SidebarSelectionActionBar>(
                find.byType(SidebarSelectionActionBar),
              )
              .selectedCount,
          2,
        );

        await tester.runAsync(() => service.deleteConversation(alphaId));
        for (var i = 0; i < 40; i++) {
          if (service.getConversation(alphaId) == null) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Alpha'), findsNothing);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text(l10n.sideDrawerSelectionTitle(1)), findsOneWidget);
        expect(find.text(l10n.sideDrawerSelectionTitle(2)), findsNothing);
        expect(
          tester
              .widget<SidebarSelectionActionBar>(
                find.byType(SidebarSelectionActionBar),
              )
              .selectedCount,
          1,
        );

        await tester.runAsync(() => service.deleteConversation(betaId));
        for (var i = 0; i < 40; i++) {
          if (service.getConversation(betaId) == null) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(l10n.sideDrawerSelectionTitle(0)), findsOneWidget);
        expect(
          tester
              .widget<SidebarSelectionActionBar>(
                find.byType(SidebarSelectionActionBar),
              )
              .selectedCount,
          0,
        );
      });
    },
  );

  testWidgets('glass drawer shows the colour backdrop under a veil', (
    tester,
  ) async {
    final service = createService();
    await tester.runAsync(service.init);
    await pumpDrawer(tester, service, embedded: false);
    expect(find.byType(ChatGradientBackground), findsNothing);

    final settings = Provider.of<SettingsProvider>(
      tester.element(find.byType(SideDrawer)),
      listen: false,
    );
    await settings.loaded;
    await settings.setGlassTheme(true);
    await tester.pump();
    expect(find.byType(ChatGradientBackground), findsOneWidget);
    expect(
      tester.widget<Drawer>(find.byType(Drawer)).backgroundColor,
      Colors.transparent,
    );
    // Frosted: the backdrop is blurred behind the veil.
    final blur = find.descendant(
      of: find.byType(SidebarGlassBackdrop),
      matching: find.byType(ImageFiltered),
    );
    expect(blur, findsOneWidget);
    // Economy mode keeps the veil without the blur.
    await settings.setGlassEconomy(true);
    await tester.pump();
    expect(find.byType(SidebarGlassBackdrop), findsOneWidget);
    expect(blur, findsNothing);

    await settings.setGlassTheme(false);
    await tester.pump();
    expect(find.byType(ChatGradientBackground), findsNothing);
  });

  testWidgets('on glass the chat rows and the bottom bar have no solid fill', (
    tester,
  ) async {
    final service = createService();
    await tester.runAsync(() async {
      await service.init();
      await service.createConversation(title: 'Alpha');
      await service.createConversation(title: 'Beta');
    });
    await pumpDrawer(tester, service, embedded: false, showBottomBar: true);

    Color rowFill(String title) => tester
        .widget<IosCardPress>(
          find
              .ancestor(
                of: find.text(title),
                matching: find.byType(IosCardPress),
              )
              .first,
        )
        .baseColor!;
    Color? barFill() =>
        (tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byKey(
                              const ValueKey<String>('sidebar-user-bar'),
                            ),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?)
            ?.color;

    final surface = Theme.of(
      tester.element(find.byType(SideDrawer)),
    ).colorScheme.surface;
    // Rows never have a fill, as in OmniBot; the bottom bar is solid
    // without glass.
    expect(rowFill('Alpha'), Colors.transparent);
    expect(barFill(), surface);

    final settings = Provider.of<SettingsProvider>(
      tester.element(find.byType(SideDrawer)),
      listen: false,
    );
    await settings.loaded;
    await settings.setGlassTheme(true);
    // The rebuilt rows replay their entrance animation; let it finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(rowFill('Alpha'), Colors.transparent);
    expect(barFill(), Colors.transparent);
  });

  testWidgets('the round + next to the search starts a new chat and closes '
      'the panel', (tester) async {
    final service = createService();
    await tester.runAsync(service.init);
    final calls = <bool>[];
    await pumpDrawer(
      tester,
      service,
      embedded: false,
      onNewConversation: ({closeDrawer = false}) => calls.add(closeDrawer),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-new-chat')));
    await tester.pump();
    expect(calls, [true]);
    expect(find.bySemanticsLabel('New chat'), findsOneWidget);
  });

  testWidgets('without a new-chat action there is no + button', (tester) async {
    final service = createService();
    await tester.runAsync(service.init);
    await pumpDrawer(tester, service, embedded: false);
    expect(
      find.byKey(const ValueKey<String>('sidebar-new-chat')),
      findsNothing,
    );
  });

  testWidgets('archiving hides a chat from the list and restoring puts it '
      'back in its old place', (tester) async {
    final service = createService();
    late String alphaId;
    await tester.runAsync(() async {
      await service.init();
      alphaId = (await service.createConversation(title: 'Alpha')).id;
      await service.createConversation(title: 'Beta');
    });
    await pumpDrawer(tester, service, embedded: false);
    expect(find.text('Alpha'), findsOneWidget);
    final updated = service.getConversation(alphaId)!.updatedAt;
    final revision = service.conversationListRevision;

    await tester.runAsync(
      () => service.setConversationsArchived([alphaId], true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(service.conversationListRevision, greaterThan(revision));
    expect(service.getArchivedConversations().map((c) => c.id), [alphaId]);
    // Archiving is not activity: the chat keeps its place in time.
    expect(service.getConversation(alphaId)!.updatedAt, updated);

    await tester.runAsync(
      () => service.setConversationsArchived([alphaId], false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alpha'), findsOneWidget);
    expect(service.getArchivedConversations(), isEmpty);
  });

  testWidgets('a full swipe to the left archives a chat and Undo brings it '
      'back', (tester) async {
    final service = createService();
    await tester.runAsync(() async {
      await service.init();
      await service.createConversation(title: 'Alpha');
      await service.createConversation(title: 'Beta');
    });
    await pumpDrawer(tester, service, embedded: false);

    // As in OmniBot, pulling the row all the way archives it.
    await tester.timedDrag(
      find.text('Beta'),
      const Offset(-1180, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pump();
    await settleUntil(
      tester,
      () => service.getArchivedConversations().isNotEmpty,
    );
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(service.getArchivedConversations().map((c) => c.title), ['Beta']);

    expect(find.text('Chat archived'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settleUntil(tester, () => service.getArchivedConversations().isEmpty);
    expect(find.text('Beta'), findsOneWidget);
    // Let the notifications time out and slide away.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a short swipe to the left shows delete, pin, copy and '
      'archive', (tester) async {
    final service = createService();
    late String betaId;
    await tester.runAsync(() async {
      await service.init();
      await service.createConversation(title: 'Alpha');
      betaId = (await service.createConversation(title: 'Beta')).id;
    });
    await pumpDrawer(tester, service, embedded: false);

    // Past half of the buttons' width (the test window is 1200 wide).
    await tester.timedDrag(
      find.text('Beta'),
      const Offset(-800, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('Beta'),
      matching: find.byType(Slidable),
    );
    Finder button(IconData icon) =>
        find.descendant(of: row, matching: find.byIcon(icon));
    for (final icon in [
      LucideIcons.trash2,
      LucideIcons.pin,
      LucideIcons.copy,
      LucideIcons.archive,
    ]) {
      expect(button(icon), findsOneWidget, reason: '$icon');
    }

    final revision = service.conversationListRevision;
    await tester.tap(button(LucideIcons.pin));
    // The flag flips at once; the list hears of it after the database write.
    await settleUntil(
      tester,
      () => service.conversationListRevision > revision,
    );
    expect(service.getConversation(betaId)?.isPinned, isTrue);
    expect(find.text('Pinned'), findsOneWidget);
    // A swipe leftward on a row belongs to the row: nothing else happened.
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('the archive button lists archived chats; restore and open '
      'work from there', (tester) async {
    final service = createService();
    late String alphaId;
    final opened = <String>[];
    await tester.runAsync(() async {
      await service.init();
      alphaId = (await service.createConversation(title: 'Alpha')).id;
      await service.createConversation(title: 'Beta');
      await service.setConversationsArchived([alphaId], true);
    });
    await pumpDrawer(
      tester,
      service,
      embedded: false,
      onSelectConversation: (id, {closeDrawer = false}) => opened.add(id),
    );
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-archive')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatArchivePage), findsOneWidget);
    expect(find.byKey(ChatArchivePage.rowKey(alphaId)), findsOneWidget);

    await tester.tap(find.byKey(ChatArchivePage.restoreKey(alphaId)));
    await settleUntil(tester, () => service.getArchivedConversations().isEmpty);
    expect(find.byKey(ChatArchivePage.rowKey(alphaId)), findsNothing);
    expect(
      find.text(
        'Nothing archived. Swipe a chat to the right to put '
        'it here.',
      ),
      findsOneWidget,
    );

    // Archive it again and open it from the archive.
    await tester.runAsync(
      () => service.setConversationsArchived([alphaId], true),
    );
    await tester.pump();
    await tester.tap(find.byKey(ChatArchivePage.rowKey(alphaId)));
    await tester.pumpAndSettle();
    expect(find.byType(ChatArchivePage), findsNothing);
    expect(opened, [alphaId]);
    // Let the notifications time out and slide away.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a chat shows previews of its latest images, and the setting '
      'turns them off', (tester) async {
    final service = createService();
    late String withImages;
    await tester.runAsync(() async {
      await service.init();
      withImages = (await service.createConversation(title: 'Photos')).id;
      await service.createConversation(title: 'Plain');
      final dir = Directory('${tempDir.path}/upload');
      await dir.create(recursive: true);
      for (final name in ['a.png', 'b.png']) {
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(const [1, 2, 3]);
        await service.addMessage(
          conversationId: withImages,
          role: 'user',
          parts: [ImagePart(uri: file.path, mime: 'image/png')],
        );
      }
    });
    await pumpDrawer(tester, service, embedded: false);
    // The lookup runs on the database.
    await settleUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
    expect(find.byType(ChatThumbnails), findsNWidgets(2));
    expect(find.byType(Image), findsNWidgets(2));

    final settings = Provider.of<SettingsProvider>(
      tester.element(find.byType(SideDrawer)),
      listen: false,
    );
    await settings.setSidebarThumbnails(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatThumbnails), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  test('the thumbnails setting is on by default and kept', () async {
    final prefs = createBusinessTestPreferences();
    final first = SettingsProvider(prefs);
    await first.loaded;
    expect(first.sidebarThumbnails, isTrue);
    await first.setSidebarThumbnails(false);
    final second = SettingsProvider(prefs);
    await second.loaded;
    expect(second.sidebarThumbnails, isFalse);
    first.dispose();
    second.dispose();
  });

  testWidgets('section headers show how many chats they hold', (tester) async {
    final service = createService();
    late String pinnedId;
    await tester.runAsync(() async {
      await service.init();
      pinnedId = (await service.createConversation(title: 'Pinned one')).id;
      await service.createConversation(title: 'Today one');
      await service.createConversation(title: 'Today two');
      await service.setConversationsPinned([pinnedId], true);
    });
    await pumpDrawer(tester, service, embedded: false);
    final settings = Provider.of<SettingsProvider>(
      tester.element(find.byType(SideDrawer)),
      listen: false,
    );
    // Date headers are always shown now, as in OmniBot.
    // "Pinned 1" and "Today 2".
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // A tap folds the section: its chats hide, the header and count stay,
    // and the choice is remembered.
    expect(find.text('Today one'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Today one'), findsNothing);
    expect(find.text('Today two'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Pinned one'), findsOneWidget);
    expect(settings.sidebarCollapsedSections, hasLength(1));
    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Today one'), findsOneWidget);
    expect(settings.sidebarCollapsedSections, isEmpty);
  });

  testWidgets('older days are headed in the app language', (tester) async {
    final service = createService();
    await tester.runAsync(service.init);
    // A day before yesterday, so the header shows a date, not a word.
    final day = DateTime.now().subtract(const Duration(days: 5));
    service.seedConversationsForTest([
      Conversation(title: 'Old chat', createdAt: day, updatedAt: day),
    ]);
    await pumpDrawer(
      tester,
      service,
      embedded: false,
      locale: const Locale('ru'),
    );
    final pattern = day.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy';
    final label = DateFormat(pattern, 'ru').format(day);
    expect(find.text(label), findsOneWidget);
    // Russian month, not "Sep".
    expect(label, isNot(contains(DateFormat('MMM', 'en').format(day))));
  });

  group('folders', () {
    test('the list survives a round trip and skips damaged entries', () async {
      const work = ChatFolder(id: 'w', name: 'Work', icon: 'briefcase');
      const games = ChatFolder(id: 'g', name: 'Games', icon: 'gamepad');
      expect(ChatFolder.decodeList(ChatFolder.encodeList([work, games])), [
        work,
        games,
      ]);
      expect(ChatFolder.decodeList('{'), isEmpty);
      expect(ChatFolder.decodeList('{"id":"x"}'), isEmpty);
      expect(
        ChatFolder.decodeList(
          '[{"id":"","name":"a"},{"id":"a","name":"A","icon":"nope"}]',
        ),
        [const ChatFolder(id: 'a', name: 'A', icon: 'folder')],
      );

      final prefs = createBusinessTestPreferences();
      final first = SettingsProvider(prefs);
      await first.loaded;
      expect(first.sidebarFolders, isEmpty);
      await first.setSidebarFolders([games, work]);
      final second = SettingsProvider(prefs);
      await second.loaded;
      expect(second.sidebarFolders, [games, work]);
      first.dispose();
      second.dispose();
    });

    // The sidebar has its own search field; this is the dialog's.
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    Future<SettingsProvider> addFolders(
      WidgetTester tester,
      List<ChatFolder> folders,
    ) async {
      final settings = Provider.of<SettingsProvider>(
        tester.element(find.byType(SideDrawer)),
        listen: false,
      );
      await settings.setSidebarFolders(folders);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return settings;
    }

    testWidgets('a folder gathers its chats after the pinned ones, keeps '
        'their time and folds like any section', (tester) async {
      final service = createService();
      late String pinnedId;
      late String alphaId;
      await tester.runAsync(() async {
        await service.init();
        pinnedId = (await service.createConversation(title: 'Pinned one')).id;
        alphaId = (await service.createConversation(title: 'Alpha')).id;
        await service.createConversation(title: 'Beta');
        await service.createConversation(title: 'Gamma');
        await service.setConversationsPinned([pinnedId], true);
      });
      await pumpDrawer(tester, service, embedded: false);
      final settings = await addFolders(tester, const [
        ChatFolder(id: 'work', name: 'Work', icon: 'briefcase'),
      ]);
      // An empty folder still shows, so chats can be put in it.
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      final updated = service.getConversation(alphaId)!.updatedAt;
      await tester.runAsync(
        () => service.setConversationsFolder([alphaId], 'work'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ChatService.folderOf(service.getConversation(alphaId)!), 'work');
      // Putting a chat in a folder is not activity.
      expect(service.getConversation(alphaId)!.updatedAt, updated);

      // Pinned 1, Work 1, Today 2 — in that order.
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Pinned'), lessThan(top('Work')));
      expect(top('Work'), lessThan(top('Alpha')));
      expect(top('Alpha'), lessThan(top('Today')));
      expect(top('Today'), lessThan(top('Beta')));
      expect(find.byIcon(LucideIcons.briefcase), findsOneWidget);

      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
      expect(settings.sidebarCollapsedSections, {'folder:work'});

      // A folder that is gone lets its chats back into the date groups.
      await settings.setSidebarFolders(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Work'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the chat menu moves a chat into a new folder and back out', (
      tester,
    ) async {
      final service = createService();
      late String alphaId;
      await tester.runAsync(() async {
        await service.init();
        alphaId = (await service.createConversation(title: 'Alpha')).id;
        await service.createConversation(title: 'Beta');
      });
      await pumpDrawer(tester, service, embedded: false);
      final settings = Provider.of<SettingsProvider>(
        tester.element(find.byType(SideDrawer)),
        listen: false,
      );

      Future<void> openMove() async {
        await tester.longPress(find.text('Alpha'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move to folder'));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();
      }

      await openMove();
      // No folders yet: only "New folder".
      expect(find.text('No folder'), findsNothing);
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField, '  Work  ');
      await tester.tap(find.text('Save'));
      await settleUntil(
        tester,
        () => ChatService.folderOf(service.getConversation(alphaId)!) != null,
      );
      expect(settings.sidebarFolders, hasLength(1));
      final folder = settings.sidebarFolders.single;
      expect(folder.name, 'Work');
      expect(folder.icon, 'folder');
      expect(
        ChatService.folderOf(service.getConversation(alphaId)!),
        folder.id,
      );
      expect(find.text('Work'), findsOneWidget);

      await openMove();
      await tester.tap(find.text('No folder'));
      await settleUntil(
        tester,
        () => ChatService.folderOf(service.getConversation(alphaId)!) == null,
      );
      // The folder stays, now empty.
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a long press on a folder renames it, changes its icon and '
        'deletes it without deleting its chats', (tester) async {
      final service = createService();
      late String alphaId;
      await tester.runAsync(() async {
        await service.init();
        alphaId = (await service.createConversation(title: 'Alpha')).id;
        await service.createConversation(title: 'Beta');
        await service.setConversationsFolder([alphaId], 'work');
      });
      await pumpDrawer(tester, service, embedded: false);
      final settings = await addFolders(tester, const [
        ChatFolder(id: 'work', name: 'Work', icon: 'folder'),
      ]);

      await tester.longPress(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField, 'Games');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(settings.sidebarFolders.single.name, 'Games');
      expect(find.text('Games'), findsOneWidget);

      await tester.longPress(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Icon'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('folder-icon-gamepad')),
      );
      await tester.pumpAndSettle();
      expect(settings.sidebarFolders.single.icon, 'gamepad');
      expect(find.byIcon(LucideIcons.gamepad2), findsOneWidget);

      await tester.longPress(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();
      expect(find.text('Chats in "Games" stay in the list.'), findsOneWidget);
      await tester.tap(find.text('Delete folder').last);
      await settleUntil(
        tester,
        () => ChatService.folderOf(service.getConversation(alphaId)!) == null,
      );
      expect(settings.sidebarFolders, isEmpty);
      expect(find.text('Games'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget);
      expect(service.getConversation(alphaId), isNotNull);
    });
  });
}

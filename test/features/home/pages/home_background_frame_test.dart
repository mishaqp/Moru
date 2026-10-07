import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tag_provider.dart';
import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/home/pages/home_mobile_layout.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/interactive_drawer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    for (final glass in const [false, true]) {
      testWidgets('mobile wallpaper keeps screen coordinates during drawer '
          'opening $size glass=$glass', (tester) async {
        final directory = Directory.systemTemp.createTempSync('home-frame-');
        final previousPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Paths(directory.path);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.reset();
          PathProviderPlatform.instance = previousPaths;
          debugDefaultTargetPlatformOverride = null;
          directory.deleteSync(recursive: true);
        });

        late final SettingsProvider settings;
        late final AssistantProvider assistants;
        late final BackupReminderProvider backup;
        late final TagProvider tags;
        late final UserProvider user;
        late final UpdateProvider update;
        late final String path;
        await tester.runAsync(() async {
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
          path = await _writePhoto(directory);
          await settings.setChatAppearance(
            ChatAppearanceSettings(
              light: ChatBackgroundSettings(
                type: ChatBackgroundType.image,
                path: path,
                fit: ChatBackgroundFit.fill,
                focusX: .6,
                focusY: -.4,
                maskStrength: 0,
              ),
            ),
          );
          await settings.setSidebarAppearance(
            const SidebarAppearanceSettings(maskStrength: 0),
          );
          await settings.setGlassTheme(glass);
        });

        final service = _EmptyChatService();
        final drawer = InteractiveDrawerController();
        final closeTick = ValueNotifier(0);
        final root = GlobalKey();
        final theme = ThemeData(brightness: Brightness.dark);
        try {
          final preloadKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(home: SizedBox(key: preloadKey)));
          await tester.runAsync(
            () => precacheImage(
              ResizeImage(
                FileImage(File(path)),
                width: size.width.ceil(),
                height: size.height.ceil(),
                policy: ResizeImagePolicy.fit,
                allowUpscaling: false,
              ),
              preloadKey.currentContext!,
            ),
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ChatService>.value(value: service),
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider.value(value: assistants),
                ChangeNotifierProvider.value(value: backup),
                ChangeNotifierProvider.value(value: tags),
                ChangeNotifierProvider.value(value: user),
                ChangeNotifierProvider.value(value: update),
              ],
              child: MaterialApp(
                theme: theme,
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: RepaintBoundary(
                  key: root,
                  child: HomeMobileScaffold(
                    scaffoldKey: GlobalKey<ScaffoldState>(),
                    drawerController: drawer,
                    assistantPickerCloseTick: closeTick,
                    loadingConversationIds: const {},
                    title: 'Chat',
                    providerName: null,
                    modelDisplay: null,
                    onToggleDrawer: () {},
                    onDismissKeyboard: () {},
                    onSelectConversation: (_) {},
                    onNewConversation: () {},
                    onOpenMiniMap: () {},
                    onCreateNewConversation: () async {},
                    onToggleTemporaryConversation: () async {},
                    onSelectModel: () {},
                    canToggleTemporaryConversation: false,
                    temporaryConversationEnabled: false,
                    globalSearchMode: false,
                    globalSearchQuery: '',
                    onGlobalSearchQueryChanged: (_) {},
                    onEnterGlobalSearch: () {},
                    onExitGlobalSearch: () {},
                    onOpenGlobalSearchResult: (_, _) async {},
                    appBarOverride: const PreferredSize(
                      preferredSize: Size.zero,
                      child: SizedBox.shrink(),
                    ),
                    body: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          final closed = await _capture(tester, root);
          final filters = debugChatBackgroundFilterBuildCount;
          final providers = debugChatBackgroundImageProviderBuildCount;

          for (final progress in [.25, .5, .75, 1.0]) {
            drawer.jumpTo(progress);
            await tester.pump(const Duration(milliseconds: 16));
            final opened = await _capture(tester, root);
            final point = Offset(size.width - 12, size.height / 2);
            final expected = Color.alphaBlend(
              Colors.black.withValues(alpha: .32 * progress),
              closed.at(point),
            );
            _expectPixel(
              opened.at(point),
              expected,
              'Exposed chat must keep screen coordinates at progress $progress',
            );
          }
          final opened = await _capture(tester, root);
          if (!glass) {
            // The empty panel margin avoids all foreground widgets.
            final point = Offset(4, size.height / 2);
            _expectPixel(
              opened.at(point),
              closed.at(point),
              'Shared sidebar and chat must use the same screen coordinates',
            );
          }
          expect(debugChatBackgroundFilterBuildCount, filters);
          expect(debugChatBackgroundImageProviderBuildCount, providers);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 500));
          drawer.dispose();
          closeTick.dispose();
          service.dispose();
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

void _expectPixel(Color actual, Color expected, String reason) {
  for (final pair in [
    (actual.r, expected.r),
    (actual.g, expected.g),
    (actual.b, expected.b),
  ]) {
    expect(pair.$1, closeTo(pair.$2, 2 / 255), reason: reason);
  }
}

Future<String> _writePhoto(Directory directory) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 960, 640),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(960, 640),
        [Colors.red, Colors.green, Colors.blue],
        [0, .5, 1],
      ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(960, 640);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${directory.path}/photo.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<_Pixels> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return _Pixels(
      image.width,
      Uint8List.fromList(bytes!.buffer.asUint8List()),
    );
  } finally {
    image.dispose();
  }
}

class _Pixels {
  const _Pixels(this.width, this.bytes);
  final int width;
  final Uint8List bytes;

  Color at(Offset point) {
    final index = (point.dy.floor() * width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes[index + 3],
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
    );
  }
}

class _EmptyChatService extends ChatService {
  @override
  bool get initialized => true;

  @override
  List<Conversation> getAllConversations() => const [];
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
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

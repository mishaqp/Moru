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
import 'package:Kelivo/features/home/widgets/side_drawer.dart';
import 'package:Kelivo/features/home/widgets/sidebar_bottom_bar.dart';
import 'package:Kelivo/features/home/widgets/sidebar_omni_parts.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
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

  for (final (layout, size, embedded) in const [
    ('phone', Size(390, 844), false),
    ('tablet', Size(1000, 800), true),
    ('landscape', Size(844, 390), true),
  ]) {
    for (final brightness in Brightness.values) {
      for (final glass in const [false, true]) {
        for (final mode in const [
          SidebarBackgroundMode.sameAsChat,
          SidebarBackgroundMode.custom,
        ]) {
          testWidgets(
            'real sidebar artwork covers edges and secondary surfaces '
            '$layout ${brightness.name} glass=$glass ${mode.name}',
            (tester) async {
              final directory = Directory.systemTemp.createTempSync(
                'sidebar-background-coverage-',
              );
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
              late final String redPath;
              late final String greenPath;
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
                await settings.setGlassTheme(glass);
                redPath = await _writeImage(
                  directory,
                  'red',
                  const Color(0xffff0000),
                );
                greenPath = await _writeImage(
                  directory,
                  'green',
                  const Color(0xff00ff00),
                );
                await _setArtwork(settings, mode, redPath);
              });
              final service = _EmptyChatService();
              final key = GlobalKey();
              final panelWidth = settings.sidebarAppearance.widthFor(
                size.width,
                wide: embedded,
              );

              try {
                // Start file decoding in the real async zone before the
                // drawer resolves these providers from the fake test clock.
                // Cache both sizes: shared artwork uses the screen frame,
                // whereas a custom scene is fitted to the sidebar panel.
                final preloadKey = GlobalKey();
                await tester.pumpWidget(
                  MaterialApp(home: SizedBox(key: preloadKey)),
                );
                await tester.runAsync(() async {
                  for (final path in [redPath, greenPath]) {
                    for (final width in {
                      panelWidth.ceil(),
                      size.width.ceil(),
                    }) {
                      await precacheImage(
                        ResizeImage(
                          FileImage(File(path)),
                          width: width,
                          height: size.height.ceil(),
                          policy: ResizeImagePolicy.fit,
                          allowUpscaling: false,
                        ),
                        preloadKey.currentContext!,
                      );
                    }
                  }
                });
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
                      theme: ThemeData(brightness: brightness),
                      locale: const Locale('en'),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      home: MediaQuery(
                        data: MediaQueryData(
                          size: size,
                          padding: const EdgeInsets.fromLTRB(12, 24, 14, 24),
                          viewPadding: const EdgeInsets.fromLTRB(
                            12,
                            24,
                            14,
                            24,
                          ),
                        ),
                        child: RepaintBoundary(
                          key: key,
                          child: Scaffold(
                            body: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: panelWidth,
                                child: SideDrawer(
                                  userName: 'User',
                                  assistantName: 'Assistant',
                                  embedded: embedded,
                                  embeddedWidth: panelWidth,
                                  showBottomBar: true,
                                  onNewConversation:
                                      ({bool closeDrawer = true}) {},
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await _settleImage(tester);
                _expectControlsVisible();
                final samples = _samplePoints(tester, panelWidth, size.height);
                final red = await _capture(tester, key);
                _expectForegroundPainted(tester, red, samples);

                await tester.runAsync(
                  () => _setArtwork(settings, mode, greenPath),
                );
                await tester.pump();
                await _settleImage(tester);
                _expectControlsVisible();
                final green = await _capture(tester, key);
                _expectForegroundPainted(tester, green, samples);

                // A solid surface over any of these locations hides both
                // images and leaves the pixel unchanged. Sample away from
                // glyphs, icons and rounded boundaries so the result measures
                // the actual artwork through the panel and control surfaces.
                final hiddenArtwork = <String>[];
                for (final sample in samples.entries) {
                  final redPixel = red.at(sample.value);
                  final greenPixel = green.at(sample.value);
                  if (redPixel.r - greenPixel.r <= 20 ||
                      greenPixel.g - redPixel.g <= 20) {
                    hiddenArtwork.add(
                      '${sample.key}: $redPixel became $greenPixel',
                    );
                  }
                }
                expect(
                  hiddenArtwork,
                  isEmpty,
                  reason: 'Artwork must remain visible through every sample.',
                );
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pump(const Duration(milliseconds: 500));
                service.dispose();
                settings.dispose();
                assistants.dispose();
                backup.dispose();
                tags.dispose();
                user.dispose();
                update.dispose();
                debugDefaultTargetPlatformOverride = null;
              }
            },
          );
        }
      }
    }
  }
}

void _expectControlsVisible() {
  expect(find.byType(SidebarSearchField).hitTestable(), findsOneWidget);
  expect(
    find.byKey(const ValueKey<String>('sidebar-archive')).hitTestable(),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('sidebar-new-chat')).hitTestable(),
    findsOneWidget,
  );
  expect(find.byType(SidebarDockCapsule).hitTestable(), findsOneWidget);
  expect(find.byKey(SidebarBottomBar.avatarKey).hitTestable(), findsOneWidget);
  for (final item in SidebarAppearanceSettings.defaultDockItems) {
    expect(
      find.byKey(ValueKey<String>('sidebar-dock-${item.name}')).hitTestable(),
      findsOneWidget,
    );
  }
}

void _expectForegroundPainted(
  WidgetTester tester,
  _Pixels pixels,
  Map<String, Offset> samples,
) {
  void painted(String label, Finder foreground, Offset plainSurface) {
    final rect = tester.getRect(foreground).deflate(1);
    final fill = pixels.at(plainSurface);
    var contrastingPixels = 0;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final pixel = pixels.at(Offset(x.toDouble(), y.toDouble()));
        final difference =
            (pixel.r - fill.r).abs() +
            (pixel.g - fill.g).abs() +
            (pixel.b - fill.b).abs();
        if (difference > 45) contrastingPixels++;
      }
    }
    expect(
      contrastingPixels,
      greaterThan(8),
      reason: '$label must paint visible content over its surface.',
    );
  }

  painted(
    'search icon',
    find.descendant(
      of: find.byType(SidebarSearchField),
      matching: find.byType(Icon),
    ),
    samples['search surface']!,
  );
  painted(
    'archive icon',
    find.descendant(
      of: find.byKey(const ValueKey<String>('sidebar-archive')),
      matching: find.byType(Icon),
    ),
    samples['archive surface']!,
  );
  final newChat = find.byKey(const ValueKey<String>('sidebar-new-chat'));
  final newChatRect = tester.getRect(newChat);
  painted(
    'new chat icon',
    find.descendant(of: newChat, matching: find.byType(Icon)),
    Offset(newChatRect.center.dx, newChatRect.top + 5),
  );
  for (final item in SidebarAppearanceSettings.defaultDockItems) {
    painted(
      'dock ${item.name}',
      item == SidebarDockItem.profile
          ? find.byKey(SidebarBottomBar.avatarKey)
          : find.descendant(
              of: find.byKey(ValueKey<String>('sidebar-dock-${item.name}')),
              matching: find.byType(Icon),
            ),
      samples['dock surface']!,
    );
  }
}

Map<String, Offset> _samplePoints(
  WidgetTester tester,
  double width,
  double height,
) {
  final search = tester.getRect(find.byType(SidebarSearchField));
  final archive = tester.getRect(
    find.byKey(const ValueKey<String>('sidebar-archive')),
  );
  final newChat = tester.getRect(
    find.byKey(const ValueKey<String>('sidebar-new-chat')),
  );
  final dock = tester.getRect(find.byType(SidebarDockCapsule));
  return {
    'status edge': Offset(width / 2, 12),
    'gesture edge': Offset(width / 2, height - 12),
    'left safe edge': Offset(6, height / 2),
    'right safe edge': Offset(width - 7, height / 2),
    'header above search': Offset(search.center.dx, search.top - 8),
    'header between archive and new chat': Offset(
      (archive.right + newChat.left) / 2,
      archive.center.dy,
    ),
    'search surface': Offset(search.center.dx, search.top + 4),
    'archive surface': Offset(archive.center.dx, archive.top + 5),
    'dock surface': Offset(dock.center.dx, dock.top + 4),
    'below dock': Offset(dock.center.dx, dock.bottom + 6),
  };
}

Future<void> _setArtwork(
  SettingsProvider settings,
  SidebarBackgroundMode mode,
  String path,
) async {
  final background = ChatBackgroundSettings(
    type: ChatBackgroundType.image,
    path: path,
    maskStrength: 0,
  );
  await settings.setChatAppearance(
    ChatAppearanceSettings(light: background, dark: background),
  );
  await settings.setSidebarAppearance(
    settings.sidebarAppearance.copyWith(
      backgroundMode: mode,
      customBackground: background,
      maskStrength: 0,
    ),
  );
}

Future<String> _writeImage(
  Directory directory,
  String name,
  Color color,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _settleImage(WidgetTester tester) async {
  final image = find.descendant(
    of: find.byType(ChatBackground),
    matching: find.byType(Image),
  );
  expect(image, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
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

  ({int r, int g, int b}) at(Offset point) {
    final index = (point.dy.floor() * width + point.dx.floor()) * 4;
    return (r: bytes[index], g: bytes[index + 1], b: bytes[index + 2]);
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

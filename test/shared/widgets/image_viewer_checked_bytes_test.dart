import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/features/chat/pages/image_viewer_page.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'model-tmp');
  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'app-data');
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(root, 'app-data');
}

void main() {
  for (final (action, format) in [
    ('save', 'png'),
    ('share', 'png'),
    ('share', 'bmp'),
  ]) {
    testWidgets(
      'viewer $action $format uses checked bytes after path replacement',
      (tester) async {
        try {
          final dir = Directory(
            p.join(Directory.current.path, '.dart_tool'),
          ).createTempSync('checked_viewer_');
          addTearDown(() => dir.deleteSync(recursive: true));
          final oldPaths = PathProviderPlatform.instance;
          PathProviderPlatform.instance = _Paths(dir.path);
          addTearDown(() => PathProviderPlatform.instance = oldPaths);
          Directory(p.join(dir.path, 'model-tmp')).createSync();
          Directory(p.join(dir.path, 'app-data')).createSync();
          final bytes = format == 'bmp'
              ? Uint8List.fromList([
                  0x42,
                  0x4d,
                  58,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  54,
                  0,
                  0,
                  0,
                  40,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  1,
                  0,
                  24,
                  0,
                  0,
                  0,
                  0,
                  0,
                  4,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  255,
                  0,
                  0,
                  0,
                ])
              : base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Kz0AAAAASUVORK5CYII=',
                );
          final selected = File(p.join(dir.path, 'selected.$format'))
            ..writeAsBytesSync(bytes);
          final private = File(p.join(dir.path, 'private.png'))
            ..writeAsStringSync('private data');
          final ready = Completer<Uint8List>();
          String? sharedPath;
          final channel = MethodChannel(
            action == 'save'
                ? 'image_gallery_saver_plus'
                : 'dev.fluttercommunity.plus/share',
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async {
              if (action == 'save') {
                ready.complete(
                  (call.arguments as Map)['imageBytes'] as Uint8List,
                );
                return {'isSuccess': true};
              }
              final path =
                  ((call.arguments as Map)['paths'] as List).single as String;
              sharedPath = path;
              ready.complete(await File(path).readAsBytes());
              return 'shared';
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ImageViewerPage(
                images: [selected.path],
                imageProviders: {selected.path: MemoryImage(bytes)},
              ),
            ),
          );
          await tester.pump();
          await tester.runAsync(() async {
            await selected.delete();
            await Link(selected.path).create(private.path);
          });
          await tester.tap(
            find.byIcon(action == 'save' ? Lucide.Download : Lucide.Share2),
          );
          final deadline = Stopwatch()..start();
          while ((!ready.isCompleted ||
                  find
                      .byType(CircularProgressIndicator)
                      .evaluate()
                      .isNotEmpty) &&
              deadline.elapsed < const Duration(seconds: 10)) {
            await tester.runAsync(() => Future<void>(() {}));
            await tester.pump();
          }
          expect(ready.isCompleted, isTrue);
          expect(await ready.future, bytes);
          if (action == 'share') {
            expect(
              p.isWithin(
                p.join(dir.path, 'app-data', 'workspace-previews'),
                sharedPath!,
              ),
              isTrue,
            );
            expect(p.extension(sharedPath!), '.$format');
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pump();
          AppSnackBarManager().dismissAll();
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 4));
        }
      },
    );
  }
}

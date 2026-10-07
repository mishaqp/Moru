import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/screen_wakelock.dart';
import 'package:Kelivo/features/mini_apps/mini_app_display.dart';

MiniApp _app({
  bool fullscreen = false,
  MiniAppOrientation orientation = MiniAppOrientation.any,
  bool keepAwake = false,
}) => MiniApp(
  id: 'game',
  name: 'Game',
  directory: '/tmp/game',
  fullscreen: fullscreen,
  orientation: orientation,
  keepAwake: keepAwake,
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final wakelock = <bool>[];

  setUp(() {
    calls.clear();
    wakelock.clear();
    ScreenWakelock.debugReset(platformApply: wakelock.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    ScreenWakelock.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<String> summary() => [
    for (final call in calls)
      if (call.method == 'SystemChrome.setEnabledSystemUIMode')
        'mode ${call.arguments}'
      else if (call.method == 'SystemChrome.setPreferredOrientations')
        'orientation ${call.arguments}',
  ];

  test('an ordinary app changes nothing', () {
    MiniAppDisplay.apply(null, _app());
    MiniAppDisplay.apply(_app(), null);
    expect(summary(), isEmpty);
    expect(wakelock, isEmpty);
  });

  test('a landscape fullscreen game sets the screen up and restores it', () {
    final game = _app(
      fullscreen: true,
      orientation: MiniAppOrientation.landscape,
      keepAwake: true,
    );
    MiniAppDisplay.apply(null, game);
    expect(summary(), [
      'mode SystemUiMode.immersiveSticky',
      'orientation [DeviceOrientation.landscapeLeft, '
          'DeviceOrientation.landscapeRight]',
    ]);
    expect(wakelock, [true]);

    calls.clear();
    MiniAppDisplay.apply(game, null);
    expect(summary(), ['mode SystemUiMode.edgeToEdge', 'orientation []']);
    expect(wakelock, [true, false]);
    expect(ScreenWakelock.debugForced, 0);
  });

  test('a rollback to a portrait version only changes what differs', () {
    final landscape = _app(
      fullscreen: true,
      orientation: MiniAppOrientation.landscape,
      keepAwake: true,
    );
    final portrait = _app(
      fullscreen: true,
      orientation: MiniAppOrientation.portrait,
      keepAwake: true,
    );
    MiniAppDisplay.apply(null, landscape);
    calls.clear();
    MiniAppDisplay.apply(landscape, portrait);
    expect(summary(), [
      'orientation [DeviceOrientation.portraitUp, '
          'DeviceOrientation.portraitDown]',
    ]);
    // The screen stayed on throughout.
    expect(wakelock, [true]);
    expect(ScreenWakelock.debugForced, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/mini_apps/widgets/native_mini_app_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> screen, {
    Map<String, dynamic> state = const {},
    Future<void> Function(String, Map<String, dynamic>)? onAction,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    bool layered = false,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness).copyWith(
        extensions: [
          brightness == Brightness.dark
              ? AppSemanticColors.dark(
                  ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: brightness,
                  ),
                  layered: layered,
                )
              : AppSemanticColors.light(
                  ColorScheme.fromSeed(seedColor: Colors.blue),
                  layered: layered,
                ),
        ],
      ),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            child: NativeMiniAppPanel(
              screen: screen,
              state: state,
              onAction: onAction ?? (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('renders localized native cards and bound values', (
    tester,
  ) async {
    await pump(
      tester,
      {
        'version': 1,
        'components': [
          {
            'type': 'card',
            'title': {'en': 'Battery', 'ru': 'Батарея'},
            'children': [
              {
                'type': 'text',
                'text': {'en': 'Live status', 'ru': 'Состояние'},
              },
              {
                'type': 'value',
                'label': 'Charge',
                'bind': 'device.battery.levelPercent',
                'unit': '%',
              },
              {
                'type': 'indicator',
                'label': 'Charging',
                'bind': 'device.battery.charging',
              },
            ],
          },
        ],
      },
      state: {
        'device': {
          'battery': {'levelPercent': 72, 'charging': true},
        },
      },
      locale: const Locale('ru'),
    );
    expect(find.text('Батарея'), findsOneWidget);
    expect(find.text('Состояние'), findsOneWidget);
    expect(find.text('72 %'), findsOneWidget);
    expect(find.byType(SectionCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'numeric indicators clamp readings without drawing unknown as zero',
    (tester) async {
      for (final reading in [0, 50, 120, null]) {
        await pump(
          tester,
          {
            'version': 1,
            'components': [
              {
                'type': 'indicator',
                'label': 'Charge',
                'bind': 'data.charge',
                'min': 0,
                'max': 100,
                'unit': '%',
              },
            ],
          },
          state: {
            'data': {'charge': reading},
          },
        );
        if (reading == null) {
          expect(find.text('Unavailable'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
        } else {
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            (reading / 100).clamp(0, 1),
          );
          expect(find.text('$reading %'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'null sensor values have a reason and cannot become false controls',
    (tester) async {
      await pump(
        tester,
        {
          'version': 1,
          'components': [
            {
              'type': 'value',
              'label': 'Temperature',
              'bind': 'device.battery.temperatureC',
            },
            {
              'type': 'switch',
              'label': 'Torch',
              'bind': 'device.flashlight.enabled',
              'action': 'torch',
              'args': {
                'enabled': {r'$value': true},
              },
            },
          ],
        },
        state: {
          'device': {
            'battery': {
              'temperatureC': null,
              'reasons': {'temperatureC': 'unsupported'},
            },
            'flashlight': {
              'enabled': null,
              'reasons': {'enabled': 'permission_required'},
            },
          },
        },
      );
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.text('Not supported on this device'), findsOneWidget);
      expect(find.text('Permission required'), findsOneWidget);
      expect(
        tester.widget<IosSwitch>(find.byType(IosSwitch)).onChanged,
        isNull,
      );
    },
  );

  testWidgets(
    'buttons and switches substitute only the declared control value',
    (tester) async {
      final calls = <(String, Map<String, dynamic>)>[];
      await pump(
        tester,
        {
          'version': 1,
          'components': [
            {
              'type': 'button',
              'label': 'Refresh',
              'action': 'refresh',
              'args': {
                'nested': [
                  1,
                  {'literal': true},
                ],
              },
            },
            {
              'type': 'switch',
              'label': 'Torch',
              'bind': 'device.flashlight.enabled',
              'action': 'torch',
              'args': {
                'enabled': {r'$value': true},
              },
            },
          ],
        },
        state: {
          'device': {
            'flashlight': {'enabled': false},
          },
        },
        onAction: (name, args) async => calls.add((name, args)),
      );
      await tester.tap(find.text('Refresh'));
      await tester.tap(find.byType(IosSwitch));
      await tester.pump();
      expect(calls.map((call) => call.$1), ['refresh', 'torch']);
      expect(calls[0].$2, {
        'nested': [
          1,
          {'literal': true},
        ],
      });
      expect(calls[1].$2, {'enabled': true});
    },
  );

  testWidgets('sliders commit once on release and use the exact native range', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    await pump(
      tester,
      {
        'version': 1,
        'components': [
          {
            'type': 'slider',
            'label': 'Music',
            'bind': 'device.audio.volumes.music.value',
            'minBind': 'device.audio.volumes.music.min',
            'maxBind': 'device.audio.volumes.music.max',
            'step': 1,
            'action': 'volume',
            'args': {
              'stream': 'music',
              'value': {r'$value': true},
            },
          },
        ],
      },
      state: {
        'device': {
          'audio': {
            'volumes': {
              'music': {'value': 2, 'min': 2, 'max': 7},
            },
          },
        },
      },
      onAction: (_, args) async => calls.add(args),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 2);
    expect(slider.max, 7);
    slider.onChanged!(5);
    await tester.pump();
    expect(calls, isEmpty);
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(5);
    await tester.pump();
    expect(calls, [
      {'stream': 'music', 'value': 5},
    ]);
  });

  testWidgets(
    'safe package selector offers snapshot entries without free text',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await pump(
        tester,
        {
          'version': 1,
          'components': [
            {
              'type': 'list',
              'label': 'Stop an app',
              'bind': 'device.system.stoppableApps',
              'valueKey': 'packageName',
              'labelKey': 'label',
              'action': 'stop',
              'args': {
                'packageName': {r'$value': true},
              },
            },
          ],
        },
        state: {
          'device': {
            'system': {
              'stoppableApps': [
                {'packageName': 'org.example.notes', 'label': 'Notes'},
              ],
            },
          },
        },
        onAction: (_, args) async => calls.add(args),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<Object>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes').last);
      await tester.pumpAndSettle();
      expect(calls, [
        {'packageName': 'org.example.notes'},
      ]);
    },
  );

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(900, 400)]) {
      for (final layered in [false, true]) {
        testWidgets(
          'native controls fit $size at 1.3 in $brightness (layered: $layered)',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await pump(
              tester,
              {
                'version': 1,
                'components': [
                  {
                    'type': 'card',
                    'title': 'A readable title for a phone panel',
                    'children': [
                      {
                        'type': 'value',
                        'label':
                            'Battery temperature with a longer description',
                        'bind': 'temperature',
                      },
                      {
                        'type': 'switch',
                        'label': 'A longer setting label that must wrap',
                        'bind': 'enabled',
                        'action': 'toggle',
                      },
                      {
                        'type': 'button',
                        'label': 'Open the Android settings for this feature',
                        'action': 'settings',
                      },
                      {
                        'type': 'indicator',
                        'label': 'Battery charge',
                        'bind': 'charge',
                        'min': 0,
                        'max': 100,
                        'unit': '%',
                      },
                      {
                        'type': 'slider',
                        'label': 'Screen brightness',
                        'bind': 'brightness',
                        'min': 1,
                        'max': 255,
                        'step': 1,
                        'action': 'brightness',
                      },
                    ],
                  },
                ],
              },
              state: {'enabled': true, 'brightness': 120, 'charge': 50},
              brightness: brightness,
              textScale: 1.3,
              layered: layered,
            );
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.byType(Slider));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

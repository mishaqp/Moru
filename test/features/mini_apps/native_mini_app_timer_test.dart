import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/mini_apps/widgets/native_mini_app_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  const screen = {
    'version': 1,
    'components': [
      {'type': 'timer', 'label': 'Remaining', 'bind': 'data.end'},
      {
        'type': 'progress',
        'label': 'Progress',
        'bind': 'data.end',
        'startBind': 'data.start',
      },
    ],
  };

  Future<void> pump(
    WidgetTester tester, {
    Map<String, dynamic> source = screen,
    required Map<String, dynamic> data,
    DateTime Function()? now,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    GlobalKey<NavigatorState>? navigatorKey,
    bool tickers = true,
    Future<void> Function(String, Map<String, dynamic>)? onAction,
  }) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            child: TickerMode(
              enabled: tickers,
              child: NativeMiniAppPanel(
                screen: source,
                state: {'data': data},
                now: now ?? tester.binding.clock.now,
                onAction: onAction ?? (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('countdown and progress update together and clamp at expiry', (
    tester,
  ) async {
    final start = tester.binding.clock.now().millisecondsSinceEpoch;
    var actions = 0;
    var clockReads = 0;
    await pump(
      tester,
      data: {'start': start, 'end': start + 3000},
      now: () {
        clockReads++;
        return tester.binding.clock.now();
      },
      onAction: (_, _) async => actions++,
    );
    expect(find.text('0:00:03'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    final beforeTick = clockReads;
    await tester.pump(const Duration(seconds: 1));
    expect(clockReads, beforeTick + 1);
    expect(find.text('0:00:02'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 3, 0.001),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('0:00:00'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(actions, 0);
  });

  testWidgets('elapsed timer clamps future starts and ticks without actions', (
    tester,
  ) async {
    final start = tester.binding.clock.now().millisecondsSinceEpoch;
    await pump(
      tester,
      source: {
        'version': 1,
        'components': [
          {
            'type': 'timer',
            'label': 'Elapsed',
            'mode': 'elapsed',
            'bind': 'data.start',
          },
        ],
      },
      data: {'start': start + 1000},
    );
    expect(find.text('0:00:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('0:00:02'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid extreme epochs cannot overflow into a negative timer', (
    tester,
  ) async {
    await pump(
      tester,
      source: {
        'version': 1,
        'components': [
          {'type': 'timer', 'label': 'Remaining', 'bind': 'data.end'},
        ],
      },
      data: {'end': 8640000000000000},
      now: () => DateTime.fromMillisecondsSinceEpoch(-8640000000000000),
    );
    expect(find.text('4800000000:00:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing and invalid timestamps remain unavailable without a gauge',
    (tester) async {
      var reads = 0;
      await pump(
        tester,
        data: {'start': 10, 'end': double.infinity},
        now: () {
          reads++;
          return tester.binding.clock.now();
        },
      );
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.text('0:00:00'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final before = reads;
      await tester.pump(const Duration(seconds: 3));
      expect(reads, before);
    },
  );

  testWidgets('pause stops ticks and resume catches up from timestamps', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final start = tester.binding.clock.now().millisecondsSinceEpoch;
    var reads = 0;
    await pump(
      tester,
      data: {'start': start, 'end': start + 10000},
      now: () {
        reads++;
        return tester.binding.clock.now();
      },
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:00:09'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedReads = reads;
    await tester.pump(const Duration(seconds: 4));
    expect(reads, pausedReads);
    expect(find.text('0:00:09'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('0:00:05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = reads;
    await tester.pump(const Duration(seconds: 4));
    expect(reads, disposedReads);
  });

  testWidgets(
    'a covered route stops ticks and returning refreshes the display',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final start = tester.binding.clock.now().millisecondsSinceEpoch;
      var reads = 0;
      await pump(
        tester,
        navigatorKey: navigator,
        data: {'start': start, 'end': start + 10000},
        now: () {
          reads++;
          return tester.binding.clock.now();
        },
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      );
      await tester.pumpAndSettle();
      final hiddenReads = reads;
      await tester.pump(const Duration(seconds: 3));
      expect(reads, hiddenReads);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(reads, greaterThan(hiddenReads));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        greaterThan(0),
      );
    },
  );

  testWidgets('disabled TickerMode creates no live panel ticks', (
    tester,
  ) async {
    final start = tester.binding.clock.now().millisecondsSinceEpoch;
    var reads = 0;
    await pump(
      tester,
      data: {'start': start, 'end': start + 10000},
      tickers: false,
      now: () {
        reads++;
        return tester.binding.clock.now();
      },
    );
    final before = reads;
    await tester.pump(const Duration(seconds: 3));
    expect(reads, before);
  });

  testWidgets('invalid date inputs cannot masquerade as On or Off', (
    tester,
  ) async {
    await pump(
      tester,
      source: {
        'version': 1,
        'components': [
          {
            'type': 'value',
            'label': 'Date',
            'bind': 'data.falseValue',
            'format': 'date',
          },
          {
            'type': 'value',
            'label': 'Time',
            'bind': 'data.trueValue',
            'format': 'time',
          },
          {
            'type': 'value',
            'label': 'Timestamp',
            'bind': 'data.text',
            'format': 'datetime',
          },
          {
            'type': 'value',
            'label': 'Nonfinite date',
            'bind': 'data.infinity',
            'format': 'date',
          },
          {
            'type': 'value',
            'label': 'Missing time',
            'bind': 'data.missing',
            'format': 'time',
          },
        ],
      },
      data: {
        'falseValue': false,
        'trueValue': true,
        'text': 'not-a-date',
        'infinity': double.infinity,
      },
    );
    expect(find.text('Unavailable'), findsNWidgets(5));
    expect(find.text('On'), findsNothing);
    expect(find.text('Off'), findsNothing);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('ru'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('date/time/datetime render timestamp and ISO date in $locale', (
      tester,
    ) async {
      await pump(
        tester,
        locale: locale,
        source: {
          'version': 1,
          'components': [
            {
              'type': 'value',
              'label': 'Date',
              'bind': 'data.stamp',
              'format': 'date',
            },
            {
              'type': 'value',
              'label': 'Time',
              'bind': 'data.stamp',
              'format': 'time',
            },
            {
              'type': 'value',
              'label': 'Date and time',
              'bind': 'data.stamp',
              'format': 'datetime',
            },
            {
              'type': 'value',
              'label': 'Day',
              'bind': 'data.day',
              'format': 'date',
            },
          ],
        },
        data: {
          'stamp': DateTime(2026, 9, 1, 10, 1).millisecondsSinceEpoch,
          'day': '2026-09-01',
        },
      );
      expect(find.text('10:01'), findsOneWidget);
      final month = switch (locale.languageCode) {
        'ru' => 'сент.',
        'zh' => '9月',
        _ => 'Sep',
      };
      expect(find.textContaining(month), findsNWidgets(3));
      expect(find.text('2026-09-01'), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(900, 400)]) {
      testWidgets('timer fits $size with Russian text at 1.3 in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final start = tester.binding.clock.now().millisecondsSinceEpoch;
        await pump(
          tester,
          locale: const Locale('ru'),
          brightness: brightness,
          textScale: 1.3,
          source: {
            'version': 1,
            'components': [
              {
                'type': 'timer',
                'label': {
                  'en': 'Time remaining in this session',
                  'ru': 'Осталось до завершения текущей сессии',
                },
                'bind': 'data.end',
              },
              {
                'type': 'progress',
                'label': 'Выполнение сессии',
                'bind': 'data.end',
                'startBind': 'data.start',
              },
            ],
          },
          data: {'start': start, 'end': start + 1500000},
        );
        expect(find.text('0:25:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('0:24:59'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

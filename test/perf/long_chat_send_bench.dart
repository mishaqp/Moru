import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:Kelivo/features/chat/utils/chat_ui_work.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

import '../support/long_chat_harness.dart';

/// Explicit benchmark, never a timing assertion. Widget tests have no device
/// FrameTiming: time drawFrame (build/layout/paint, excluding raster) and
/// synchronous action + pump separately; keep Flutter's per-phase Timeline.
void main() {
  final binding = _FrameBinding();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installLongChatPlatformStubs();
  });

  testWidgets('long chat open / send / first chunks / tool card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(() => ChatUiWork.debugObserver = null);

    // Prime every scenario on a short chat. Pixel release uses AOT; compiling
    // the first send/stream/tool path in this debug test must not skew the
    // long-history comparison. All subsequent long-chat frames are retained.
    final warmKey = GlobalKey<LongChatHarnessState>();
    await tester.pumpWidget(
      LongChatHarness(key: warmKey, fixture: LongChatFixture(rounds: 3)),
    );
    await tester.pump();
    for (var send = 0; send < 3; send++) {
      warmKey.currentState!.send();
      await tester.pump();
      warmKey.currentState!.goToEnd();
      await tester.pump();
      for (var chunk = 0; chunk < 3; chunk++) {
        warmKey.currentState!.streamChunk();
        await tester.pump();
      }
      warmKey.currentState!.toolCard();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final frames = <_Frame>[];
    Map<String, (int, int)> work = {};
    final builtMessages = <String>{};
    ChatUiWork.debugObserver = (name, id, us) {
      final previous = work[name] ?? (0, 0);
      work[name] = (previous.$1 + 1, previous.$2 + us);
      if (name == 'message.build' && id != null) builtMessages.add(id);
    };

    FlutterTimeline.debugCollectionEnabled = true;
    addTearDown(() => FlutterTimeline.debugCollectionEnabled = false);
    final timelineBlocks = <Map<String, Object?>>[];
    final vm = !const bool.fromEnvironment('CPU_PROFILE')
        ? null
        : await tester.runAsync(() async {
            final uri = (await developer.Service.getInfo()).serverUri;
            if (uri == null) {
              throw StateError('CPU_PROFILE requires --enable-vmservice');
            }
            final service = await vmServiceConnectUri(
              uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
            );
            await service.setVMTimelineFlags(['Dart']);
            await service.clearVMTimeline();
            if (const bool.fromEnvironment('CPU_PROFILE')) {
              await service.setFlag('profiler', 'true');
              await service.clearCpuSamples(
                developer.Service.getIsolateId(Isolate.current)!,
              );
            }
            return service;
          });

    Future<void> frame(
      String scenario,
      VoidCallback action, {
      Widget? mount,
    }) async {
      work = {};
      builtMessages.clear();
      binding.lastBuildUs = 0;
      FlutterTimeline.debugReset();
      final start = developer.Timeline.now;
      final watch = Stopwatch()..start();
      action();
      if (mount == null) {
        await tester.pump(const Duration(milliseconds: 16));
      } else {
        await tester.pumpWidget(mount);
      }
      watch.stop();
      frames.add(
        _Frame(
          scenario,
          start,
          developer.Timeline.now,
          watch.elapsedMicroseconds,
          Map.of(work),
          List.of(builtMessages),
        )..buildUs = binding.lastBuildUs,
      );
      for (final block in FlutterTimeline.debugCollect().timedBlocks) {
        timelineBlocks.add({
          'name': block.name,
          'ph': 'X',
          'ts': block.start,
          'dur': block.duration,
          'pid': 1,
          'tid': 1,
        });
      }
    }

    late LongChatHarnessState state;
    for (var opening = 0; opening < 8; opening++) {
      // A fresh database hydration produces new part identities. Construct
      // them outside the timed frame so open p90 measures cold presentation,
      // without reusing the preceding opening's weak caches.
      final fixture = LongChatFixture();
      final key = GlobalKey<LongChatHarnessState>();
      await frame(
        'open',
        () {},
        mount: LongChatHarness(key: key, fixture: fixture),
      );
      state = key.currentState!;
      await frame('open', state.goToEnd);
      await frame('open', () {});
      if (opening < 7) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
    for (var sending = 0; sending < 12; sending++) {
      await frame('send', state.send);
      await frame('send', state.goToEnd);
      await frame('send', () {});
      for (var chunk = 0; chunk < 3; chunk++) {
        await frame('stream', state.streamChunk);
        await frame('stream', state.goToEnd);
      }
      await frame('tool', state.toolCard);
      await frame('tool', state.goToEnd);
      await frame('tool', () {});
    }

    ChatUiWork.debugObserver = null;
    await tester.runAsync(() async {
      const prefix = String.fromEnvironment(
        'PERF_OUTPUT',
        defaultValue: '/tmp/moru-long-chat',
      );
      await File('$prefix-timeline.json').writeAsString(
        jsonEncode(
          vm != null
              ? (await vm.getVMTimeline()).toJson()
              : {'traceEvents': timelineBlocks},
        ),
      );
      if (vm != null) {
        final cpu = await vm.getCpuSamples(
          developer.Service.getIsolateId(Isolate.current)!,
          0,
          1 << 60,
        );
        await File('$prefix-cpu.json').writeAsString(jsonEncode(cpu.toJson()));
      }
      await File(
        '$prefix-frames.json',
      ).writeAsString(jsonEncode(frames.map((f) => f.toJson()).toList()));
      await vm?.dispose();
    });

    for (final scenario in ['open', 'send', 'stream', 'tool']) {
      final samples =
          frames.where((frame) => frame.scenario == scenario).toList()
            ..sort((a, b) => a.wallUs.compareTo(b.wallUs));
      final build = [
        for (final f in samples)
          if (f.buildUs != null) f.buildUs!,
      ]..sort();
      String ms(int us) => (us / 1000).toStringAsFixed(2);
      // ignore: avoid_print
      print(
        'LONG_CHAT scenario=$scenario frames=${samples.length} '
        'buildMaxMs=${build.isEmpty ? "unavailable" : ms(build.last)} '
        'buildP90Ms=${build.isEmpty ? "unavailable" : ms(build[(build.length * .9).ceil() - 1])} '
        'uiMaxMs=${ms(samples.last.wallUs)} uiP90Ms=${ms(samples[(samples.length * .9).ceil() - 1].wallUs)}',
      );
      for (final worst in samples.reversed.take(3)) {
        // ignore: avoid_print
        print('WORST ${jsonEncode(worst.toJson())}');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _Frame {
  _Frame(
    this.scenario,
    this.start,
    this.end,
    this.wallUs,
    this.work,
    this.messages,
  );
  final String scenario;
  final int start;
  final int end;
  final int wallUs;
  final Map<String, (int, int)> work;
  final List<String> messages;
  int? buildUs;

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'start': start,
    'end': end,
    'uiUs': wallUs,
    'buildUs': buildUs,
    'work': {
      for (final e in work.entries)
        e.key: {'calls': e.value.$1, 'us': e.value.$2},
    },
    'messagesBuilt': messages,
  };
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

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/features/chat/utils/chat_ui_work.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

import '../support/long_chat_harness.dart';
import '../support/send_long_chat_harness.dart';

/// Explicit actual-send benchmark, outside the normal _test.dart glob.
/// Timings contain no assertions. Headless tests cannot report Android raster
/// time: drawFrame measures build/layout/paint; event-loop delay includes any
/// scheduler/GC/IO contention and is not labelled as CPU time.
void main() {
  final binding = _SendFrameBinding();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installLongChatPlatformStubs();
    const background = MethodChannel('app.mobile_background');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(background, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(background, null));
  });

  testWidgets('persisted long chat actual send / prepare / first chunks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(() => ChatUiWork.debugObserver = null);
    addTearDown(() => ChatDatabaseRepository.debugToolEventDecode = null);
    final samples = <_SendSample>[];
    final captured = <Map<String, dynamic>>[];
    const smoke = bool.fromEnvironment('SMOKE');
    const repetitions = int.fromEnvironment('SEND_REPEATS', defaultValue: 20);

    Future<void> driveUntil(bool Function() done, String description) async {
      final deadline = Stopwatch()..start();
      while (!done()) {
        if (deadline.elapsed > const Duration(seconds: 30)) {
          throw StateError('benchmark timed out waiting for $description');
        }
        // IO/provider futures belong to the real async zone. Between these
        // 16 ms turns, pump the scheduled frame at an approximate 60 Hz wall
        // cadence. This sampling time remains in send-to-frame/request times.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> scenario(int rounds, int sends, {required bool retain}) async {
      final environment = (await tester.runAsync(
        () => SendLongChatEnvironment.create(rounds: rounds),
      ))!;
      final key = GlobalKey<SendLongChatHarnessState>();
      await tester.pumpWidget(environment.app(key: key));
      final state = key.currentState!;
      await tester.runAsync(state.open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      Timer? activePulse;

      try {
        for (var send = 0; send < sends; send++) {
          await tester.enterText(find.byType(TextField).first, 'Продолжай.');
          await tester.pump();
          final button = tester.widget<InkWell>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('send')),
                  matching: find.byType(InkWell),
                )
                .first,
          );
          if (button.onTap == null) {
            throw StateError('benchmark send button is disabled');
          }
          final sample = _SendSample(
            send: send,
            fixtureMessages: environment.fixtureMessages,
            fixtureTools: environment.fixtureTools,
            fixtureToolBytes: environment.fixtureToolBytes,
            windowMessages: state.controller.messages.length,
          );
          final repository = environment.repository;
          final previousReads = (
            repository.toolReadCalls,
            repository.toolReadMessages,
            repository.toolReadEvents,
            repository.toolReadUs,
          );
          final requestsBefore = environment.requests.length;
          environment.observer.reset();
          environment.responseHold = Completer<void>();
          environment.onStage = sample.stage;
          binding.sample = sample;
          ChatUiWork.debugObserver = (name, id, us) {
            sample.work(name, id, us);
            if (name == 'message.build' &&
                id == repository.insertedAssistantId) {
              sample.insertedBuiltThisFrame = true;
            }
          };
          ChatDatabaseRepository.debugToolEventDecode = (payloads, us) {
            sample.decodedToolPayloads += payloads;
            ChatUiWork.debugObserver?.call(
              'send.toolEvents.jsonDecode',
              null,
              us,
            );
          };
          Timer? pulse;
          await tester.runAsync(() async {
            sample.timelineStartUs = developer.Timeline.now;
            sample.watch.start();
            var lastPulse = sample.watch.elapsedMicroseconds;
            pulse = Timer.periodic(const Duration(milliseconds: 1), (_) {
              final now = sample.watch.elapsedMicroseconds;
              final delay = now - lastPulse - 1000;
              if (delay > sample.maxEventLoopDelayUs) {
                sample.maxEventLoopDelayUs = delay;
              }
              if ((!sample.firstFrameCompleted ||
                      lastPulse < sample.firstPairFrameUs) &&
                  delay > sample.preFrameEventLoopDelayUs) {
                sample.preFrameEventLoopDelayUs = delay;
              }
              lastPulse = now;
            });
            activePulse = pulse;
            button.onTap!();
          });
          await driveUntil(
            () =>
                environment.requests.length > requestsBefore &&
                sample.firstFrameCompleted,
            'inserted assistant frame and prepared provider request',
          );
          sample.stage('request.and.frame.ready');
          await tester.runAsync(() async => environment.releaseResponse());
          await driveUntil(
            () => !state.controller.isCurrentConversationLoading,
            'first chunks and terminal persistence',
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.runAsync(() async {
            pulse?.cancel();
            sample.watch.stop();
            await state.lastSubmission;
            sample.timelineEndUs = developer.Timeline.now;
          });
          sample.contextMessages = environment.service.contextMessages;
          sample.toolReads = {
            'calls': repository.toolReadCalls - previousReads.$1,
            'messages': repository.toolReadMessages - previousReads.$2,
            'events': repository.toolReadEvents - previousReads.$3,
            'wallUs': repository.toolReadUs - previousReads.$4,
          };
          sample.database = environment.observer.snapshot().toSafeJson();
          environment.onStage = null;
          binding.sample = null;
          ChatUiWork.debugObserver = null;
          ChatDatabaseRepository.debugToolEventDecode = null;
          if (retain) {
            samples.add(sample);
            captured.add(environment.requests.last);
            // ignore: avoid_print
            print(
              'ACTUAL_SEND ${jsonEncode(Map.of(sample.toJson())
                ..remove('frames')
                ..remove('database'))}',
            );
          }
        }
      } finally {
        environment.onStage = null;
        binding.sample = null;
        ChatUiWork.debugObserver = null;
        ChatDatabaseRepository.debugToolEventDecode = null;
        await tester.runAsync(() async => activePulse?.cancel());
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(environment.close);
      }
    }

    // Prime real persistence, preparation, tool history replay and first chunks
    // before retaining long-history samples; every measured frame is retained.
    await scenario(3, smoke ? 1 : 3, retain: false);
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
            await service.setFlag('profiler', 'true');
            await service.clearCpuSamples(
              developer.Service.getIsolateId(Isolate.current)!,
            );
            return service;
          });
    await scenario(smoke ? 3 : 200, smoke ? 1 : repetitions, retain: true);
    const prefix = String.fromEnvironment(
      'PERF_OUTPUT',
      defaultValue: '/tmp/moru-actual-send',
    );
    await tester.runAsync(() async {
      await File(
        '$prefix-samples.json',
      ).writeAsString(jsonEncode(samples.map((s) => s.toJson()).toList()));
      await File('$prefix-requests.json').writeAsString(jsonEncode(captured));
      if (vm != null) {
        await File(
          '$prefix-timeline.json',
        ).writeAsString(jsonEncode((await vm.getVMTimeline()).toJson()));
        final cpu = await vm.getCpuSamples(
          developer.Service.getIsolateId(Isolate.current)!,
          0,
          1 << 60,
        );
        await File('$prefix-cpu.json').writeAsString(jsonEncode(cpu.toJson()));
        await vm.dispose();
      }
    });
    for (final metric in [
      'firstPairFrameUs',
      'providerRequestUs',
      'maxBuildUs',
      'maxSyncWorkUs',
      'maxSyncWorkBeforeFrameUs',
      'maxEventLoopDelayUs',
      'preFrameEventLoopDelayUs',
    ]) {
      final values = [for (final s in samples) s.toJson()[metric] as int]
        ..sort();
      String ms(int us) => (us / 1000).toStringAsFixed(2);
      // ignore: avoid_print
      print(
        'ACTUAL_SEND_SUMMARY metric=$metric samples=${values.length} '
        'p90Ms=${ms(values[(values.length * .9).ceil() - 1])} '
        'maxMs=${ms(values.last)}',
      );
    }
  });
}

class _SendSample {
  _SendSample({
    required this.send,
    required this.fixtureMessages,
    required this.fixtureTools,
    required this.fixtureToolBytes,
    required this.windowMessages,
  });
  final int send;
  final int fixtureMessages;
  final int fixtureTools;
  final int fixtureToolBytes;
  final int windowMessages;
  final watch = Stopwatch();
  final stages = <String, List<int>>{};
  final workSummary = <String, Map<String, int>>{};
  final frames = <Map<String, Object?>>[];
  final builtIds = <String>{};
  var insertedBuiltThisFrame = false;
  var firstFrameCompleted = false;
  var firstPairFrameUs = 0;
  var maxBuildUs = 0;
  var maxSyncWorkUs = 0;
  var maxSyncWorkBeforeFrameUs = 0;
  var maxEventLoopDelayUs = 0;
  var preFrameEventLoopDelayUs = 0;
  var contextMessages = 0;
  var decodedToolPayloads = 0;
  var timelineStartUs = 0;
  var timelineEndUs = 0;
  Map<String, int> toolReads = {};
  Map<String, Object?> database = {};

  void stage(String name) =>
      stages.putIfAbsent(name, () => []).add(watch.elapsedMicroseconds);

  void work(String name, String? id, int us) {
    final summary = workSummary.putIfAbsent(
      name,
      () => {
        'calls': 0,
        'us': 0,
        'maxUs': 0,
        'beforeFrameCalls': 0,
        'beforeFrameUs': 0,
        'beforeFrameMaxUs': 0,
      },
    );
    summary['calls'] = summary['calls']! + 1;
    summary['us'] = summary['us']! + us;
    if (us > summary['maxUs']!) summary['maxUs'] = us;
    if (!firstFrameCompleted) {
      summary['beforeFrameCalls'] = summary['beforeFrameCalls']! + 1;
      summary['beforeFrameUs'] = summary['beforeFrameUs']! + us;
      if (us > summary['beforeFrameMaxUs']!) summary['beforeFrameMaxUs'] = us;
      if (us > maxSyncWorkBeforeFrameUs) maxSyncWorkBeforeFrameUs = us;
    }
    if (us > maxSyncWorkUs) maxSyncWorkUs = us;
    if (name == 'message.build' && id != null) builtIds.add(id);
  }

  Map<String, Object?> toJson() => {
    'send': send,
    'wallFrameCadenceMs': 16,
    'fixtureMessages': fixtureMessages,
    'fixtureTools': fixtureTools,
    'fixtureToolBytes': fixtureToolBytes,
    'windowMessagesBeforeSend': windowMessages,
    'contextMessages': contextMessages,
    'decodedToolPayloads': decodedToolPayloads,
    'timelineStartUs': timelineStartUs,
    'timelineEndUs': timelineEndUs,
    'firstPairFrameUs': firstPairFrameUs,
    'providerRequestUs': stages['provider.request']?.first ?? 0,
    'maxBuildUs': maxBuildUs,
    'maxSyncWorkUs': maxSyncWorkUs,
    'maxSyncWorkBeforeFrameUs': maxSyncWorkBeforeFrameUs,
    'maxEventLoopDelayUs': maxEventLoopDelayUs,
    'preFrameEventLoopDelayUs': preFrameEventLoopDelayUs,
    'stagesUs': stages,
    'work': workSummary,
    'builtMessageCount': builtIds.length,
    'frames': frames,
    'toolReads': toolReads,
    'database': database,
  };
}

class _SendFrameBinding extends AutomatedTestWidgetsFlutterBinding {
  _SendSample? sample;
  @override
  void drawFrame() {
    final current = sample;
    final watch = Stopwatch()..start();
    try {
      super.drawFrame();
    } finally {
      if (current != null) {
        final us = watch.elapsedMicroseconds;
        if (us > current.maxBuildUs) current.maxBuildUs = us;
        current.frames.add({
          'atUs': current.watch.elapsedMicroseconds,
          'buildUs': us,
          'insertedAssistantBuilt': current.insertedBuiltThisFrame,
        });
        if (current.insertedBuiltThisFrame && !current.firstFrameCompleted) {
          current.firstFrameCompleted = true;
          current.firstPairFrameUs = current.watch.elapsedMicroseconds;
        }
        current.insertedBuiltThisFrame = false;
      }
    }
  }
}

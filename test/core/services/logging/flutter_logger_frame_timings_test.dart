import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming _frame({int buildMs = 70, int rasterMs = 80}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: buildMs * 1000,
  rasterStart: buildMs * 1000,
  rasterFinish: (buildMs + rasterMs) * 1000,
  rasterFinishWallTime: 1790985600000000,
);

void _reportFrames(List<FrameTiming> frames) =>
    SchedulerBinding.instance.platformDispatcher.onReportTimings?.call(frames);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => FlutterLogger.setEnabled(false));

  testWidgets('long frames enter the technical journal', (tester) async {
    await FlutterLogger.setEnabled(true);
    final before = FlutterLogger.technicalTail;
    _reportFrames([_frame()]);
    await tester.pump(const Duration(seconds: 1));

    final entry = FlutterLogger.technicalTail.substring(before.length);
    expect(entry, contains('[SlowFrames]'));
    expect(entry, contains('count=1'));
    expect(entry, contains('max_ms=150.0'));
    expect(entry, contains('build_ms=70.0'));
    expect(entry, contains('raster_ms=80.0'));
    expect(entry, matches(RegExp(r'^\[\d{4}-\d{2}-\d{2}T')));
    expect(FlutterLogger.technicalSummary.first, contains('[SlowFrames]'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('frames at or below 100 ms are ignored', (tester) async {
    await FlutterLogger.setEnabled(true);
    final before = FlutterLogger.technicalTail;
    _reportFrames([
      _frame(buildMs: 5, rasterMs: 10),
      _frame(buildMs: 50, rasterMs: 50),
    ]);
    await tester.pump(const Duration(seconds: 2));
    expect(FlutterLogger.technicalTail, before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('slow frames aggregate into at most one entry per second', (
    tester,
  ) async {
    await FlutterLogger.setEnabled(true);
    final before = FlutterLogger.technicalTail;
    _reportFrames([_frame(buildMs: 40, rasterMs: 80)]);
    await tester.pump(const Duration(milliseconds: 500));
    _reportFrames([
      _frame(buildMs: 100, rasterMs: 150),
      _frame(buildMs: 80, rasterMs: 90),
    ]);
    await tester.pump(const Duration(milliseconds: 499));
    expect(FlutterLogger.technicalTail, before);
    await tester.pump(const Duration(milliseconds: 1));
    final first = FlutterLogger.technicalTail.substring(before.length);
    expect(first.split('[SlowFrames]'), hasLength(2));
    expect(first, contains('count=3'));
    expect(first, contains('max_ms=250.0'));
    expect(first, contains('build_ms=100.0'));
    expect(first, contains('raster_ms=150.0'));

    _reportFrames([_frame()]);
    await tester.pump(const Duration(milliseconds: 999));
    expect(FlutterLogger.technicalTail, '$before$first');
    await tester.pump(const Duration(milliseconds: 1));
    final entries = FlutterLogger.technicalTail.substring(before.length);
    expect(entries.split('[SlowFrames]'), hasLength(3));
    expect(entries, contains('count=1'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('disabling Flutter logging cancels pending frame summaries', (
    tester,
  ) async {
    await FlutterLogger.setEnabled(true);
    final before = FlutterLogger.technicalTail;
    _reportFrames([_frame()]);
    await FlutterLogger.setEnabled(false);
    _reportFrames([_frame()]);
    await tester.pump(const Duration(seconds: 2));
    expect(FlutterLogger.technicalTail, before);

    await FlutterLogger.setEnabled(true);
    await FlutterLogger.setEnabled(true);
    _reportFrames([_frame()]);
    await tester.pump(const Duration(seconds: 1));
    final entry = FlutterLogger.technicalTail.substring(before.length);
    expect(entry.split('[SlowFrames]'), hasLength(2));
    expect(entry, contains('count=1'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('slow-frame entries share the technical journal size limits', (
    tester,
  ) async {
    await FlutterLogger.setEnabled(true);
    for (var i = 0; i < 210; i++) {
      _reportFrames([_frame()]);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      '[SlowFrames]'.allMatches(FlutterLogger.technicalTail),
      hasLength(200),
    );
    expect(
      FlutterLogger.technicalTail.length,
      lessThanOrEqualTo(FlutterLogger.technicalTailMaxBytes),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

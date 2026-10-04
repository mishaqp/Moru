import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:Kelivo/core/services/logging/problem_report_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SettingsProvider settings;
  late ProblemReportService reports;
  late Map<String, Object?> device;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('moru-report-test-');
    final harness = await createBusinessTestHarness(
      initial: {
        'user_name_v1': 'PRIVATE_USER_SENTINEL',
        'memory_prompt_en_v1': 'PRIVATE_CHAT_SENTINEL',
      },
    );
    settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    device = {'android': '16', 'sdk': 36, 'model': 'Test Phone'};
    reports = ProblemReportService(
      supportDirectory: () async => Directory('${root.path}/support'),
      cacheDirectory: () async => Directory('${root.path}/cache'),
      appInfo: () async => {'version': '0.1.47', 'build': '48'},
      deviceInfo: () async => device,
    );
    addTearDown(() async {
      settings.dispose();
      await root.delete(recursive: true);
    });
  });

  test(
    'ZIP contains technical data and no chat, requests or custom text',
    () async {
      const chat = 'PRIVATE_CHAT_SENTINEL';
      await settings.setSpendLimits(const SpendLimits(chatTokens: 100));
      final spendLine = SpendControlStatus(
        chat: const ChatTokenSummary(
          input: 80,
          output: 0,
          cached: 0,
          replies: 1,
        ),
        today: const ChatTokenSummary(
          input: 80,
          output: 0,
          cached: 0,
          replies: 1,
        ),
        limits: settings.spendLimits,
        day: DateTime(2026, 10, 4),
      ).systemWarning!;
      final logs = await Directory(
        '${root.path}/support/logs',
      ).create(recursive: true);
      for (final name in ['logs.txt', 'context_logs.txt', 'flutter_logs.txt']) {
        await File('${logs.path}/$name').writeAsString('$chat\n$spendLine');
      }
      FlutterLogger.logPrint(chat);
      FlutterLogger.logPrint(spendLine);
      FlutterLogger.recordTechnicalError(StateError(chat), StackTrace.empty);
      final result = await reports.create(settings: settings);
      final name = result['name'] as String;
      final bytes = await reports.readReport(name);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((file) => file.name), ['report.json', 'events.txt']);
      final text = zip.files
          .map((file) => utf8.decode(file.content))
          .join('\n');
      expect(text, contains('0.1.47'));
      expect(text, contains('Test Phone'));
      expect(text, contains('StateError'));
      expect(text, isNot(contains(chat)));
      expect(text, isNot(contains('Spend control')));
      expect(text, isNot(contains('spend_limits')));
      expect(text, isNot(contains('PRIVATE_USER_SENTINEL')));
      expect(result['size_bytes'], bytes.length);
      expect(jsonEncode(result), isNot(contains('events.txt\n')));
      expect(result.containsKey('log'), isFalse);

      final workspace = await Directory('${root.path}/workspace').create();
      final access = WorkspaceFileAccess(roots: [workspace.path]);
      await expectLater(
        access.readBytes(result['path'] as String),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
    },
  );

  test(
    'configured primary and rotated search secrets are removed before ZIP',
    () async {
      const primary = 'primary-search-credential-value';
      const rotated = 'rotated-search-credential-value';
      await settings.setSearchServices([
        LinkUpOptions(id: 'test', apiKey: primary, extraApiKeys: [rotated]),
      ]);
      device['model'] = 'Phone $primary $rotated';
      final result = await reports.create(settings: settings);
      final zip = ZipDecoder().decodeBytes(
        await reports.readReport(result['name'] as String),
      );
      final text = zip.files
          .map((file) => utf8.decode(file.content))
          .join('\n');
      for (final secret in [primary, rotated]) {
        expect(text, isNot(contains(secret)));
        expect(jsonEncode(result), isNot(contains(secret)));
      }
    },
  );

  test('MCP private inputs are removed from report data and ZIP', () async {
    const secret = 'PRIVATE_MCP_REPORT_INPUT';
    final mcp = McpProvider(preferences: createBusinessTestPreferences());
    addTearDown(mcp.dispose);
    await mcp.loaded;
    await mcp.importServers([
      McpServerConfig(
        id: 'private',
        enabled: false,
        name: 'Private',
        transport: McpTransportType.http,
        url: 'https://example.test',
        managedSecrets: {'TOKEN': secret},
        headers: {'Authorization': 'Bearer $secret'},
      ),
    ]);
    device['model'] = 'Phone $secret';
    final result = await reports.create(settings: settings, mcp: mcp);
    final zip = ZipDecoder().decodeBytes(
      await reports.readReport(result['name'] as String),
    );
    final text = zip.files.map((file) => utf8.decode(file.content)).join('\n');
    expect(text, isNot(contains(secret)));
    expect(jsonEncode(result), isNot(contains(secret)));
  });

  test('ZIP and uncompressed journal stay bounded', () async {
    for (var i = 0; i < 1000; i++) {
      FlutterLogger.recordTechnicalError(
        StateError('secret $i'),
        StackTrace.fromString(
          List.filled(
            30,
            '#0      run (package:Kelivo/main.dart:42:3)',
          ).join('\n'),
        ),
      );
    }
    final result = await reports.create(settings: settings);
    final bytes = await reports.readReport(result['name'] as String);
    expect(bytes.length, lessThanOrEqualTo(ProblemReportService.maxZipBytes));
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(
      zip.findFile('events.txt')!.size,
      lessThanOrEqualTo(FlutterLogger.technicalTailMaxBytes),
    );
  });

  test('reports include slow-frame summaries without any errors', () async {
    await settings.setFlutterLogEnabled(true);
    addTearDown(() => FlutterLogger.setEnabled(false));
    fakeAsync((clock) {
      SchedulerBinding.instance.platformDispatcher.onReportTimings?.call([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 70000,
          rasterStart: 70000,
          rasterFinish: 150000,
          rasterFinishWallTime: 1790985600000000,
        ),
      ]);
      clock.elapse(const Duration(seconds: 1));
    });
    final result = await reports.create(settings: settings);
    final summary = result['summary'] as Map;
    expect(summary['recent_events'], contains(contains('[SlowFrames]')));
    final zip = ZipDecoder().decodeBytes(
      await reports.readReport(result['name'] as String),
    );
    expect(
      utf8.decode(zip.findFile('events.txt')!.content),
      contains('count=1 max_ms=150.0 build_ms=70.0 raster_ms=80.0'),
    );
  });

  test(
    'sharing copies checked bytes and removes temporary snapshots',
    () async {
      final result = await reports.create(settings: settings);
      final name = result['name'] as String;
      final expected = await reports.readReport(name);
      String? temporary;
      await reports.withShareSnapshot(name, (file) async {
        temporary = file.path;
        expect(file.path, isNot(result['path']));
        expect(await file.readAsBytes(), expected);
      });
      expect(await File(temporary!).exists(), isFalse);
      await expectLater(
        reports.withShareSnapshot(name, (file) async {
          temporary = file.path;
          throw StateError('Share failed');
        }),
        throwsStateError,
      );
      expect(await File(temporary!).exists(), isFalse);
      expect(await File(result['path'] as String).exists(), isTrue);
    },
  );

  test(
    'report symlinks cannot disclose files outside the private directory',
    () async {
      final result = await reports.create(settings: settings);
      final name = result['name'] as String;
      final path = result['path'] as String;
      await File(path).delete();
      final outside = await File(
        '${root.path}/private-chat.txt',
      ).writeAsString('PRIVATE_CHAT_SENTINEL');
      await Link(path).create(outside.path);
      await expectLater(
        reports.readReport(name),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      await expectLater(
        reports.withShareSnapshot(name, (_) async => fail('Must not share')),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      await reports.cleanup(all: true);
      expect(await Link(path).exists(), isFalse);
      expect(await outside.readAsString(), 'PRIVATE_CHAT_SENTINEL');
    },
  );

  test(
    'startup removes reports, snapshots and only owned share cache files',
    () async {
      final result = await reports.create(settings: settings);
      final name = result['name'] as String;
      final cache = await Directory(
        '${root.path}/cache/share_plus',
      ).create(recursive: true);
      await File('${cache.path}/$name').writeAsString('report copy');
      final other = await File(
        '${cache.path}/other.zip',
      ).writeAsString('other');
      await reports.cleanup(all: true);
      expect(await File(result['path'] as String).exists(), isFalse);
      expect(await File('${cache.path}/$name').exists(), isFalse);
      expect(await other.exists(), isTrue);
    },
  );

  test(
    'expired reports cannot be read or shared; filenames cannot escape',
    () async {
      final result = await reports.create(settings: settings);
      final file = File(result['path'] as String);
      await file.setLastModified(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      await expectLater(
        reports.readReport(result['name'] as String),
        throwsStateError,
      );
      expect(await file.exists(), isFalse);
      for (final name in ['../other.zip', '/etc/passwd', 'other.zip']) {
        await expectLater(reports.readReport(name), throwsArgumentError);
      }
    },
  );
}

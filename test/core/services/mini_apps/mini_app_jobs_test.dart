import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_check.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_jobs.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

/// The native planner, in memory.
class _Planner {
  final saved = <String, Map<String, Object?>>{};
  final ran = <String>[];
  final state = <String, Map<String, dynamic>>{};

  late final scheduler = MiniAppJobScheduler(
    save: (job) async => saved['${job['id']}'] = job,
    delete: (id) async => saved.remove(id),
    list: (appId) async => [
      for (final entry in saved.entries)
        if (entry.value['appId'] == appId)
          {...entry.value, ...?state[entry.key]},
    ],
    runNow: (id) async => ran.add(id),
  );
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late _Planner planner;
  late MiniAppJobs jobs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-jobs-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
    planner = _Planner();
    jobs = MiniAppJobs(store: store, scheduler: planner.scheduler);
    store.addDeleteHook(jobs.cancelAll);
    final src = Directory(p.join(temp.path, 'src'))..createSync();
    File(
      p.join(src.path, MiniAppStore.manifestFile),
    ).writeAsStringSync(jsonEncode({'id': 'weather', 'name': 'Weather'}));
    File(p.join(src.path, 'index.html')).writeAsStringSync('<p>');
    await store.install(src);
  });
  tearDown(() => temp.delete(recursive: true));

  test('a job is kept with the app and scheduled natively', () async {
    await jobs.set('weather', 'morning', {
      'time': '8:05',
      'days': [5, 1, 1],
      'run': 'checkWeather',
      'title': 'ignored',
    });
    expect(await store.readJobs('weather'), {
      'morning': {
        'time': '08:05',
        'days': [1, 5],
        'run': 'checkWeather',
      },
    });
    expect(planner.saved['miniapp:weather:morning'], {
      'id': 'miniapp:weather:morning',
      'kind': 'miniAppJob',
      'appId': 'weather',
      'jobId': 'morning',
      'run': 'checkWeather',
      'hour': 8,
      'minute': 5,
      'weekdays': [1, 5],
    });

    // Every day unless days are given.
    await jobs.set('weather', 'evening', {'time': '20:00', 'run': 'sum'});
    expect(planner.saved['miniapp:weather:evening']!['weekdays'], [
      1, 2, 3, 4, 5, 6, 7, //
    ]);

    await jobs.remove('weather', 'morning');
    expect(planner.saved.keys, ['miniapp:weather:evening']);
    expect((await store.readJobs('weather')).keys, ['evening']);
  });

  test('invalid jobs are refused and nothing is scheduled', () async {
    for (final (id, raw) in <(String, Object?)>[
      ('morning', {'time': '8:00'}),
      ('morning', {'time': '8:00', 'run': 'alert("x")'}),
      ('morning', {'time': '25:00', 'run': 'go'}),
      (
        'morning',
        {
          'time': '8:00',
          'run': 'go',
          'days': [0],
        },
      ),
      ('bad id!', {'time': '8:00', 'run': 'go'}),
      ('morning', 'every day'),
    ]) {
      await expectLater(
        jobs.set('weather', id, raw),
        throwsA(isA<MiniAppException>()),
        reason: '$id $raw',
      );
    }
    for (var i = 0; i < MiniAppJobs.maxJobs; i++) {
      await jobs.set('weather', 'job$i', {'time': '8:00', 'run': 'go'});
    }
    await expectLater(
      jobs.set('weather', 'one-more', {'time': '8:00', 'run': 'go'}),
      throwsA(
        isA<MiniAppException>().having((e) => e.code, 'code', 'too_many_jobs'),
      ),
    );
    expect(planner.saved, hasLength(MiniAppJobs.maxJobs));
  });

  test('the list shows next and last runs from the planner', () async {
    await jobs.set('weather', 'morning', {'time': '08:00', 'run': 'check'});
    planner.state['miniapp:weather:morning'] = {
      'nextRunAt': DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
      'runs': [
        {
          'status': 'failed',
          'startedAt': DateTime(2026, 9, 30, 8).millisecondsSinceEpoch,
          'error': 'check() did not finish within 30 s',
        },
        {'status': 'completed', 'startedAt': 1},
      ],
    };
    final [job] = await jobs.list('weather');
    expect(job.nextRunAt, DateTime(2026, 10, 1, 8));
    expect(job.runs.map((r) => r.status), ['failed', 'completed']);
    expect(job.toJson(), {
      'id': 'morning',
      'time': '08:00',
      'run': 'check',
      'nextRunAt': DateTime(2026, 10, 1, 8).toIso8601String(),
      'lastRun': {
        'status': 'failed',
        'at': DateTime(2026, 9, 30, 8).toIso8601String(),
        'error': 'check() did not finish within 30 s',
      },
    });
  });

  test('stored jobs are scheduled again, e.g. after a restore', () async {
    await jobs.set('weather', 'morning', {'time': '08:00', 'run': 'check'});
    planner.saved.clear();
    // A damaged definition does not stop the others.
    final all = await store.readJobs('weather');
    all['broken'] = {'time': 'soon'};
    await store.writeJobs('weather', all);

    await jobs.rescheduleAll();
    expect(planner.saved.keys, ['miniapp:weather:morning']);
  });

  test(
    'run now needs a defined job; deleting the app unschedules its jobs',
    () async {
      await expectLater(
        jobs.runNow('weather', 'nope'),
        throwsA(
          isA<MiniAppException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
      await jobs.set('weather', 'morning', {'time': '08:00', 'run': 'check'});
      await jobs.runNow('weather', 'morning');
      expect(planner.ran, ['miniapp:weather:morning']);

      await store.delete('weather');
      expect(planner.saved, isEmpty);
    },
  );

  test('planner refusals become errors the app and chat understand', () async {
    final busy = MiniAppJobs(
      store: store,
      scheduler: MiniAppJobScheduler(
        save: (job) async => job['jobId'] == 'refused'
            ? throw PlatformException(code: 'scheduled_task', message: 'x')
            : null,
        delete: (_) async {},
        list: (_) async => const [],
        runNow: (_) async => throw PlatformException(
          code: 'scheduled_task',
          message: 'task_running',
        ),
      ),
    );
    await busy.set('weather', 'morning', {'time': '08:00', 'run': 'check'});
    await expectLater(
      busy.runNow('weather', 'morning'),
      throwsA(
        isA<MiniAppException>().having(
          (e) => e.message,
          'message',
          'The job is already running.',
        ),
      ),
    );
    await expectLater(
      busy.set('weather', 'refused', {'time': '08:00', 'run': 'check'}),
      throwsA(
        isA<MiniAppException>().having(
          (e) => e.code,
          'code',
          'schedule_failed',
        ),
      ),
    );
  });

  test(
    'the bridge sets, lists and removes jobs and tells a background run',
    () async {
      final bridge = MiniAppBridge(
        store: store,
        appId: 'weather',
        host: MiniAppHost(jobs: jobs, background: true),
      );
      Future<Object?> call(String method, [Map<String, Object?>? args]) async {
        final script = (await bridge.handle(
          jsonEncode({'id': 1, 'method': method, 'args': args ?? {}}),
        ))!;
        final match = RegExp(
          r'^window\.__moruReply\(1, (true|false), (.*)\);$',
        ).firstMatch(script)!;
        expect(match[1], 'true', reason: script);
        return jsonDecode(match[2]!);
      }

      await call('jobs.set', {
        'id': 'morning',
        'job': {'time': '07:30', 'run': 'check'},
      });
      expect(await call('jobs.list'), [
        {'id': 'morning', 'time': '07:30', 'run': 'check'},
      ]);
      await call('jobs.remove', {'id': 'morning'});
      expect(await call('jobs.list'), isEmpty);
      expect(await call('app.info'), containsPair('background', true));
    },
  );

  test('the mini_apps tool lists and starts jobs', () async {
    await jobs.set('weather', 'morning', {'time': '08:00', 'run': 'check'});
    Future<Map<String, dynamic>> tool(Map<String, dynamic> args) async =>
        jsonDecode(
              await MiniAppDataTool(store: store, jobs: jobs).execute(args),
            )
            as Map<String, dynamic>;

    final listed = await tool({'action': 'jobs', 'app_id': 'weather'});
    expect(listed['jobs'], [
      {'id': 'morning', 'time': '08:00', 'run': 'check', 'runs': []},
    ]);
    final started = await tool({
      'action': 'run_job',
      'app_id': 'weather',
      'job': 'morning',
    });
    expect(started['ok'], isTrue, reason: '$started');
    expect(planner.ran, ['miniapp:weather:morning']);
    final missing = await tool({
      'action': 'run_job',
      'app_id': 'weather',
      'job': 'nope',
    });
    expect(missing['error'], 'not_found');
    // Without jobs, e.g. in another host, the actions say so.
    final unavailable = jsonDecode(
      await MiniAppDataTool(
        store: store,
      ).execute({'action': 'jobs', 'app_id': 'weather'}),
    );
    expect(unavailable['error'], 'unavailable');
  });

  test('jobs the page set in the publish check are scheduled for the '
      'installed app', () async {
    final sandbox = await MiniAppSandbox.create(store.byId('weather')!);
    addTearDown(sandbox.dispose);
    // What the page does on start inside the check.
    for (final id in ['morning', 'alert']) {
      final reply = await sandbox.bridge.handle(
        jsonEncode({
          'id': 1,
          'method': 'jobs.set',
          'args': {
            'id': id,
            'job': {'time': '07:30', 'run': 'check'},
          },
        }),
      );
      expect(reply, startsWith('window.__moruReply(1, true, '));
    }
    expect(await store.readJobs('weather'), isEmpty);
    expect(planner.saved, isEmpty);

    expect(await sandbox.adoptJobs(jobs), ['alert', 'morning']);
    expect((await store.readJobs('weather')).keys, {'alert', 'morning'});
    expect(planner.saved.keys, {
      'miniapp:weather:alert',
      'miniapp:weather:morning',
    });
    // So the agent can run one right after publishing.
    await jobs.runNow('weather', 'morning');
    expect(planner.ran, ['miniapp:weather:morning']);
    expect(
      const MiniAppCheckReport(
        loaded: true,
        scheduledJobs: ['alert', 'morning'],
      ).toJson()['jobs_scheduled'],
      ['alert', 'morning'],
    );
  });

  test('the mini_apps tool deletes a job and an app, after approval', () async {
    Future<Map<String, dynamic>> tool(Map<String, dynamic> args) async =>
        jsonDecode(
              await MiniAppDataTool(store: store, jobs: jobs).execute(args),
            )
            as Map<String, dynamic>;
    await jobs.set('weather', 'morning', {'time': '08:00', 'run': 'check'});

    for (final action in ['delete', 'delete_job']) {
      expect(
        LocalToolNames.requiresApprovalFor('mini_apps', {'action': action}),
        isTrue,
      );
    }
    for (final action in ['list', 'jobs', 'run_job', 'write', 'rollback']) {
      expect(
        LocalToolNames.requiresApprovalFor('mini_apps', {'action': action}),
        isFalse,
        reason: action,
      );
    }

    final missing = await tool({
      'action': 'delete_job',
      'app_id': 'weather',
      'job': 'nope',
    });
    expect(missing['error'], 'not_found');

    final job = await tool({
      'action': 'delete_job',
      'app_id': 'weather',
      'job': 'morning',
    });
    expect(job, {'ok': true, 'deleted_job': 'morning'});
    expect(await store.readJobs('weather'), isEmpty);
    expect(planner.saved, isEmpty);

    await jobs.set('weather', 'evening', {'time': '20:00', 'run': 'check'});
    final app = await tool({'action': 'delete', 'app_id': 'weather'});
    expect(app, {'ok': true, 'deleted': 'weather'});
    expect(store.byId('weather'), isNull);
    expect(planner.saved, isEmpty);
    expect(
      Directory(p.join(temp.path, 'installed', 'weather')).existsSync(),
      isFalse,
    );
  });
}

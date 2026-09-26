import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_fetch.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-3-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<MiniApp> install(Map<String, dynamic> manifest) async {
    final dir = Directory(p.join(temp.path, 'src'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync();
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({'id': 'weather', 'name': 'W', ...manifest}),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync('<p>x</p>');
    return (await store.install(dir)).app;
  }

  Future<Map<String, dynamic>> call(
    MiniAppBridge bridge,
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final script = await bridge.handle(
      jsonEncode({'id': 1, 'method': method, 'args': args}),
    );
    final match = RegExp(
      r'^window\.__moruReply\(1, (true|false), (.*)\);$',
    ).firstMatch(script!)!;
    return {'ok': match[1] == 'true', 'value': jsonDecode(match[2]!)};
  }

  group('manifest', () {
    test('network hosts and permissions are kept and reloaded', () async {
      await install({
        'network': ['API.Open-Meteo.com', '*.example.org'],
        'permissions': ['calendar'],
      });
      final reloaded = MiniAppStore(
        root: () async => Directory(p.join(temp.path, 'installed')),
      );
      await reloaded.load();
      final app = reloaded.byId('weather')!;
      expect(app.network, ['api.open-meteo.com', '*.example.org']);
      expect(app.permissions, {'calendar'});
    });

    test('bad network or permissions are refused', () async {
      for (final bad in [
        {'network': 'api.example.com'},
        {
          'network': ['https://api.example.com'],
        },
        {
          'network': ['api.example.com/path'],
        },
        {
          'network': ['*'],
        },
        {
          'permissions': ['camera'],
        },
      ]) {
        await expectLater(
          install(bad),
          throwsA(isA<MiniAppException>()),
          reason: '$bad',
        );
      }
    });

    test('wildcards allow subdomains and the domain itself only', () async {
      final app = await install({
        'network': ['*.example.org', 'api.test.com'],
      });
      expect(MiniAppStore.allowsHost(app, 'a.b.example.org'), isTrue);
      expect(MiniAppStore.allowsHost(app, 'example.org'), isTrue);
      expect(MiniAppStore.allowsHost(app, 'API.test.com'), isTrue);
      expect(MiniAppStore.allowsHost(app, 'badexample.org'), isFalse);
      expect(MiniAppStore.allowsHost(app, 'test.com'), isFalse);
      expect(MiniAppStore.allowsHost(app, 'api.test.com.evil.io'), isFalse);
    });
  });

  group('moru.fetch', () {
    test('reaches listed hosts and returns status, headers and body', () async {
      final app = await install({
        'network': ['api.example.com'],
      });
      final requests = <http.Request>[];
      final fetch = MiniAppFetch(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"t": 21}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = await fetch.fetch(app, {
        'url': 'https://api.example.com/v1?q=1',
        'method': 'post',
        'headers': {'X-Key': 'k'},
        'body': '{"a":1}',
      });
      expect(result['status'], 200);
      expect(result['ok'], isTrue);
      expect(result['body'], '{"t": 21}');
      expect((result['headers'] as Map)['content-type'], 'application/json');
      expect(requests.single.method, 'POST');
      expect(requests.single.headers['X-Key'], 'k');
      expect(requests.single.body, '{"a":1}');
    });

    test('other hosts, schemes and methods are refused unsent', () async {
      final app = await install({
        'network': ['api.example.com'],
      });
      var sent = 0;
      final fetch = MiniAppFetch(
        client: MockClient((_) async {
          sent++;
          return http.Response('', 200);
        }),
      );
      for (final args in [
        {'url': 'https://other.com/'},
        {'url': 'file:///etc/hosts'},
        {'url': 'api.example.com/x'},
        {'url': 'https://api.example.com/', 'method': 'TRACE'},
        {'url': 'https://api.example.com/', 'body': 5},
      ]) {
        await expectLater(
          fetch.fetch(app, args),
          throwsA(isA<MiniAppException>()),
          reason: '$args',
        );
      }
      expect(sent, 0);
    });

    test('a redirect to an unlisted host is not followed', () async {
      final app = await install({
        'network': ['api.example.com'],
      });
      final hosts = <String>[];
      final fetch = MiniAppFetch(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://evil.com/steal'},
          );
        }),
      );
      await expectLater(
        fetch.fetch(app, {'url': 'https://api.example.com/'}),
        throwsA(
          isA<MiniAppException>().having(
            (e) => e.code,
            'code',
            'host_not_allowed',
          ),
        ),
      );
      expect(hosts, ['api.example.com']);
    });

    test('redirects inside the list are followed, POST becomes GET', () async {
      final app = await install({
        'network': ['*.example.com'],
      });
      final seen = <String>[];
      final fetch = MiniAppFetch(
        client: MockClient((request) async {
          seen.add('${request.method} ${request.url}');
          if (request.url.host == 'a.example.com') {
            return http.Response(
              '',
              303,
              headers: {'location': 'https://b.example.com/done'},
            );
          }
          return http.Response('done', 200);
        }),
      );
      final result = await fetch.fetch(app, {
        'url': 'https://a.example.com/start',
        'method': 'POST',
        'body': 'x',
      });
      expect(result['body'], 'done');
      expect(result['url'], 'https://b.example.com/done');
      expect(seen, [
        'POST https://a.example.com/start',
        'GET https://b.example.com/done',
      ]);
    });

    test('large responses are refused', () async {
      final app = await install({
        'network': ['api.example.com'],
      });
      final fetch = MiniAppFetch(
        client: MockClient(
          (_) async => http.Response.bytes(
            List.filled(MiniAppFetch.maxResponseBytes + 1, 65),
            200,
          ),
        ),
      );
      await expectLater(
        fetch.fetch(app, {'url': 'https://api.example.com/'}),
        throwsA(
          isA<MiniAppException>().having(
            (e) => e.code,
            'code',
            'response_too_large',
          ),
        ),
      );
    });

    test('the bridge answers the page through the fetcher', () async {
      await install({
        'network': ['api.example.com'],
      });
      final bridge = MiniAppBridge(
        store: store,
        appId: 'weather',
        host: MiniAppHost(
          fetch: MiniAppFetch(
            client: MockClient((_) async => http.Response('hi', 201)),
          ),
        ),
      );
      final ok = await call(bridge, 'fetch', {
        'url': 'https://api.example.com/',
      });
      expect(ok['ok'], isTrue);
      expect((ok['value'] as Map)['status'], 201);
      final refused = await call(bridge, 'fetch', {'url': 'https://x.com/'});
      expect(refused, {
        'ok': false,
        'value': 'x.com is not in "network" of moru-app.json.',
      });
    });
  });

  group('moru.calendar', () {
    test('needs the permission in the manifest', () async {
      await install({});
      var calls = 0;
      final bridge = MiniAppBridge(
        store: store,
        appId: 'weather',
        host: MiniAppHost(
          calendar: (method, args) async {
            calls++;
            return {'events': []};
          },
        ),
      );
      expect(await call(bridge, 'calendar.list'), {
        'ok': false,
        'value': 'Add "permissions": ["calendar"] to moru-app.json.',
      });
      expect(calls, 0);
    });

    test('list and add pass only their own fields', () async {
      await install({
        'permissions': ['calendar'],
      });
      final seen = <String, Map<String, dynamic>>{};
      final bridge = MiniAppBridge(
        store: store,
        appId: 'weather',
        host: MiniAppHost(
          calendar: (method, args) async {
            seen[method] = args;
            return method == 'queryCalendar'
                ? {
                    'events': [
                      {'id': 1, 'title': 'Gym'},
                    ],
                  }
                : {'id': 7};
          },
        ),
      );
      final listed = await call(bridge, 'calendar.list', {
        'range': 'week',
        'query': 'gym',
        'event_id': 5,
      });
      expect(listed['ok'], isTrue);
      expect(listed['value'], {
        'events': [
          {'id': 1, 'title': 'Gym'},
        ],
      });
      final added = await call(bridge, 'calendar.add', {
        'title': 'Run',
        'start': '2026-10-01T08:00:00',
        'reminders': [10],
        'event_id': 5,
      });
      expect(added, {
        'ok': true,
        'value': {'id': 7},
      });
      expect(seen, {
        'queryCalendar': {'range': 'week', 'query': 'gym'},
        'createCalendarEvent': {
          'title': 'Run',
          'start': '2026-10-01T08:00:00',
          'reminders': [10],
        },
      });
    });

    test('device errors reach the page', () async {
      await install({
        'permissions': ['calendar'],
      });
      final bridge = MiniAppBridge(
        store: store,
        appId: 'weather',
        host: MiniAppHost(
          calendar: (method, args) async => {
            'error': 'no_writable_calendar',
            'message': 'No writable calendar.',
          },
        ),
      );
      expect(await call(bridge, 'calendar.add', {'title': 'x'}), {
        'ok': false,
        'value': 'No writable calendar.',
      });
    });
  });
}

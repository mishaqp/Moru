import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late BrowserLibrary library;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('browser-library');
    now = DateTime(2026, 9, 28, 12);
    library = BrowserLibrary(directory: () async => dir, clock: () => now);
  });

  tearDown(() => dir.delete(recursive: true));

  test('history keeps each address once, newest first, and survives a '
      'restart', () async {
    await library.recordVisit('https://a.example/', 'A');
    now = now.add(const Duration(minutes: 1));
    await library.recordVisit('https://b.example/', 'B');
    now = now.add(const Duration(minutes: 1));
    await library.recordVisit('https://a.example/', 'A again');
    await library.recordVisit('about:blank', 'Blank');

    expect([for (final e in library.history.value) e.title], ['A again', 'B']);

    final reopened = BrowserLibrary(
      directory: () async => dir,
      clock: () => now,
    );
    await reopened.load();
    expect(
      [for (final e in reopened.history.value) e.url],
      ['https://a.example/', 'https://b.example/'],
    );
  });

  test('pages older than 7 days leave the history', () async {
    await library.recordVisit('https://old.example/', 'Old');
    now = now.add(const Duration(days: 8));
    await library.recordVisit('https://new.example/', 'New');
    expect(
      [for (final e in library.history.value) e.url],
      ['https://new.example/'],
    );

    final reopened = BrowserLibrary(
      directory: () async => dir,
      clock: () => now,
    );
    await reopened.load();
    expect(reopened.history.value, hasLength(1));
  });

  test('the star toggles a bookmark; removing and clearing work', () async {
    expect(await library.toggleBookmark('https://a.example/', 'A'), isTrue);
    expect(library.isBookmarked('https://a.example/'), isTrue);
    expect(await library.toggleBookmark('https://a.example/', 'A'), isFalse);
    expect(library.bookmarks.value, isEmpty);
    expect(await library.toggleBookmark('file:///etc', 'x'), isFalse);

    await library.toggleBookmark('https://b.example/', 'Bee');
    final saved = jsonDecode(
      File('${dir.path}/bookmarks.json').readAsStringSync(),
    );
    expect(saved, [
      {
        'url': 'https://b.example/',
        'title': 'Bee',
        'time': now.millisecondsSinceEpoch,
      },
    ]);

    await library.recordVisit('https://b.example/', 'Bee');
    await library.recordVisit('https://c.example/', 'Sea');
    await library.removeFromHistory('https://b.example/');
    expect(
      [for (final e in library.history.value) e.url],
      ['https://c.example/'],
    );
    await library.clearHistory();
    expect(library.history.value, isEmpty);
  });

  test('search matches title or address in any case', () {
    final entry = BrowserPageEntry(
      url: 'https://en.wikipedia.org/wiki/Moon',
      title: 'Moon - Wikipedia',
      time: DateTime(2026),
    );
    expect(entry.matches('moon'), isTrue);
    expect(entry.matches('WIKIPEDIA.org'), isTrue);
    expect(entry.matches('mars'), isFalse);
    expect(entry.matches('  '), isTrue);
  });

  test('a damaged file starts over', () async {
    File('${dir.path}/history.json').writeAsStringSync('{not json');
    await library.load();
    expect(library.history.value, isEmpty);
  });

  group('authentication visits', () {
    const parameters = [
      'state',
      'code',
      'device',
      'device_code',
      'user_code',
      'access_token',
      'refresh_token',
      'id_token',
      'token',
      'auth_token',
      'oauth_token',
      'oauth_verifier',
      'code_challenge',
      'code_verifier',
      'client_secret',
    ];
    for (final parameter in parameters) {
      for (final location in ['query', 'fragment']) {
        test('does not save a $parameter $location parameter', () async {
          final separator = location == 'query' ? '?' : '#';
          final url =
              'https://login.example/callback'
              '${separator}theme=dark&$parameter=private-test-value';

          await library.recordVisit(url, 'Private authentication page');
          // A later title update follows the same visit path.
          await library.recordVisit(url, 'Updated authentication title');

          expect(library.history.value, isEmpty);
          expect(await File('${dir.path}/history.json').exists(), isFalse);
          expect(await File('${dir.path}/history.json.tmp').exists(), isFalse);
        });
      }
    }

    const alternateParameters = <String, String>{
      'mixed case query key': '?AcCeSs_ToKeN=private-test-value',
      'percent-encoded query key': '?%73TaTe=private-test-value',
      'camel case fragment key': '#refreshToken=private-test-value',
      'hyphenated fragment key': '#user-code=private-test-value',
      'fragment route query': '#/callback?normal=kept&CoDe=private-test-value',
      'encoded fragment route key': '#/callback?%75ser_code=private-test-value',
      'encoded fragment fields': '#state%3Dprivate-test-value%26theme%3Ddark',
      'empty authentication field': '?normal=kept&code=',
    };
    for (final variant in alternateParameters.entries) {
      test('does not save ${variant.key}', () async {
        await library.recordVisit(
          'https://login.example/callback${variant.value}',
          'Private authentication page',
        );

        expect(library.history.value, isEmpty);
        expect(await File('${dir.path}/history.json').exists(), isFalse);
      });
    }

    const endpoints = <String, String>{
      'Codex device login': 'https://auth.openai.com/codex/device',
      'OpenAI authorization': 'https://auth.openai.com/authorize',
      'OpenAI OAuth authorization': 'https://auth.openai.com/oauth/authorize',
      'Claude subscription login': 'https://claude.com/oauth/authorize',
      'legacy Claude subscription login': 'https://claude.ai/oauth/authorize',
      'Console login': 'https://platform.claude.com/oauth/authorize',
      'legacy Console login': 'https://console.anthropic.com/oauth/authorize',
      'manual Claude callback':
          'https://platform.claude.com/oauth/code/callback',
      'legacy manual Claude callback':
          'https://console.anthropic.com/oauth/code/callback',
      'trailing slash device login': 'https://auth.openai.com/codex/device/',
      'encoded device login path': 'https://auth.openai.com/codex/%64evice',
    };
    for (final endpoint in endpoints.entries) {
      test('does not save ${endpoint.key} without query parameters', () async {
        await library.recordVisit(endpoint.value, 'Sign in');

        expect(library.history.value, isEmpty);
        expect(await File('${dir.path}/history.json').exists(), isFalse);
      });
    }

    test('skipped visits do not alter an existing history file', () async {
      await library.recordVisit('https://normal.example/', 'Normal page');
      final file = File('${dir.path}/history.json');
      final original = await file.readAsString();

      now = now.add(const Duration(minutes: 1));
      await library.recordVisit(
        'https://auth.openai.com/codex/device',
        'Private authentication page',
      );
      await library.recordVisit(
        'https://normal.example/#access_token=private-test-value',
        'Updated authentication title',
      );

      expect(await file.readAsString(), original);
      expect(library.history.value.single.url, 'https://normal.example/');
      expect(library.history.value.single.title, 'Normal page');
    });
  });

  test(
    'ordinary query strings and fragment anchors keep their full address',
    () async {
      const urls = [
        'https://docs.example/article?q=oauth&language=en#authentication',
        'https://docs.example/article?stateful=true&codec=av1#section-2',
        'https://docs.example/oauth/authorize#overview',
        'https://claude.com/help?topic=login#browser',
        'https://auth.openai.com/codex/device-help',
        'https://normal.example/#/article?sort=latest',
      ];
      for (final url in urls) {
        await library.recordVisit(url, 'Normal page');
      }

      expect(library.history.value.map((entry) => entry.url), urls.reversed);
      final reopened = BrowserLibrary(
        directory: () async => dir,
        clock: () => now,
      );
      await reopened.load();
      expect(reopened.history.value.map((entry) => entry.url), urls.reversed);
    },
  );
}

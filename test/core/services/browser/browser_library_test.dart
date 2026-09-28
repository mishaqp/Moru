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
}

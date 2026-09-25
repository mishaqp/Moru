import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/services/model_catalog/model_catalog.dart';

Map<String, dynamic> _model(
  String id, {
  int? context,
  num? input,
  num? output,
  num? cacheRead,
  List<String> modalities = const ['text'],
}) => {
  'id': id,
  'reasoning': true,
  'tool_call': true,
  'modalities': {'input': modalities},
  'limit': {'context': ?context, 'output': 8192},
  'cost': {'input': ?input, 'output': ?output, 'cache_read': ?cacheRead},
};

final _payload = <String, dynamic>{
  // A reseller listed first must not win over the vendor's own entry.
  'reseller': {
    'models': {
      'claude-sonnet-4-5': _model('claude-sonnet-4-5', context: 1, input: 9),
      'qwen/qwen3-max': _model('qwen/qwen3-max', context: 262144, input: 1.2),
    },
  },
  'anthropic': {
    'models': {
      'claude-sonnet-4-5': _model(
        'claude-sonnet-4-5',
        context: 200000,
        input: 3,
        output: 15,
        cacheRead: 0.3,
        modalities: ['text', 'image'],
      ),
    },
  },
};

void main() {
  test('the vendor listing wins and ids are normalized', () {
    final index = ModelCatalog.buildIndex(_payload);
    final claude = index['claude-sonnet-4-5']!;
    expect(claude.contextTokens, 200000);
    expect(claude.inputPrice, 3);
    expect(claude.imageInput, isTrue);
    expect(claude.reasoning, isTrue);
    expect(index['qwen3-max']!.contextTokens, 262144);
    expect(index['qwen3-max']!.hasPrice, isFalse);
  });

  test('lookup strips vendor prefixes, variants and dates', () {
    final catalog = ModelCatalog()
      ..debugSetEntries(ModelCatalog.buildIndex(_payload));
    for (final id in [
      'claude-sonnet-4-5',
      'Anthropic/Claude-Sonnet-4-5',
      'claude-sonnet-4-5:thinking',
      'claude-sonnet-4-5-20250929',
    ]) {
      expect(catalog.lookup(id)?.contextTokens, 200000, reason: id);
    }
    expect(catalog.lookup('unknown-model'), isNull);
  });

  test('cost splits cached prompt tokens and never exceeds the prompt', () {
    const entry = ModelCatalogEntry(
      inputPrice: 3,
      outputPrice: 15,
      cacheReadPrice: 0.3,
    );
    // 800k fresh * $3 + 200k cached * $0.3 + 100k out * $15
    expect(
      entry.cost(input: 1000000, output: 100000, cached: 200000),
      closeTo(2.4 + 0.06 + 1.5, 1e-9),
    );
    expect(
      entry.cost(input: 1000, output: 0, cached: 5000),
      closeTo(1000 * 0.3 / 1e6, 1e-12),
    );
    expect(
      const ModelCatalogEntry(inputPrice: 1).cost(input: 1, output: 1),
      isNull,
    );
  });

  test('refresh caches the index and a new instance reads it', () async {
    final dir = await Directory.systemTemp.createTemp('model-catalog-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/index.json');
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url, ModelCatalog.sourceUri);
      return http.Response(jsonEncode(_payload), 200);
    });
    final now = DateTime(2026, 9, 26, 12);

    final first = ModelCatalog(
      client: client,
      cacheFile: () async => file,
      now: () => now,
    );
    await first.start();
    expect(requests, 1);
    expect(first.lookup('claude-sonnet-4-5')?.contextTokens, 200000);

    // Within a day the cached copy is used without a download.
    final second = ModelCatalog(
      client: client,
      cacheFile: () async => file,
      now: () => now.add(const Duration(hours: 5)),
    );
    await second.start();
    expect(requests, 1);
    expect(second.lookup('claude-sonnet-4-5')?.outputPrice, 15);
    expect(second.updatedAt, now);
  });

  test('a failed download keeps the cached copy', () async {
    final dir = await Directory.systemTemp.createTemp('model-catalog-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/index.json');
    final now = DateTime(2026, 9, 26, 12);
    await ModelCatalog(
      client: MockClient((_) async => http.Response(jsonEncode(_payload), 200)),
      cacheFile: () async => file,
      now: () => now,
    ).start();

    final stale = ModelCatalog(
      client: MockClient((_) async => http.Response('busy', 503)),
      cacheFile: () async => file,
      now: () => now.add(const Duration(days: 2)),
    );
    await stale.start();
    expect(stale.lookup('claude-sonnet-4-5')?.contextTokens, 200000);
    expect(stale.updatedAt, now);
  });

  test('listed tools and image input reach inferred abilities', () {
    addTearDown(() => ModelCatalog.instance.debugSetEntries(const {}));
    const id = 'acme-omni-7';
    final before = ModelRegistry.infer(ModelInfo(id: id, displayName: id));
    expect(before.abilities, isNot(contains(ModelAbility.tool)));
    expect(before.input, isNot(contains(Modality.image)));

    ModelCatalog.instance.debugSetEntries(const {
      id: ModelCatalogEntry(toolCall: true, imageInput: true, reasoning: true),
    });
    final after = ModelRegistry.infer(ModelInfo(id: id, displayName: id));
    expect(after.abilities, contains(ModelAbility.tool));
    expect(after.input, contains(Modality.image));
    expect(after.abilities, isNot(contains(ModelAbility.reasoning)));
  });
}

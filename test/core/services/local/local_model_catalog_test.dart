import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local/local_model_catalog.dart';

void main() {
  test('the Qwen3-0.6B entry carries the exact size and sha256 verified '
      'against Hugging Face\'s own API (see docs/litert-lm-progress.md)', () {
    final entry = LiteRtModelCatalog.byId(
      'litert-community/qwen3-0.6b-dynamic-int4',
    )!;

    expect(entry.isDownloadable, isTrue);
    expect(entry.sizeBytes, 344437808);
    expect(
      entry.sha256,
      'e3e290109da4388d65a17510a0c66af91c8039f52d2c465868dbc43c09a776cf',
    );
    expect(entry.license, 'Apache-2.0');
    expect(
      entry.downloadUrl.toString(),
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
      'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    );
  });

  test(
    'the Gemma3-1B-IT entry is listed as license-gated, import-only -- no '
    'in-app download and no fabricated checksum HF never actually gave us',
    () {
      final entry = LiteRtModelCatalog.byId(
        'litert-community/gemma3-1b-it-q4',
      )!;

      expect(entry.isDownloadable, isFalse);
      expect(entry.downloadUrl, isNull);
      expect(entry.sha256, isNull);
      expect(entry.sizeBytes, 584417280);
      expect(
        entry.repoUrl.toString(),
        'https://huggingface.co/litert-community/Gemma3-1B-IT',
      );
    },
  );

  test('every catalog entry only ever references a genuine .litertlm file, '
      'never a .task (a different, older MediaPipe format some of these repos '
      'also publish)', () {
    for (final entry in LiteRtModelCatalog.entries) {
      expect(entry.fileName, endsWith('.litertlm'));
      if (entry.downloadUrl != null) {
        expect(entry.downloadUrl!.path, endsWith('.litertlm'));
      }
    }
  });
}

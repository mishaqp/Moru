/// The built-in `.litertlm` catalog -- a small, hand-verified list, not a
/// live feed. Every entry's [sizeBytes]/[sha256] was confirmed against
/// Hugging Face's own API (`tree/main`) and a real `HEAD`/`GET` against the
/// download URL before being pinned here; see docs/litert-lm-progress.md
/// ("Verified facts -- model catalog") for exactly how and when.
final class LiteRtCatalogEntry {
  const LiteRtCatalogEntry({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.sizeBytes,
    required this.license,
    required this.contextTokens,
    required this.repoUrl,
    this.downloadUrl,
    this.sha256,
    this.minMemoryGb,
    this.vision = false,
    this.audio = false,
    this.thinking = false,
    this.tools = false,
  });

  /// Stable catalog id, independent of the installed model's own content-
  /// derived id (`litert-<sha256>` -- see `local_model_library.dart`).
  final String id;
  final int? minMemoryGb;
  final bool vision;
  final bool audio;
  final bool thinking;
  final bool tools;

  final String displayName;

  /// The file name as published, also used as the installed file's
  /// `localSourceLabel`.
  final String fileName;

  /// The exact byte size HF's API reports for this file. Compared against
  /// what the server actually sends during download -- a mismatch is a
  /// hard failure, never silently accepted.
  final int sizeBytes;

  /// SPDX-ish short license id/name for display (e.g. "Apache-2.0",
  /// "Gemma").
  final String license;

  final int contextTokens;

  /// The model's own Hugging Face repo page -- shown as an "open" link for
  /// every entry, and the only way forward for a gated one (manual browser
  /// download, then Moru's own import flow).
  final Uri repoUrl;

  /// Null for a license-gated entry: HF withholds the checksum from an
  /// anonymous request to a gated repo (confirmed empirically -- see the
  /// progress log), so there is nothing honest to pin. A gated entry is
  /// listed for awareness only; [downloadUrl] is also null and the catalog
  /// UI points the user at a manual browser download + Moru's own import
  /// flow instead of an in-app fetch.
  final String? sha256;

  /// Public, unauthenticated, direct download URL. Null for a gated entry
  /// (see [sha256]).
  final Uri? downloadUrl;

  bool get isDownloadable => downloadUrl != null && sha256 != null;
}

abstract final class LiteRtModelCatalog {
  // Verified 2026-09-21: Gallery 6353707 model_allowlists/1_0_19.json,
  // HF revision metadata and HEAD. Gemma 3n/3 require manual license access.
  static final List<LiteRtCatalogEntry> entries = List.unmodifiable([
    LiteRtCatalogEntry(
      id: 'litert-community/gemma-4-E2B-it-litert-lm',
      displayName: 'Gemma-4-E2B-it',
      fileName: 'gemma-4-E2B-it.litertlm',
      sizeBytes: 2588147712,
      license: 'Gemma',
      contextTokens: 32000,
      minMemoryGb: 8,
      vision: true,
      audio: true,
      thinking: true,
      tools: true,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'),
      sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
      downloadUrl: Uri.parse('https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/6e5c4f1e395deb959c494953478fa5cec4b8008f/gemma-4-E2B-it.litertlm'),
    ),
    LiteRtCatalogEntry(
      id: 'litert-community/gemma-4-E4B-it-litert-lm',
      displayName: 'Gemma-4-E4B-it',
      fileName: 'gemma-4-E4B-it.litertlm',
      sizeBytes: 3659530240,
      license: 'Gemma',
      contextTokens: 32000,
      minMemoryGb: 12,
      vision: true,
      audio: true,
      thinking: true,
      tools: true,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm'),
      sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
      downloadUrl: Uri.parse('https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/28299f30ee4d43294517a4ac93abd6163412f07f/gemma-4-E4B-it.litertlm'),
    ),
    LiteRtCatalogEntry(
      id: 'litert-community/qwen3-0.6b-dynamic-int4',
      displayName: 'Qwen3-0.6B · int4',
      thinking: true,
      fileName: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
      sizeBytes: 344671744,
      license: 'Apache-2.0',
      contextTokens: 4096,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/Qwen3-0.6B'),
      downloadUrl: Uri.parse(
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/a3c5d805ae362dff7f580bc25f2dfb9a5a7eaa76/'
        'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
      ),
      sha256:
          '03e7da1eb1108b50dffaa9bb52cc7bcbad2eb0c66ca990267f480c1e545d2856',
    ),
    LiteRtCatalogEntry(
      id: 'litert-community/gemma3-1b-it-q4',
      displayName: 'Gemma3-1B-IT',
      fileName: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
      sizeBytes: 584417280,
      license: 'Gemma',
      contextTokens: 4096,
      repoUrl: Uri.parse(
        'https://huggingface.co/litert-community/Gemma3-1B-IT',
      ),
      // Gated: no in-app download, see the class doc above.
    ),
    LiteRtCatalogEntry(
      id: 'google/gemma-3n-E2B-it-litert-lm',
      displayName: 'Gemma-3n-E2B-it',
      fileName: 'gemma-3n-E2B-it-int4.litertlm',
      sizeBytes: 3655827456,
      license: 'Gemma',
      contextTokens: 4096,
      minMemoryGb: 8,
      vision: true,
      audio: true,
      thinking: false,
      tools: false,
      repoUrl: Uri.parse('https://huggingface.co/google/gemma-3n-E2B-it-litert-lm'),
      sha256: '2ed7bc3a0026c93d5b8a4544b352d9d00cd66ff0bac3ef6a20ac3d2cba4010d6',
    ),
    LiteRtCatalogEntry(
      id: 'google/gemma-3n-E4B-it-litert-lm',
      displayName: 'Gemma-3n-E4B-it',
      fileName: 'gemma-3n-E4B-it-int4.litertlm',
      sizeBytes: 4919541760,
      license: 'Gemma',
      contextTokens: 4096,
      minMemoryGb: 12,
      vision: true,
      audio: true,
      thinking: false,
      tools: false,
      repoUrl: Uri.parse('https://huggingface.co/google/gemma-3n-E4B-it-litert-lm'),
      sha256: '2e67a6cd51dfe0f793431e6bd4ed8d029c88e10f52ca0469ad38445e3cd3c1f4',
    ),
    LiteRtCatalogEntry(
      id: 'litert-community/Qwen2.5-1.5B-Instruct',
      displayName: 'Qwen2.5-1.5B-Instruct',
      fileName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      sizeBytes: 1597931520,
      license: 'Apache-2.0',
      contextTokens: 4096,
      minMemoryGb: 6,
      vision: false,
      audio: false,
      thinking: false,
      tools: false,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct'),
      sha256: 'faa60663b333290c1496c499828b21d3e3254a788cacd8cce917ce0f761a2dc9',
      downloadUrl: Uri.parse('https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/19edb84c69a0212f29a6ef17ba0d6f278b6a1614/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm'),
    ),
    LiteRtCatalogEntry(
      id: 'litert-community/DeepSeek-R1-Distill-Qwen-1.5B',
      displayName: 'DeepSeek-R1-Distill-Qwen-1.5B',
      fileName: 'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      sizeBytes: 1833451520,
      license: 'MIT',
      contextTokens: 4096,
      minMemoryGb: 6,
      vision: false,
      audio: false,
      thinking: true,
      tools: false,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B'),
      sha256: '69b35f01759eed765641ab4af589bbe98131fd2825662a086d9037409b8c1295',
      downloadUrl: Uri.parse('https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/e34bb88632342d1f9640bad579a45134eb1cf988/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm'),
    ),
  ]);

  static LiteRtCatalogEntry? byId(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

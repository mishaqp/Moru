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
  });

  /// Stable catalog id, independent of the installed model's own content-
  /// derived id (`litert-<sha256>` -- see `local_model_library.dart`).
  final String id;

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
  static final List<LiteRtCatalogEntry> entries = List.unmodifiable([
    LiteRtCatalogEntry(
      id: 'litert-community/qwen3-0.6b-dynamic-int4',
      displayName: 'Qwen3-0.6B',
      fileName: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
      sizeBytes: 344437808,
      license: 'Apache-2.0',
      contextTokens: 4096,
      repoUrl: Uri.parse('https://huggingface.co/litert-community/Qwen3-0.6B'),
      downloadUrl: Uri.parse(
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
      ),
      sha256:
          'e3e290109da4388d65a17510a0c66af91c8039f52d2c465868dbc43c09a776cf',
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
  ]);

  static LiteRtCatalogEntry? byId(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

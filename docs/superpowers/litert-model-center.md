# LiteRT model center: implementation record

User authorized implementation from supplied screenshots: local model downloads, catalog, settings and LiteRT-LM 0.17.1 features. Base: 02d4be6, isolated branch codex/litert-model-center. Do not merge PR36 or publish a stable release.

Constraints: AGENTS.md, Android arm64 only, preserve identity/chats/PRoot/MCP. Verify APIs from SDK v0.17.1. Existing tool approval/execution handlers remain authoritative.

1. Runtime worker: optional localBackend/localMaxNumTokens/localTemperature/localTopK/localTopP/localThinking/localThinkingBudget/localVision/localAudio/localTools/localKeepLoaded settings; reload on engine config changes; media/reasoning/tool channels; storageInfo availableBytes/totalMemoryBytes; tests.
2. Root: fix safe downloader partial paths and range validation; immutable verified catalog; Hugging Face URL resolution; library metadata preservation; model cards and settings; localization and tests.
3. Format/static verification, independent review, draft PR and existing GitHub CI. Physical-device inference is not claimed by passing CI.

Previous uncommitted scratch checkout disappeared during a runtime reset. Restoring code from the session record. No earlier implementation was published.
Local Flutter bootstrap was rejected by automatic approval because it attempted cloud metadata access. Do not retry or bypass this. Downloading an exact Dart archive for offline formatting is independent; use GitHub Actions for Flutter/package/native build execution.

## Verification targets
- Slash-containing catalog IDs and malformed resume ranges.
- Immutable HF revisions, hash/size validation, gated downloads.
- Imported model settings preserved through reimport.
- Backend/context changes reload; normal messages reuse engine.
- Media/tool/think features connected end to end, not only toggles.
- Existing analyzer/tests/l10n/ARM64 gates.

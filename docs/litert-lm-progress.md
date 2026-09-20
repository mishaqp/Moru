# LiteRT-LM local provider — progress log

Working notes for the "Локальные модели · LiteRT" integration. Branch:
`feature/litert-lm-local-provider`, based on `master` at `e1644f7` (post
v0.1.13 release). Kept separate from the browser Ask-AI work (v0.1.12/v0.1.13)
— no overlap.

## Status: research phase complete, starting Moru architecture read

## Verified facts (not guessed) — LiteRT-LM SDK

Verified by cloning `google-ai-edge/litert-lm` at tag `v0.17.1` (commit
`5e58e9a`, tagged 2026-09-16) and reading the actual Kotlin source under
`kotlin/java/com/google/ai/edge/litertlm/`, plus fetching the real Maven
metadata/POM/AAR from `dl.google.com` directly (not trusting doc prose alone).

- **Pinned version: `0.17.1`** — confirmed as both the latest GitHub tag *and*
  the `<release>`/`<latest>` in Google Maven's
  `maven-metadata.xml` for `com.google.ai.edge.litertlm:litertlm-android`
  (`lastUpdated 20260916171957`). This matches the user's prior belief; no
  newer stable release exists. **Do not use `latest.release`** (what the
  getting-started doc shows as a lazy example) — pin
  `com.google.ai.edge.litertlm:litertlm-android:0.17.1` explicitly.
- **AAR contents** (downloaded and unzipped
  `litertlm-android-0.17.1.aar`):
  - `AndroidManifest.xml`: `minSdkVersion="24"`. Moru's Flutter Gradle plugin
    default `flutter.minSdkVersion` is also **24** — no minSdk change needed.
  - Native libs: `jni/arm64-v8a/liblitertlm_jni.so` (~21.8 MB) and
    `jni/x86_64/liblitertlm_jni.so`. We only ship arm64-v8a — matches Moru's
    Android-only arm64 policy, the x86_64 slice is simply unused/excluded by
    our existing `abiFilters`.
  - `liblitertlm_jni.so` LOAD segments are `0x4000`-aligned (16384 = 16 KB) —
    confirmed via `readelf -lW`. 16 KB page-size compliant.
  - POM dependencies: `com.google.code.gson:gson:2.14.0`,
    `org.jetbrains.kotlin:kotlin-reflect:2.4.0`,
    `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0`. Moru's root
    Kotlin Gradle plugin is `2.2.20` (AGP `8.11.1`) — kotlin-reflect 2.4.0 is
    a transitive runtime dep, not our compiler version; Gradle will resolve
    the higher stdlib version project-wide. Flagged as **first thing to
    verify empirically** in vertical slice 1 (does it actually compile/run,
    or does it need the Kotlin plugin bumped?). Do not preemptively bump the
    whole toolchain — only if the build actually fails on this.
- **Existing `packaging { jniLibs { useLegacyPackaging = true } }`** in
  `android/app/build.gradle.kts` (there for the PRoot native libs) — need to
  confirm this doesn't defeat the 16KB alignment of the new .so at APK-build
  time (legacy packaging compresses libs; check the built APK's own
  alignment in slice 1/5, not just the AAR's).

### Kotlin API surface (from `getting_started.md` + direct source read of
`Engine.kt`, `Conversation.kt`, `Session.kt`, `Config.kt`)

- `Engine(EngineConfig(modelPath, backend, visionBackend, audioBackend,
  maxNumTokens, maxNumImages, cacheDir))`. `engine.initialize()` is
  synchronous/blocking (up to ~10s) — **must run off the Flutter/main
  thread**, matches user's requirement. `engine.isInitialized()`,
  `engine.close()` (throws `IllegalStateException` if not initialized, or if
  called twice).
- `Backend.CPU(threadCount)` (default), `Backend.GPU()`, `Backend.NPU(nativeLibraryDir)`,
  `Backend.GOOGLE_TENSOR()`. GPU requires
  `<uses-native-library android:name="libvndksupport.so" android:required="false"/>`
  and `libOpenCL.so` declared in `<application>` — these are **system**
  native libs (not bundled by the AAR), `required="false"` so install isn't
  blocked on devices without them. **We are not doing NPU** in this scope
  (user's explicit scope: no guaranteed NPU acceleration by Snapdragon name)
  — CPU is the baseline, GPU is opt-in after a real health check.
- `engine.createConversation(ConversationConfig(systemInstruction,
  initialMessages, samplerConfig, tools, automaticToolCalling, channels,
  extraContext, loraConfig, prefillPrefaceOnInit, maxOutputToken,
  thinkingConfig, enableResponseFormat))` → `Conversation`.
- **History/context mechanism — the ONE mechanism we will use everywhere:**
  `Conversation` has **no message-edit/remove API** (checked: only
  `sendMessage`/`sendMessageAsync`/`cancelProcess`/`getBenchmarkInfo`/
  `getTokenCount`/`renderMessageIntoString`/`renderPrefaceIntoString`/
  `close`). The only supported way to seed or rewind history is
  `ConversationConfig.initialMessages` at `createConversation()` time. So:
  - One native `Conversation` per active Moru chat session, created once
    with `initialMessages` = that conversation's persisted history (minus
    the in-flight turn) + `systemInstruction`.
  - Consecutive turns in the *same* unchanged conversation reuse the *same*
    `Conversation` object (matches the SDK's own terminal-chat example,
    which loops `sendMessageAsync` on one conversation) — never re-append
    the whole history into an already-populated conversation.
  - Switching chat, regenerating, or editing an older message all
    **recreate** the `Conversation` (`close()` the old one first, per the
    cancel-then-close ordering below) with fresh `initialMessages` truncated/
    corrected to the right point. This is the one consistent rule for all
    three cases the task calls out.
  - `conversation.getTokenCount(): Int` gives a *real* token count we can use
    internally for context-budget decisions — not surfaced as fabricated
    "usage" in the UI, per the user's constraint, but legitimate to use for
    our own overflow avoidance logic since it's a real SDK value.
- **Streaming**: `conversation.sendMessageAsync(contents): Flow<Message>`
  (recommended) or the callback form. Internally the Flow wraps
  `MessageCallback` via `callbackFlow { ... awaitClose {} }`.
- **Cancellation — the critical, previously-unverified fact:**
  `conversation.cancelProcess()` (also on `Session`) calls
  `LiteRtLmJni.nativeConversationCancelProcess(handle)` — a **real native
  call**, not just a Kotlin-side flag. No-op if nothing is running; throws
  `IllegalStateException` if the conversation isn't alive. On cancellation
  the native layer returns `StatusCode::kCancelled` (code 1), which the JNI
  callback wrapper turns into a `CancellationException` delivered through
  `onError` (and thus through the Flow's `close(throwable)`).
  **Confirmed by direct source read: `Conversation.sendMessageAsync`'s
  `callbackFlow { ... awaitClose {} }` has an EMPTY `awaitClose` block.**
  This means simply cancelling the Kotlin coroutine/Flow collector (e.g. the
  Dart side stops listening) does **NOT** call `cancelProcess()` and does
  **NOT** stop native inference — exactly the trap the task brief warned
  about. **Our Stop button must explicitly call `conversation.cancelProcess()`**
  as its own bridge command; cancelling the Flow alone is not real cancellation.
  There is a noted upstream limitation (`b/450903294`) that
  `cancelProcess()` does not roll back internal state — treat a cancelled
  conversation's turn as "cut short", not "as if it never happened".
- **Close ordering**: neither `Engine.close()` nor `Conversation.close()` is
  documented/guarded against a concurrent in-flight `sendMessageAsync` call
  on that same conversation — `Engine`'s internal lock only protects
  Kotlin-side engine-handle bookkeeping, not a conversation's native call in
  flight. Our bridge must: call `cancelProcess()` → wait for the Flow to
  actually terminate (onDone/onError) → only then `close()` the
  conversation/engine. Never call close() while a `sendMessageAsync` is
  still active.
- **Multi-modality / tools**: `Content.ImageBytes/ImageFile/AudioBytes/
  AudioFile`, `ToolSet`/`@Tool`/`OpenApiTool` all exist in this SDK version
  but are **out of scope** per the task brief (text-only v1, no images/audio,
  no unconfirmed function calling) — noted so nobody "discovers" these APIs
  later and assumes they were meant to be wired up now.
- **Error handling**: `LiteRtLmJniException` from the native layer, or
  standard Kotlin exceptions (`IllegalStateException` for lifecycle misuse).

## Verified facts — model catalog (for vertical slice 4)

Verified via Hugging Face's public API (`huggingface.co/api/models/...` and
`.../tree/main`), not guessed. `litert-community` is Google's own org
publishing `.litertlm` files (confirmed via `library_name: litert-lm` in
each repo's card metadata).

- **Primary catalog entry — non-gated, in-app downloadable:**
  `litert-community/Qwen3-0.6B`, file
  `Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm`.
  - License: `apache-2.0` (repo `gated: false` — confirmed via the API, no
    HF auth needed to fetch).
  - Size: **344,437,808 bytes** (exact, from HF's tree API `size` field).
  - SHA-256: **`e3e290109da4388d65a17510a0c66af91c8039f52d2c465868dbc43c09a776cf`**
    (HF's `lfs.oid` for this file — git-lfs's default hash is sha256; this
    is HF's own published value, visible because the repo is not gated).
  - Per the repo's own README: dynamic INT4 (block-32) weights, float
    KV-cache, context **4096** tokens, "incorporates LiteRT-LM GPU graph
    optimizations... configured with static prefill memory allocation."
    Base model: Qwen/Qwen3-0.6B (Qwen3, 0.6B params).
  - Download URL pattern (public, unauthenticated):
    `https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm`
    — to be verified with a real `HEAD`/ranged `GET` request in slice 4
    before wiring it into the downloader (confirm `Accept-Ranges`, `ETag`,
    actual `Content-Length` match the API's reported size).
  - **No claim made about Russian-language quality** — Qwen3 is a
    multilingual base model but we have not run it; the catalog entry will
    say "многоязычная модель" at most, never "хорошо работает на русском"
    without an actual test.
- **Secondary catalog entry — license-gated, import-only (not in-app
  download) for v1:** `litert-community/Gemma3-1B-IT`, file
  `Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm`.
  - `gated: "auto"` confirmed via the API — requires an HF account that has
    accepted the Gemma license. Confirmed empirically: an **unauthenticated**
    request to this repo's `tree/main` returns the file's real `size`
    (**584,417,280 bytes**) but its `lfs.oid` (checksum) and `xetHash` come
    back **redacted** (`"****...."`) — i.e. HF itself withholds the
    checksum from anonymous callers for a gated repo. We cannot honestly
    publish a checksum we were never actually given.
  - Decision: **do not attempt an in-app anonymous download of this file.**
    List it in the catalog as license-gated (Gemma license, HF login
    required), point the user to download it manually (browser, logged into
    HF, license accepted) and then use Moru's own SAF **import** flow —
    exactly the "explicit gating, no bypass, keep import path" requirement
    from the task brief. If/when Moru ever supports an HF token, this could
    upgrade to in-app download; out of scope now.
  - This is also the exact model used as the demo in LiteRT-LM's own
    `getting_started.md`, so it's a credible "known-good" second entry
    despite being import-only.
- Both files are genuine `.litertlm` (not `.task`, a different/older
  MediaPipe format also present in some of these repos — the catalog must
  only ever reference `.litertlm` siblings, never `.task` ones).
- Third-party published benchmark numbers exist in the Qwen3-0.6B README
  (Samsung/vivo/TECNO devices, LiteRT-LM v0.13.1, various backends) — **not**
  POCO F5 or iQOO 15R, and not measured by us. If cited at all in the final
  report, must be clearly attributed as third-party reference numbers for
  other hardware, never presented as a promise for the user's devices.

- Confirmed via a real `HEAD`/`GET` against
  `https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm`:
  302-redirects to a signed, time-limited CDN URL; final response has
  `accept-ranges: bytes`, `content-length: 344437808` (matches the API size
  exactly), and `etag`/`x-linked-etag` values. **Nuance for the
  downloader**: the CDN response's `etag` is HF's internal "xet hash", not
  the file's sha256 — use it only for the download's own HTTP-level
  resume/Range validation (per-session), and separately verify the
  **downloaded file's actual sha256** against the catalog's pinned
  `e3e29010...` checksum as the final integrity gate before marking a model
  "Установлена". The signed CDN URL is time-limited (`Expires=...`) — always
  re-resolve from the stable `resolve/main/...` URL on resume rather than
  caching the redirect target across a paused download.

### Still to verify empirically in vertical slice 1 (not yet done)
- Whether the AGP 8.11.1 / Kotlin 2.2.20 project actually resolves and
  compiles against `kotlin-reflect:2.4.0` cleanly.
- Whether `useLegacyPackaging = true` changes the 16KB alignment of the
  packaged .so inside the built APK vs. the AAR's own alignment.
- Real device memory headroom on a 12 GB device once engine + KV-cache +
  Moru's own Flutter/Android process overhead are all resident — no
  benchmarking without user consent per the task brief; this is a
  qualitative check only, not a number to promise.
- The exact `.litertlm` catalog model(s) for vertical slice 4 — real
  HuggingFace `litert-community` URL, size, checksum, license, license-gate
  status. Not yet chosen or verified.

## Next
Reading Moru's existing provider/chat architecture (ProviderConfig/Kind,
ModelProvider, ChatApiService, StreamChunk, generation lifecycle/terminal
events, settings/backup, Android channel patterns, GenerationForegroundService)
before writing any integration code.

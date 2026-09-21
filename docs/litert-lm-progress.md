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

## Verified facts — Moru's existing architecture (read directly, via research agent)

Full findings kept in this session's transcript; key decisions extracted here:

1. **`ProviderKind`** (`lib/core/providers/settings_provider.dart:6080`): only
   `openai`/`google`/`claude` exist today. Adding `ProviderKind.local` is
   **safe** for old saved configs — `ProviderConfig.fromJson` already falls
   back via `ProviderKind.values.firstWhere(..., orElse: () =>
   classify(json['id']))` for any unrecognized `providerType` string, and
   `classify()` never throws. A local provider's `ProviderConfig` must always
   pass `explicitType: ProviderKind.local` since nothing infers it from an id
   string.
2. **No provider interface** — `ChatApiService._sendOnce`
   (`chat_api_service.dart:336-515`) is an if/else dispatch by
   `ProviderKind`. Add a 4th branch calling a new top-level
   `sendLiteRtStream(...)` matching the existing per-provider function shape
   (`Stream<StreamChunk> sendXStream(http.Client, ProviderConfig, String
   modelId, List<Map<String,dynamic>> messages, {...})` — unused HTTP-shaped
   params can be ignored). `StreamChunk` is a sealed hierarchy
   (`TextStart/Delta/End`, `Finish`, `Usage`, ...); errors are thrown Dart
   exceptions, not a chunk variant.
3. **Cancellation**: keyed by `conversationId` end-to-end.
   `ChatActions.cancelStreaming` → `ChatApiService.cancelRequest(cid)` cancels
   a Dio `CancelToken` stored in `_activeCancelTokens[cid]`. A local provider
   must thread/observe that same per-request cancel signal and call
   `conversation.cancelProcess()` (see SDK section above) when it fires —
   this is the real Stop path to wire into, not a new mechanism.
4. **No existing single-flight guard** across title-gen/summary-gen/
   suggestions/memory-organize — all independent `unawaited()` background
   calls (`home_view_model.dart`), and title/summary gen falls back to the
   *same* model as the just-finished chat turn if no separate title model is
   configured. **A local single-engine provider needs its own Dart-side
   mutex/queue** serializing all calls into the one in-memory engine —
   nothing in Moru does this for us today. Policy to implement: local calls
   queue behind the active user-facing generation; never run concurrently
   with it, never start a second engine instance.
5. **Backups**: provider config is plain SharedPreferences JSON
   (`provider_configs_v1`), always included — fine, it's small. Model weight
   files must live under an app-data subdirectory **not** added to
   `data_sync.dart`'s `_assetRootNames` whitelist (same treatment the PRoot
   `environment/` rootfs already gets, with the same "not backup data"
   rationale) — automatic exclusion, no special-case code needed.
6. **Platform channel template**: reuse `app.workspace`/`app.workspace/events`
   pattern verbatim (`workspace_channel.dart` Dart side;
   `WorkspacePlugin.kt`/`WorkspaceEvents.kt` Kotlin side) — cached
   thread-pool `runAsync` helper for off-main-thread work + queued
   `EventSink` that buffers events fired before Dart subscribes. New channel
   pair: `app.litert` / `app.litert/events`.
7. **`GenerationForegroundService`** currently declares only
   `foregroundServiceType="dataSync"`, already time-limited per Android
   15+'s FGS execution-time budget (service has an `onTimeout` handler for
   exactly this). **Open decision, not resolved yet**: don't blindly reuse
   `dataSync` for local inference — evaluate whether it fits Play policy for
   on-device compute or whether local generation should instead run without
   a foreground service guarantee (honest "stops when backgrounded" per the
   task brief's fallback instruction) for v1.
8. **UI**: don't bolt onto `add_provider_sheet.dart`/`provider_detail_page.dart`
   (structurally HTTP-provider-specific, 4831 lines of `if (_kind ==
   ProviderKind.openai/google/claude)` branches) — build a dedicated
   "Локальные модели · LiteRT" entry point/page instead (matches how OAuth
   providers already get their own detail page). The generic model picker
   (`model_select_sheet.dart`) needs **zero changes** — it already lists
   every provider's `cfg.models` generically and will show local models
   automatically once the `ProviderConfig` exists with `models: [...]`
   populated, only needs a brand-avatar icon added.

## Next
Starting vertical slice 1: Android native integration (Gradle dependency
pinned to 0.17.1, `app.litert` MethodChannel/EventChannel Kotlin plugin
wrapping Engine/Conversation, minimal load/stream/cancel/close proven to
actually compile and run before any Dart-side chat-pipeline wiring).

## Vertical slice 1 — real compile findings (not theoretical anymore)

- Added `com.google.ai.edge.litertlm:litertlm-android:0.17.1` to
  `android/app/build.gradle.kts`, the `libvndksupport.so`/`libOpenCL.so`
  `<uses-native-library>` entries to `AndroidManifest.xml`, and wrote the
  Kotlin bridge: `LiteRtEvents.kt` (copy of `WorkspaceEvents`' queued-sink
  pattern), `LiteRtEngineManager.kt` (single-threaded command executor,
  `Engine`/`Conversation` lifecycle, cancel-then-await-then-close ordering,
  one CPU→GPU fallback), `LiteRtPlugin.kt` (`app.litert` /
  `app.litert/events` channel pair, mirrors `WorkspacePlugin`). Registered
  in `KelivoApplication.kt` exactly like `workspace`/`deviceTools`.
- **Confirmed real incompatibility** (not the theoretical one flagged
  earlier): compiling with `gradle :app:compileDebugKotlin` failed with
  `Class 'kotlin.Unit' was compiled with an incompatible version of Kotlin.
  The actual metadata version is 2.4.0, but the compiler version 2.2.0 can
  read versions up to 2.3.0` — Gradle's normal dependency resolution bumped
  the whole project's `kotlin-stdlib` to 2.4.0 (litertlm-android's POM
  dependency), breaking compilation of every other Kotlin file too (e.g.
  `WorkspacePlugin.kt`), not just the new code.
  - **Minimal fix applied** (not a toolchain-wide Kotlin bump): added a
    `resolutionStrategy.eachDependency` force in `android/build.gradle.kts`
    pinning `org.jetbrains.kotlin:kotlin-stdlib` and `:kotlin-reflect` back
    to `2.2.20` (our own Kotlin Gradle plugin version) for all subprojects
    — same pattern already used there for `androidx.test:runner`. Justified
    because `kotlin-reflect` is only needed by litertlm-android's
    `ToolSet`/`@Tool` reflection-based tool definitions, which are unused
    (text-only v1, no tools).
  - **Open risk, to watch for at runtime** (not just compile time): if
    litertlm-android's own compiled bytecode calls a `kotlin-stdlib` API
    only added in 2.3/2.4, downgrading could throw `NoSuchMethodError` at
    runtime despite compiling fine. Real device/emulator generation must be
    watched for this specifically, not assumed safe from a clean compile
    alone.
- Local dev-environment notes (not project changes): needed
  `android/local.properties` `sdk.dir=/home/user/android-sdk` and
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` env vars for Gradle's
  `compileFlutterBuildDebug` step to find the SDK in this sandbox — already
  handled correctly by CI's `android-actions/setup-android@v3` step, not a
  project file change.

## Vertical slice 1 — RESULT: real compile success

Root cause was not the transitive `kotlin-stdlib` bump alone -- `litertlm-
android-0.17.1`'s own published classes (`Conversation`, `Engine`,
`Backend`, ...) carry Kotlin 2.4.0 metadata directly. No transitive-pin
trick fixes that; the project's own Kotlin compiler must be able to read
2.4.0 metadata. **Actual minimal fix**: bumped
`org.jetbrains.kotlin.android` in `android/settings.gradle.kts` from
`2.2.20` to **`2.4.0`** (the exact version litertlm-android itself was
built with, not the newest available `2.4.20` -- picked the minimal
sufficient version, not the latest).

`gradle :app:compileDebugKotlin --no-daemon -Dorg.gradle.jvmargs=-Xmx3g`
→ **BUILD SUCCESSFUL**, all 475 tasks, including the new `com.psyche.
kelivo.litert` package (`LiteRtEvents.kt`, `LiteRtEngineManager.kt`,
`LiteRtPlugin.kt`) compiling cleanly against the real published SDK
classes -- only pre-existing unrelated deprecation warnings. This is real
proof the API signatures used (`Engine`, `EngineConfig`, `Backend.CPU()`/
`GPU()`, `Conversation`, `ConversationConfig`, `Message.user/model/system/
tool`, `Contents.of`, `SamplerConfig`, `MessageCallback`,
`conversation.cancelProcess()`, `CancellationException`) are all real and
correctly typed -- not guessed.

(Dev-environment note, first Gradle daemon run crashed/OOM'd mid-build in
this sandbox under full module compilation load -- unrelated to the code,
resolved with `--no-daemon` + a bounded heap for the retry.)

**Not yet possible to verify in this sandbox**: no Android device/emulator
here to actually load a real `.litertlm` file and prove streaming/cancel/
unload at runtime. Compile-correctness is proven; runtime behavior (the
open risk noted above -- downgraded/upgraded stdlib API surface actually
working, GPU fallback actually firing, cancelProcess() actually halting
generation observably) is deferred to a real device per the task's own
process (section 14: finish code + checks + APK, hand off for the one
mandatory real-device smoke test before stable release).

## Next
Vertical slice 2: wire the Kotlin bridge into Moru's Dart chat pipeline --
`ProviderKind.local`, `app.litert` Dart-side channel wrapper, a new
`sendLiteRtStream` dispatched from `ChatApiService._sendOnce`, threading
the existing conversationId-keyed cancel signal through to `cancel`, and a
Dart-side single-flight queue serializing local-model calls (main chat +
title/summary/suggestions/memory-organize all potentially racing the one
in-memory engine).

## Vertical slice 2 — Dart-side wiring (in progress)

Added:
- `ProviderKind.local` to the enum (`settings_provider.dart`). Confirmed
  safe for old saved configs (existing `fromJson` fallback via `classify()`
  already handles an unrecognized `providerType` string, per the
  architecture research). `dart analyze` found 12 non-exhaustive-switch
  compile errors across 11 files touching `ProviderKind` -- each one
  reviewed individually and given a deliberate case (mostly `false`/empty
  for capabilities the local provider doesn't have in v1: xhigh/max
  reasoning, built-in search, tool schemas; `provider_detail_page.dart`/
  `share_provider_sheet.dart`/`desktop/providers_pane.dart` cases are
  unreachable in practice since the local provider gets its own dedicated
  entry points, kept exhaustive only). `dart analyze --fatal-infos lib test
  integration_test` is clean.
- `lib/core/services/local/litert_channel.dart` -- Dart-side typed client
  over `app.litert`/`app.litert/events`, mirrors `WorkspaceChannel`.
- `lib/core/services/local/local_model_runtime.dart` -- the Dart-side
  single-flight queue + conversation-reuse decision logic. Key design:
  since every provider (local included) receives the *full* current
  message history on every `ChatApiService.sendMessageStream` call (Moru's
  own message-builder assembles it, not an incremental delta), the runtime
  detects "is this a pure continuation of the conversation the native
  engine already has loaded" by comparing the new call's history (minus
  its trailing new user turn) against what was stored after the *previous*
  successful turn (which includes that previous turn's own assistant
  reply, appended once streaming finishes) -- an exact prefix match reuses
  the existing native `Conversation` (fast path, KV-cache intact); anything
  else (different conversationId, edited/regenerated history, mismatched
  content) recreates it via `initialMessages`. This is deliberately the
  *one* mechanism for switch/regenerate/edit-old-message the task asked for,
  not three special cases.
- `lib/core/services/api/providers/litert_local.dart` -- `sendLiteRtStream`,
  reads `modelPath`/`backend` from
  `config.modelOverrides[modelId]['localModelPath'/'localBackend']` (the
  model-management UI in slice 3 will populate these; not yet built).
- `chat_api_service.dart`: `kind == ProviderKind.local` now short-circuits
  *before* any `http.Client`/OAuth/proxy/cancelToken-bridging code runs --
  confirmed by placing the branch before `_clientFor`/`authenticatedClient`
  are even constructed, not just choosing not to use them.
- Threaded `conversationId` into `_sendOnce` (previously not a parameter)
  so the local branch has a stable per-chat identity; `sessionToken`
  (already a `_sendOnce` parameter) is reused as-is for cancellation --
  `sendLiteRtStream` races `sessionToken.whenCancel` and calls
  `LiteRtChannel.cancel(requestId)`, which reaches
  `Conversation.cancelProcess()` on the Kotlin side.

**Bug caught before it shipped**: while writing `LocalModelRuntime`'s own
tests, found that `_runGenerate` never actually called
`_channel.sendMessage(...)` -- it registered the request id and went
straight to awaiting events that would never arrive. Fixed (wrapped in a
try/catch that cleans up `_byRequestId`/the controller and rethrows on a
synchronous send failure, matching the "don't leave the caller hanging"
rule from the task brief). This is exactly the kind of thing the task's
own emphasis on real tests (not just a clean compile) exists to catch.

New tests: `test/core/services/local/litert_channel_test.dart` (channel
encode/decode/error-mapping, same style as `workspace_channel_test.dart`)
and `local_model_runtime_test.dart` (streaming order, cancellation,
conversation reuse vs. recreate incl. the regenerate case, single-flight
queueing, one-load-not-reloaded). **Status: written, first
`flutter test` run still in progress / not yet confirmed green** -- this
sandbox's flutter test startup has taken 1-3 minutes before on a cold
build cache; continuing to verify before committing further slices.

## Next (after confirming these tests pass)
Still needed for a complete slice 2: wiring `LocalModelRuntime.unload()`
into somewhere sensible (manual "Выгрузить из памяти" UI action -- slice
5), and deciding whether/how the background title/summary/suggestions/
memory-organize calls should skip themselves entirely when the local
engine is mid-user-generation rather than just queuing behind it
indefinitely (queuing is implemented; an explicit "skip if it would make
the user wait too long" policy is not yet decided). Then slice 3 (import +
model management UI, which is what actually populates
`modelOverrides[...]['localModelPath']`).

## Vertical slice 2 — RESULT: real deadlock caught and fixed by the new tests

The first `flutter test` run of `local_model_runtime_test.dart` hung on
every single test (30s timeout each). Debug prints traced it precisely:
all native events (`textDelta`/`done`) were correctly delivered into the
per-request `StreamController`, and the `await for (final event in
events.stream)` loop correctly received them -- but execution never
returned from processing the terminal `LiteRtDone`/`LiteRtError` event.

**Root cause**: the `LiteRtDone`/`LiteRtError` case bodies did
`await events.close();` -- but that code runs *inside* the very
`await for` loop that is `events.stream`'s own listener. A
`StreamController.close()`'s returned future only completes once the
stream has finished notifying its listener that it's done; since the
listener (this same callback) was blocked awaiting that future, it could
never reach the point where the "done" notification would actually be
delivered to itself. Classic self-deadlock. **Fix**: `unawaited(events.
close())` instead -- the bare call still closes the controller (ending
the `await for` on its next iteration once this event's processing
returns), without waiting on a future that can only resolve after this
callback returns.

This is exactly why the task brief insisted on real tests over a clean
compile: `dart analyze` and a successful `gradle :app:compileDebugKotlin`
both passed while this bug was live; only actually exercising the stream
end-to-end caught it.

After the fix: all 12 tests in `test/core/services/local/` pass --
`litert_channel_test.dart` (4) and `local_model_runtime_test.dart` (8:
streaming order, mid-stream cancellation, genuine native error, reuse on
pure continuation, recreate on conversation switch, recreate on
regenerate, single-flight queueing across two overlapping `generate()`
calls, load-once-not-reloaded). `dart analyze --fatal-infos lib test
integration_test` clean. The `ProviderKind.local`-exclusion in
`chat_api_custom_request_precedence_test.dart` confirmed: exactly the 3
HTTP kinds (openai/google/claude) run, local correctly skipped.
Full `flutter test` run in progress to check for regressions elsewhere
before committing.

## Vertical slice 2 — full regression run result

Full `flutter test` (6004 tests) surfaced 3 failures, 1 real (caused by
this diff, now fixed) and 2 pre-existing/unrelated:

- **Real, fixed**: `tool_handler_service_test.dart`'s tuple-form-fan-out
  test iterates `for (final kind in ProviderKind.values)` to check tool
  schema sanitization generically -- now that `.values` includes `local`,
  it hit `ToolHandlerService`'s new `case ProviderKind.local: allowed =
  const {};` (tool calling is out of scope for the local provider, so its
  sanitizer intentionally empties a schema down to nothing). Fixed the
  same way as the earlier `chat_api_custom_request_precedence_test.dart`
  fix: excluded `.local` from that one loop with a comment, since the test
  is inherently about tool-schema shaping for providers that use tools.
- **Pre-existing, unrelated** (confirmed by re-running in isolation,
  neither file touched by this diff):
  - `desktop_process_runtime_test.dart`: "cancel kills the process tree
    including child sleep" -- fails even standalone in this sandbox
    ("child still alive after cancellation"), a real-process
    SIGTERM/SIGKILL delivery timing issue specific to this container, not
    something introduced here (unrelated subsystem: desktop workspace
    process/PTY execution).
  - `chat_input_bar_attachment_cleanup_test.dart`: relies on `chmod 0555`
    to simulate a permission failure, which this sandbox's root user
    bypasses (same root cause identified in the prior browser-feature
    session).

After the fix: `dart analyze --fatal-infos lib test integration_test`
clean; `tool_handler_service_test.dart` 14/14 pass;
`chat_api_custom_request_precedence_test.dart` 3/3 pass;
`test/core/services/local/` 12/12 pass.

## Next
Vertical slice 3: model import (Android SAF `content://` picker, copy
into a private app-data directory outside cache, `.litertlm` vs. GGUF
format check, progress/cancel for a large copy) and a minimal local model
management page/entry point in Settings -- this is what actually
populates `ProviderConfig.modelOverrides[modelId]['localModelPath']` that
`sendLiteRtStream` already reads.

## Vertical slice 3 — import backend (in progress)

- **Real format validation, not extension-only**: confirmed via the
  LiteRT-LM C++ source itself (`runtime/util/file_format_util.cc`,
  `GetFileFormatFromFileContents`) that a genuine `.litertlm` file's first
  8 bytes are the literal ASCII string `"LITERTLM"`, and a GGUF file's
  first 4 bytes are `"GGUF"`. `lib/core/services/local/local_model_import.dart`
  checks these real magic bytes before trusting any imported file --
  rejects GGUF with a distinct reason (`ggufNotSupported`) from "not
  LiteRT-LM at all" (`notLiteRtLmFormat`), and a `.litertlm`-named file
  that isn't really one is caught the same way (extension alone proves
  nothing, per the task brief).
- `importLocalModelFile` streams (never buffers the whole file in memory)
  into a `.part` sibling, only renaming to the final name once the full
  stream is written and validated -- a reader can never observe a
  half-written file at the final path. Polls `isCancelled` between chunks
  and cleans up the partial file on cancel or on a stream error (rethrown
  after cleanup).
- `AppDirectories.getLocalModelsDirectory()` -- `<appData>/litert_models`,
  same tier as `environment/` (outside cache, never added to
  `data_sync.dart`'s `_assetRootNames` backup whitelist -- confirmed no
  code change needed there, it's a fixed allow-list).
- `local_model_library.dart`: keeps a dedicated `ProviderConfig` (key
  `litert-local`, `providerType: ProviderKind.local`) whose `models`/
  `modelOverrides` list installed models -- reuses `SettingsProvider.
  deleteModels` (already handles clearing per-assistant/per-chat model
  selections) rather than reinventing that bookkeeping. `deleteModel`
  refuses (throws `LocalModelLibraryException('model_in_use')`, file and
  config left untouched) when an injectable `isPathInUse` predicate says
  the file is the one currently loaded -- defaults to checking
  `LocalModelRuntime.instance.loadedModelPath` in production, injectable
  in tests.
- 17 new tests (`local_model_import_test.dart` 11, `local_model_library_test.dart`
  6), all passing on first real run (no debugging needed this time -- the
  earlier deadlock lesson was applied: this module has no
  StreamController-closes-itself pattern). Full `test/core/services/local/`
  now 29/29.

## Next
Wire the SAF file pick into this backend
(`FilePicker.platform.pickFiles(withReadStream: true)` -- confirmed via the
installed `file_picker: ^10.3.10` package's own source that `PlatformFile.
readStream`/`.size` exist for exactly this "stream a large picked file
without loading it into memory" case, and this is the same package Moru's
own backup-import flow already uses, so no new dependency/pattern), then
the "Локальные модели · LiteRT" settings page (Каталог/Установленные/
Импортировать) and its entry point in the provider list.

## Vertical slice 3 — UI wired in (import + installed list + delete)

- `lib/features/provider/pages/local_models_page.dart`: `LocalModelsPage`,
  a `StatefulWidget` following the existing `SectionCard`/Lucide/theme-token
  patterns (no Material `Icons.*`). Installed-models list with delete (and
  an empty state), a "Каталог" section that's honestly a
  `localModelsCatalogComingSoon` placeholder (slice 4 fills this in --
  no fake catalog rows), and an import button.
  - Import: `FilePicker.platform.pickFiles(type: FileType.custom,
    allowedExtensions: ['litertlm'], withReadStream: true)`, a
    non-dismissible progress dialog (`ValueListenableBuilder` over
    `LocalModelImportProgress`, real byte counts, a cancel button that
    flips an `isCancelled` flag the import loop polls), then
    `importLocalModelFile` into `AppDirectories.getLocalModelsDirectory()`
    and, on success, `LocalModelLibrary.registerInstalledModel`. Every
    `LocalModelImportRejectReason` (gguf/format/no-stream) and the
    cancelled/success outcomes each get their own localized snackbar --
    no generic "import failed".
  - Delete: confirmation dialog, catches `LocalModelLibraryException`
    (the `model_in_use` case) and shows `localModelsDeleteInUseError`
    instead of silently failing or deleting a file still loaded.
- **Entry point**: `providers_page.dart`'s static `_providers()` catalog
  gets one more row (`kLocalModelProviderKey` = `'litert-local'`, name
  `l10n.localModelsProviderName`) so the provider is visible before any
  model is ever imported (unlike a real provider config, which
  `getProviderConfig` only materializes on first read/write -- confirmed
  this row's `enabled: false` initial state is cosmetic only, since
  `_ProviderRow` always re-reads `cfg.enabled` fresh from settings, not
  the static list's own field).
  - **Deliberately routes on `provider.keyName == kLocalModelProviderKey`,
    not on `cfg.providerType == ProviderKind.local`**: before the first
    import, no `ProviderConfig` exists yet for this key, so
    `getProviderConfig` falls through to `ProviderConfig.defaultsFor`,
    whose `classify()` has no substring match for `litert-local` and
    silently returns `ProviderKind.openai` for the *unpersisted, read-only*
    default it hands back for display. Routing on `providerType` would
    have sent a first-time user into the generic OpenAI-style
    `ProviderDetailPage` instead of `LocalModelsPage`. Routing on the key
    is correct in both the pre-import and post-import state and needed no
    change to `classify()`/`defaultsFor()`'s existing exhaustive `.local`
    branch (which stays correctly marked "unreachable in practice" --
    still true, since real local configs are only ever created explicitly
    by `LocalModelLibrary.registerInstalledModel`, never inferred from a
    typed key).
- **Found and fixed a real i18n bug while wiring this in**:
  `LocalModelLibrary.registerInstalledModel`'s fallback `ProviderConfig`
  (created on first-ever import) hardcoded `name: 'Локальные модели ·
  LiteRT'`. `providers_page.dart` prefers `cfg.name` over the static
  list's localized `provider.name` whenever `cfg.name` is non-empty, so
  after a single import the row's displayed name would have frozen to
  Russian regardless of the app's language (en/zh users would see
  Cyrillic text). Fixed by leaving `name: ''`, which makes every render
  path correctly fall back to `l10n.localModelsProviderName` again.
- Verification: `dart analyze --fatal-infos lib test integration_test` --
  clean. `flutter test test/core/services/local/` -- 29/29 pass (unchanged
  by the i18n fix; no test asserted the old hardcoded name). Full
  `flutter test` run in progress; will record the result before this
  slice's commit.

## Next
Full-suite `flutter test` confirmation, commit this UI slice, then decide
and note the two still-open design questions before slice 4 (verified
catalog + resumable download): the background-task (title-gen etc.)
skip/defer policy against the single-flight local queue, and the
`GenerationForegroundService` service-type fit for long local inference.

## Full-suite confirmation + hardening pass (before catalog/download)

Full `flutter test` run against the slice 3 UI commit surfaced two real
regressions (both from this branch's own diff, fixed and reverified with a
second full run, exit code 0 both times):

- `business_shared_preferences_static_gate_test.dart` does a literal
  `\bSharedPreferences\b` text scan across `lib/**/*.dart` -- a doc comment
  in `local_model_library.dart` used that word in prose and tripped it.
  Reworded to name `SettingsProvider` instead (no code change; the class
  never touches SharedPreferences directly, same as before).
- `moru_catalog_validator_test.dart` rejects an RU string identical to its
  EN source without an explicit technical-exception entry.
  `localModelsBackendCpuLabel`/`GpuLabel` ("CPU"/"GPU") are genuinely
  untranslated acronyms, same class as the project's existing
  `networkProxyTypeHttp` etc. entries -- added both to
  `tool/moru_ru_technical_allowlist.json`.

Both are real full-suite catches this branch is responsible for, not
pre-existing (unlike `desktop_process_runtime_test.dart`'s SIGTERM-timing
failure and `chat_input_bar_attachment_cleanup_test.dart`'s `chmod 0555`
failure, both sandbox-specific and reproducing identically without any
change from this branch, previously confirmed in isolation).

### Runtime-verified provider isolation (not just loop exclusion)

`ProviderKind.local` was already excluded from the generic HTTP-request-
precedence and tool-schema test loops with a comment explaining why. That
documents the claim but doesn't prove it executes correctly. Added
dedicated tests that actually run the real code path:

- `test/core/services/api/chat_api_local_provider_isolation_test.dart`
  (new): drives a full local generation through the real public entry
  point, `ChatApiService.sendMessageStream`, with the native engine
  mocked at the platform-channel level (same technique as
  `litert_channel_test.dart`). The `ProviderConfig`'s `baseUrl` points at
  a real bound `HttpServer` that fails the test if it ever receives a
  connection -- proves no HTTP request is built, which is also the
  runtime precondition for OAuth mattering at all (`ProviderOAuthService
  .resolve`/`authenticatedClient` are cheap no-ops unless a request is
  actually sent through the wrapped client; a local `ProviderConfig` never
  sets `oauthProvider` in the first place, so `config.isOAuth` is false
  and `resolve()`'s very first line returns early). The same call passes
  a non-trivial `tools` schema and an `onToolCall` that fails the test if
  invoked, proving the local branch neither forwards tool definitions to
  the engine nor calls back into tool handling.
- `tool_handler_service_test.dart`: added a direct test asserting
  `sanitizeToolParametersForProvider(schema, ProviderKind.local)` strips
  *every* top-level key (not just the one payload shape the excluded loop
  test happened to assert on).
- `builtin_tools_search_test.dart`: added a direct test asserting
  `supportsSearch`/`supportsBuiltInSearchForModel` both return `false` for
  `ProviderKind.local`, even when a model override explicitly requests
  search.
- `test/features/model/widgets/model_edit_state_helper_local_tools_test.dart`
  (new): `ModelBuiltInToolTiles.forConfig` returns an empty list for a
  local config -- no built-in-tool toggle (search, code execution, etc.)
  is ever offered in the model edit sheet for an on-device model.

## Magic bytes prove the header, not compatibility -- what actually
## happens when a header-valid file is corrupt or unloadable

Re-read the pinned `v0.17.1` source (still cloned at
`/home/user/google-ai-edge/litert-lm`) specifically to answer this,
rather than assuming the Dart-side header check is a substitute for real
SDK validation. Findings:

- **Native format detection trusts the file *extension* first, content
  second**: `runtime/util/file_format_util.cc`'s `GetFileFormat(path,
  scoped_file)` — "Trust the extension of the file path, if it matches a
  known format" — returns `FileFormat::LITERT_LM` for any `*.litertlm`
  path *without inspecting contents at all*; the magic-byte check
  (`GetFileFormatFromFileContents`) only runs as a fallback when there's
  no recognized extension. This means the native side's own first-stage
  dispatch would NOT catch a `.litertlm`-named file with a different or
  garbage format on its own -- confirms the Dart-side
  `local_model_import.dart` magic-byte check (which does inspect real
  content, unconditionally) is not redundant with anything native does
  at this stage, and existing code comments already correctly scope it
  as a header/format check, never as "compatibility" (verified: no
  Dart/ARB string in this branch uses "compatib*"/"совместим*" about
  format validation).
- **Past that dispatch, actual parsing is `absl::Status`-based
  throughout**: `BuildLiteRtCompiledModelResources` →
  `BuildModelResourcesFromLitertLmFormat` (both `StatusOr`-returning,
  standard Google C++ error-propagation, not exceptions/asserts) is the
  real LITERT_LM container parser. This is the right pattern for a
  malformed-but-header-valid container to fail as a clean, structured
  error rather than crash -- but it is evidence of good engineering
  practice, not a guarantee: a parsing bug (an unchecked buffer read on
  genuinely adversarial/corrupted bytes) could still misbehave natively,
  and nothing in this repo proves otherwise for every possible malformed
  input.
- **The one boundary that cannot be verified from source at all**:
  `Engine.kt`'s `initialize()` calls `LiteRtLmJni.nativeCreateEngine(...)`
  -- a JNI entry point. The C++/JNI glue that translates an internal
  `absl::Status` failure into either a thrown Java exception or a raw
  native crash is compiled into `liblitertlm_jni.so` and is **not**
  present in the public source tree (only the `.kt`/`.cc` call sites
  are). Whether a genuinely corrupt file throws cleanly or can reach a
  native crash (SIGSEGV) is therefore *not provable by reading source or
  by any Kotlin/Dart-level test* -- exactly the boundary the task brief
  already warned about: a Kotlin `try/catch` cannot be promised to catch
  a native crash. This can only be settled by the already-planned
  on-device manual test with a deliberately corrupted file (see the
  device-verification checklist).
- **What *is* fully verified, at every layer this codebase controls**:
  `LiteRtEngineManager.loadModel` (`android/app/.../litert/
  LiteRtEngineManager.kt`) wraps `Engine.initialize()` in try/catch and
  reports failure via `onResult(Result.failure(...))`;
  `LiteRtPlugin.kt`'s `loadModel` handler turns that into
  `result.error(errorCode(it), it.message, null)` -- a real
  `PlatformException`, never swallowed. `LiteRtChannel._invoke` normalizes
  that into `LiteRtException`. `LocalModelRuntime.generate()`'s
  `_enqueue(...).catchError(...)` delivers it as a normal stream error
  and closes the controller -- no hang. `ChatApiService.sendMessageStream`
  returns the same `Stream<StreamChunk>` shape for every provider, so
  `chat_actions.dart`'s existing `_handleStreamError` (generic, provider-
  agnostic, already shipped) shows it as a normal error message, not a
  frozen screen -- no local-specific UI code needed or added.
  Added a new test,
  `local_model_runtime_test.dart`: "a file the SDK rejects at load time
  ... surfaces as a clean stream error, not a hang", which simulates
  exactly this scenario (the mocked `loadModel` method-channel call
  throws a `PlatformException`, standing in for a real SDK rejection) and
  additionally proves recovery: `loadedModelPath` stays `null` after the
  failure (never mistaken for a loaded model) and a later `generate()`
  call still works normally -- a failed load does not wedge the
  single-flight queue or the runtime's own state permanently.
  `flutter test test/core/services/local/local_model_runtime_test.dart`
  -- 9/9 pass (was 8; this is the new one).

**Honest summary for this item**: everything this codebase is responsible
for (Dart header check, Kotlin catch+propagate, Dart error normalization,
generic chat UI error display) is verified, including by a new automated
test for the load-failure path. What genuinely cannot be verified without
a device is the native JNI boundary's behavior on adversarial/corrupted
*content* specifically (as opposed to a wrong-format file, which the
Dart-side header check already rejects before any file bytes ever reach
the SDK) -- this stays on the device-verification checklist, not claimed
as done here.

## Exact pinned versions (explicit record, not "check the build files")

All of these are literal, exact versions -- no ranges, no
`latest.release`, no floating `+`/`x.x.+` selectors, anywhere in this
branch's build config:

| Component | Version | Where pinned |
|---|---|---|
| `com.google.ai.edge.litertlm:litertlm-android` | `0.17.1` | `android/app/build.gradle.kts` |
| Kotlin Gradle plugin (`org.jetbrains.kotlin.android`) | `2.4.0` | `android/settings.gradle.kts` |
| Android Gradle Plugin (`com.android.application`) | `8.11.1` | `android/settings.gradle.kts` (pre-existing, unchanged by this branch) |
| Gradle distribution | `8.14` (`-all`) | `android/gradle/wrapper/gradle-wrapper.properties` (pre-existing, unchanged) |
| JDK used to build | `21.0.10` (OpenJDK, Ubuntu build) | this sandbox's `java -version`; not itself pinned in the repo, matches AGP 8.11's supported range |

Kotlin `2.4.0` is a deliberate exact match to what `litertlm-android:0.17.1`
was compiled with (its own `.class` files carry Kotlin 2.4.0 metadata,
confirmed by the original compile failure against 2.2.20 -- "compiled
with an incompatible version of Kotlin"), not the newest available
Kotlin release (`2.4.20` at research time) -- the smallest change that
fixes the real, observed error, per the task's own "pin exactly, no
guessing" and "minimal fix" rules.

Left un-pinned, by design: `kotlin-reflect`, `kotlinx-coroutines-android`,
`gson` -- these are transitive dependencies pulled in by
`litertlm-android`'s own POM (`2.4.0`, `1.11.0`, `2.14.0` respectively,
recorded earlier in this log), not depended on directly by Moru. Gradle's
conflict resolution picks the highest version requested across the whole
graph; the next step (full Android build below) is what actually proves
those resolve to versions litertlm-android's own compiled classes are
compatible with, rather than assuming the POM's stated versions win.

## Full Android build (not just `compileDebugKotlin`)

The Kotlin-version fix in slice 1 was only proven against
`gradle :app:compileDebugKotlin` -- one compilation task, not proof the
whole app (every other plugin, the JVM unit test source set, resource
merging, dexing) builds cleanly against Kotlin 2.4.0. Running the full
pipeline now: `flutter build apk --debug --target-platform=android-arm64`
(exercises the complete Gradle build: all plugins' Kotlin compilation,
resource/asset merging, dexing, packaging) plus `gradle :app:
testDebugUnitTest` (the actual JVM/Robolectric-less unit test source set
under `android/app/src/test/`, separate from Flutter's own `flutter test`)
against the Kotlin 2.4.0 + AGP 8.11.1 combination.

(Results recorded below once the build finishes -- see the next entry in
this log.)

## Background-generation queuing policy (closed)

Investigated what actually happens when a background/utility call (title
generation being the concrete, auto-triggered example --
`generateTitleOnFinish: true` fires it right after the user's own reply
finishes) shares the local provider with the user's real chat. Traced the
exact call chain: `home_view_model.dart`'s `_maybeGenerateTitleFor` calls
`ChatApiService.generateText(conversationId: convo.id, ...)` -- **the
same `conversationId` value** the real streaming chat turn uses
(`chat_actions.dart`, both the streaming and non-streaming-output paths).
`LocalModelRuntime`'s reuse/eviction bookkeeping is keyed by exactly that
value. Found two real, distinct issues from this collision, fixed both:

1. **Key collision**: a background call and the real conversation's own
   turns shared one runtime key. In practice `_sameHistory`'s content
   comparison already prevented a background prompt from being *wrongly
   reused as* real conversation content (verified: an empty
   `priorHistory` for a one-shot prompt can never content-match a real
   conversation's non-empty `_lastFullHistory`) -- so this was not a
   silent-data-corruption bug. It was still a real problem: `status()`'s
   `conversationToken` could report a real conversation's id while the
   native context actually held an unrelated background prompt, and nothing
   stopped a future change to the reuse check (e.g. a key-only fast path)
   from turning the theoretical risk into a real one.
2. **Model eviction** (the more serious one): if a background call is
   configured to use a *different* local model than the one already
   loaded (e.g. a separate title-generation model setting), it would
   force-unload the user's actively-loaded chat model to load its own --
   directly violating the task brief's "background tasks must not start a
   second model". `LiteRtEngineManager.kt`'s own doc comment already notes
   model loads can take real time (~10s per `Engine.kt`'s own doc), so this
   would have meant every auto-title-generation with a different local
   title model forces two reloads (evict for title-gen, reload again for
   the user's next real message).

**Fix** (`isConversationTurn` parameter, threaded end to end): added to
`ChatApiService.sendMessageStream`/`generateMessage` (default `false`,
safe for every existing/future one-shot utility caller -- title, summary,
translation, OCR, memory-organize, chat-suggestions) and set to `true`
only at the two call sites in `chat_actions.dart` that stream/return the
actual next turn of a real conversation. `sendLiteRtStream` forwards it
into `LocalModelRuntime.generate` (also defaulting `true`, preserving
every pre-existing call site/test unchanged), which now:
 - routes every `isConversationTurn: false` call through a fixed sentinel
   runtime key (`_utilityConversationKey`, not shaped like a real
   conversation UUID) instead of the passed `conversationId`, for both the
   Dart-side bookkeeping and the actual native `conversationToken` sent
   over the channel -- a background call can never be mistaken for, or
   report itself as, a real conversation's own context;
 - rejects (not evicts) a background call outright when a *different*
   model is already loaded, with a clean, named error
   (`LiteRtException('background_model_conflict', ...)`) that the existing
   background-task error handling (`onBackgroundTaskError`, already
   catches and logs any generation failure) absorbs without any UI change
   needed -- title-gen already treats "failed this time" as a normal,
   silent-to-the-user outcome.

**What this does *not* claim to fix**: `LocalModelRuntime` holds exactly
one native `Conversation` at a time by design ("one model, one generation
in memory"), so *any* intervening call -- background or a second real
conversation -- still evicts whatever was cached and forces the next real
turn to recreate from scratch. That eviction is an accepted, unavoidable
cost of the single-slot design, not something `isConversationTurn`
changes or was meant to change; the fix is specifically about identity
(never colliding keys) and never evicting the *loaded model itself* for a
background purpose, not about avoiding all reuse loss.

Verified with 3 new tests in `local_model_runtime_test.dart` (now
15/15 total, all passing): a background call tagged with the active
conversation's own id (a) always starts its own fresh native conversation
with empty `initialMessages` (never inherits real chat history) and (b)
never corrupts what the real conversation recreates with afterwards
(asserts the recreated conversation's `initialMessages` exactly matches
the real prior turns, not the background prompt); a background call
requesting a different already-loaded model is rejected with
`background_model_conflict` and triggers zero `loadModel`/`unloadModel`
calls; a background call targeting the same model already loaded, or
loading the very first model, proceeds normally. `dart analyze
--fatal-infos lib test integration_test` clean; the full
`test/core/services/local/` suite plus `chat_api_local_provider_isolation
_test.dart`, `home_view_model_title_test.dart`,
`home_view_model_summary_test.dart`, `chat_api_generate_message_test.dart`,
and `chat_api_custom_request_precedence_test.dart` all pass unchanged
(the new parameter is additive and defaults preserve every existing
call site's behavior).

## Full Android build results

`flutter build apk --debug --target-platform=android-arm64` (real Gradle
`assembleDebug`, not just `compileDebugKotlin` -- exercises every plugin's
Kotlin compilation, resource/asset merging, manifest merging, dexing, and
packaging against Kotlin 2.4.0 + AGP 8.11.1): **succeeded**, `Running
Gradle task 'assembleDebug'... 340.1s`, `✓ Built build/app/outputs/
flutter-apk/app-debug.apk`.

`python3 tool/verify_apk_arm64.py build/app/outputs/flutter-apk/
app-debug.apk` on the real built artifact (124316477 bytes,
sha256 `e8f70a49e1610ef6e92fbfd9272ae6e2a31aa65cb5ab6b02d1e730b1cbd21d2`):
single ABI `arm64-v8a` (no other architecture leaked in), and
**`liblitertlm_jni.so` is present** among the packaged native libraries
alongside every other expected Android-only-feature library (`libproot_
exec.so`/`libproot_loader.so`/`libtermux_pty.so` for the embedded Linux
env and terminal, `libsherpa-onnx-*.so` for ASR, `libsqlite3.so` for
Drift) -- confirms the LiteRT-LM native library is actually built into a
real APK, not just resolved as a Gradle dependency.

(A first build attempt was accidentally killed mid-run by an unrelated
`pkill` used to stop a stale background `flutter test` process in this
same session -- caught immediately by the missing APK output, re-ran
cleanly to the result above. Not a build problem; noted here only so
future re-reads of this log aren't confused by the dangling
`manifest-merger-debug-report.txt` an interrupted run leaves behind.)

## Android JVM unit test results (`gradle :app:testDebugUnitTest`)

First attempt used the wrong tool: the sandbox's global `/opt/gradle/bin/
gradle` binary is version 8.14.3, not the project's own pinned wrapper
version (8.14, `gradle-wrapper.properties`) -- caused unrelated artifact-
transform failures in `:audioplayers_android` plus a real "No space left
on device" (this session's disk allowance was exhausted by the earlier
successful APK build's Gradle caches). Fixed by using the project's own
`./gradlew` (matches exactly what `flutter build apk` already used) and
freeing disk space (deleted the unused `8.14.3`/`9.5.0` Gradle version
caches -- safe, since the project only ever uses `8.14`).

With the right tool, `:app:compileDebugUnitTestKotlin` **failed to
compile** -- a real, Kotlin-2.4.0-specific error, not a version-mismatch
artifact: `IncomingShareHandlerTest.kt:196`, `MatrixCursor(...).apply {
addRow(arrayOf(name, reportedSize)) }` where `name: String` and
`reportedSize: Long?`. Kotlin 2.2.20 silently inferred a common
supertype for `arrayOf`'s reified type parameter; Kotlin 2.4.0 treats the
resulting intersection type (`Comparable<*>? & Serializable?`) as a
compile error instead of a warning. This is exactly the class of problem
`compileDebugKotlin` alone (only the main `app` source set) could never
have caught -- it only surfaced by actually compiling the JVM test source
set against the pinned toolchain, confirming the task brief's instinct
that a full build is not optional. Fixed with an explicit
`arrayOf<Any?>(name, reportedSize)` -- same values, no behavior change,
searched the whole `android/app/src/test` tree and confirmed this was the
only such call.

With that fixed, `:app:testDebugUnitTest` ran: **122 tests, 104 passed,
18 failed** -- all 18 failures are in `WorkspaceDocumentsProviderTest`
(symlink-handling tests: `hidesEscapingSymlinksWhileAllowingInternal
Links`, `refusesRedirectedWorkspaceRoots`, etc.), every one throwing
`java.nio.file.FileSystemException`/`UnixException` from
`Files.createSymbolicLink(...)` calls the test itself makes (lines
331/332/341) -- this sandboxed container's filesystem does not permit
creating symlinks at the OS syscall level, unrelated to root/permissions
and unrelated to anything this branch changed. Confirmed via
`git diff master...HEAD --stat -- android/app/src/main/kotlin/com/psyche/
kelivo/workspace/ android/app/src/test/kotlin/com/psyche/kelivo/
workspace/` returning **empty** -- this branch has not touched the
workspace provider or its test in any way; the failure is a pre-existing
sandbox limitation (same category as the two previously-documented Dart-
side sandbox-specific failures, `desktop_process_runtime_test.dart` and
`chat_input_bar_attachment_cleanup_test.dart`), not a regression, and not
something this branch is positioned to fix (the underlying capability the
container lacks). Needs verification in a real CI/device environment
that does permit symlink creation, not in this sandbox.

**Honest summary for item 4**: exact versions are pinned and recorded
above. The main app compiles and packages into a real, verified arm64
APK against the full pinned toolchain (Kotlin 2.4.0 + AGP 8.11.1 + Gradle
8.14). The JVM/unit test source set also compiles clean against that same
toolchain, after fixing one genuine Kotlin-2.4.0 compile error the full
build (not `compileDebugKotlin` alone) caught. 104/122 JVM unit tests
pass; the 18 failures are a pre-existing, unrelated sandbox limitation
(no symlink support), not a regression from this branch or from the
Kotlin/AGP pin.

## CI confirmation (`moru-android.yml`, `workflow_dispatch`, debug variant)

Dispatched the repo's own approved workflow on this branch (run
[35552057919](https://github.com/mishaqp/Moru/actions/runs/35552057919),
commit `591d0c5`) to get an installable test APK too large to hand over
directly. **Result: `success`, end to end**, including the `:app:
testDebugUnitTest` step, which has no `continue-on-error` -- so this is
independent, real-CI confirmation on a normal Ubuntu runner (where
symlinks work) that **all 122/122 JVM unit tests pass**, settling the
open question from the section above: the 18 failures seen in this
sandbox really were that sandbox's own missing-symlink-support artifact,
not a real defect.

CI's own `verify_apk_arm64.py` + `apksigner`/`aapt2` reports on its
independently-built APK (`Moru-arm64-v8a-debug.apk`, sha256
`6ad8daffb483e6b14cdc3dfafe90d2c4c0eb95673b7ffbf4eb5f4b890d990dfc`, 124308913
bytes): single `arm64-v8a` ABI, `liblitertlm_jni.so` present, package
`com.mishaqp.moru` versionCode 14 / versionName 0.1.13, minSdk 24 /
targetSdk 36 -- all matching this branch's own local build exactly except
for the debug-keystore signature bytes (expected: each machine's
auto-generated debug keystore differs, hence a different sha256 from the
locally-built APK despite otherwise-identical content).

## Next
Start slice 4 (verified catalog + resumable download).

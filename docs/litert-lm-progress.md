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

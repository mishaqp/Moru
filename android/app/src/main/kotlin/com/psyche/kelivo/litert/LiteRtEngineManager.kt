package com.psyche.kelivo.litert

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.Role
import com.google.ai.edge.litertlm.SamplerConfig
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Owns the single in-memory LiteRT-LM [Engine]/[Conversation] pair for the
 * whole process. Every command (load, unload, start a conversation, send a
 * message, cancel) is funneled through [commandExecutor], a single-threaded
 * executor, so they never interleave with each other -- matches the "one
 * model, one generation at a time, fully serialized" requirement from the
 * task brief. A `sendMessage` call itself only *starts* native generation;
 * the actual token stream arrives later via [MessageCallback] on a JNI
 * thread, so [state] plus the latch in [activeGeneration] are the real
 * source of truth `unloadModel`/a second `sendMessage` check against, not
 * just "is the executor free".
 *
 * Cancellation: [cancel] calls [Conversation.cancelProcess], the one
 * verified-real native cancel entry point (see docs/litert-lm-progress.md --
 * cancelling the Kotlin Flow/coroutine alone does **not** stop native
 * inference, confirmed by reading the SDK's own source). [unloadModel]
 * always cancels first and waits for the generation's own terminal callback
 * before calling [Conversation.close]/[Engine.close], so close() is never
 * called concurrently with an active native call.
 */
class LiteRtEngineManager(private val events: LiteRtEvents) {
    enum class State { NOT_LOADED, LOADING, READY, GENERATING, STOPPING, UNLOADING, ERROR }

    private class ActiveGeneration(val requestId: String, val conversation: Conversation) {
        val latch = CountDownLatch(1)
    }

    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val lock = Any()

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var conversationToken: String? = null
    private var activeGeneration: ActiveGeneration? = null

    @Volatile
    var state: State = State.NOT_LOADED
        private set(value) {
            field = value
            events.emit(mapOf("type" to "engineState", "state" to value.name.lowercase()))
        }

    /** Posts [block] onto the single command executor, reporting exceptions as `onError`. */
    private fun post(onError: (Throwable) -> Unit, block: () -> Unit) {
        commandExecutor.execute {
            try {
                block()
            } catch (error: Throwable) {
                onError(error)
            }
        }
    }

    fun loadModel(
        modelPath: String,
        backend: String,
        cacheDir: String?,
        maxNumTokens: Int?,
        onResult: (Result<String>) -> Unit,
    ) {
        post({ onResult(Result.failure(it)) }) {
            synchronized(lock) {
                check(engine == null) { "already_loaded" }
                check(state != State.GENERATING && state != State.STOPPING) { "busy" }
                state = State.LOADING
            }
            val requestedGpu = backend == "gpu"
            var actualBackend = if (requestedGpu) "gpu" else "cpu"
            val loaded = try {
                initializeEngine(modelPath, if (requestedGpu) Backend.GPU() else Backend.CPU(), cacheDir, maxNumTokens)
            } catch (primaryError: Throwable) {
                if (!requestedGpu) {
                    synchronized(lock) { state = State.ERROR }
                    onResult(Result.failure(primaryError))
                    return@post
                }
                // One honest, one-time fallback to CPU -- never a retry loop.
                actualBackend = "cpu"
                try {
                    initializeEngine(modelPath, Backend.CPU(), cacheDir, maxNumTokens)
                } catch (cpuError: Throwable) {
                    synchronized(lock) { state = State.ERROR }
                    onResult(Result.failure(cpuError))
                    return@post
                }
            }
            synchronized(lock) {
                engine = loaded
                state = State.READY
            }
            onResult(Result.success(actualBackend))
        }
    }

    private fun initializeEngine(
        modelPath: String,
        backend: Backend,
        cacheDir: String?,
        maxNumTokens: Int?,
    ): Engine {
        val config = EngineConfig(
            modelPath = modelPath,
            backend = backend,
            maxNumTokens = maxNumTokens,
            cacheDir = cacheDir,
        )
        val instance = Engine(config)
        instance.initialize()
        return instance
    }

    fun unloadModel(onResult: (Result<Unit>) -> Unit) {
        post({ onResult(Result.failure(it)) }) {
            val pending = synchronized(lock) { activeGeneration }
            if (pending != null) {
                synchronized(lock) { state = State.STOPPING }
                runCatching { pending.conversation.cancelProcess() }
                // Bounded wait: the SDK gives no hard upper bound on how long a
                // cancelled call takes to actually unwind, so this is a safety
                // ceiling, not a normal-path timeout.
                pending.latch.await(10, TimeUnit.SECONDS)
            }
            synchronized(lock) {
                state = State.UNLOADING
                runCatching { conversation?.close() }
                conversation = null
                conversationToken = null
                runCatching { engine?.close() }
                engine = null
                activeGeneration = null
                state = State.NOT_LOADED
            }
            onResult(Result.success(Unit))
        }
    }

    fun startConversation(
        token: String,
        systemInstruction: String?,
        initialMessages: List<Pair<String, String>>,
        temperature: Double?,
        topK: Int?,
        topP: Double?,
        onResult: (Result<Unit>) -> Unit,
    ) {
        post({ onResult(Result.failure(it)) }) {
            val currentEngine = synchronized(lock) {
                check(state != State.GENERATING && state != State.STOPPING) { "busy" }
                engine ?: throw IllegalStateException("not_loaded")
            }
            synchronized(lock) {
                runCatching { conversation?.close() }
                conversation = null
                conversationToken = null
            }
            val messages = initialMessages.map { (role, text) -> messageFor(role, text) }
            val sampler = if (temperature != null && topK != null && topP != null) {
                SamplerConfig(topK = topK, topP = topP, temperature = temperature)
            } else {
                null
            }
            val config = ConversationConfig(
                systemInstruction = systemInstruction?.let { Contents.of(it) },
                initialMessages = messages,
                samplerConfig = sampler,
            )
            val created = currentEngine.createConversation(config)
            synchronized(lock) {
                conversation = created
                conversationToken = token
                if (state != State.READY) state = State.READY
            }
            onResult(Result.success(Unit))
        }
    }

    private fun messageFor(role: String, text: String): Message = when (role) {
        "system" -> Message.system(text)
        "model", "assistant" -> Message.model(text)
        "tool" -> Message.tool(Contents.of(text))
        else -> Message.user(text)
    }

    fun sendMessage(
        requestId: String,
        conversationToken: String,
        text: String,
        onAccepted: (Result<Unit>) -> Unit,
    ) {
        post({ onAccepted(Result.failure(it)) }) {
            val target = synchronized(lock) {
                check(state == State.READY) { "busy" }
                check(this.conversationToken == conversationToken) { "stale_conversation" }
                val c = conversation ?: throw IllegalStateException("not_loaded")
                val generation = ActiveGeneration(requestId, c)
                activeGeneration = generation
                state = State.GENERATING
                generation
            }
            onAccepted(Result.success(Unit))
            target.conversation.sendMessageAsync(
                text,
                object : MessageCallback {
                    override fun onMessage(message: Message) {
                        events.emit(
                            mapOf(
                                "type" to "textDelta",
                                "requestId" to requestId,
                                "text" to message.toString(),
                            ),
                        )
                    }

                    override fun onDone() {
                        finishGeneration(target, cancelled = false, error = null)
                        events.emit(mapOf("type" to "done", "requestId" to requestId))
                    }

                    override fun onError(throwable: Throwable) {
                        val cancelled = throwable is java.util.concurrent.CancellationException
                        finishGeneration(target, cancelled = cancelled, error = throwable)
                        events.emit(
                            mapOf(
                                "type" to "error",
                                "requestId" to requestId,
                                "cancelled" to cancelled,
                                "message" to (throwable.message ?: throwable.toString()),
                            ),
                        )
                    }
                },
            )
        }
    }

    private fun finishGeneration(generation: ActiveGeneration, cancelled: Boolean, error: Throwable?) {
        synchronized(lock) {
            if (activeGeneration === generation) {
                activeGeneration = null
                if (state == State.GENERATING || state == State.STOPPING) {
                    state = if (engine != null) State.READY else State.NOT_LOADED
                }
            }
        }
        generation.latch.countDown()
    }

    /**
     * Cancels [requestId] if it is the currently active generation. A no-op
     * (returns `false`) if nothing matches -- e.g. Stop arriving after the
     * model already finished on its own.
     */
    fun cancel(requestId: String, onResult: (Result<Boolean>) -> Unit) {
        post({ onResult(Result.failure(it)) }) {
            val generation = synchronized(lock) { activeGeneration }
            if (generation == null || generation.requestId != requestId) {
                onResult(Result.success(false))
                return@post
            }
            synchronized(lock) { if (state == State.GENERATING) state = State.STOPPING }
            generation.conversation.cancelProcess()
            onResult(Result.success(true))
        }
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        mapOf(
            "state" to state.name.lowercase(),
            "loaded" to (engine != null),
            "conversationToken" to conversationToken,
            "activeRequestId" to activeGeneration?.requestId,
        )
    }
}

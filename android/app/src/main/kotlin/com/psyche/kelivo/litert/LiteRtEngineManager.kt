package com.psyche.kelivo.litert

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Channel
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.OpenApiTool
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import com.google.ai.edge.litertlm.ToolCall
import com.google.ai.edge.litertlm.tool
import com.google.gson.Gson
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

data class LiteRtContent(
    val type: String,
    val text: String? = null,
    val path: String? = null,
    val name: String? = null,
    val response: Any? = null,
)

data class LiteRtToolCall(val name: String, val arguments: Map<String, Any?>)

data class LiteRtMessage(
    val role: String,
    val contents: List<LiteRtContent>,
    val toolCalls: List<LiteRtToolCall> = emptyList(),
)

data class LiteRtToolResponse(val name: String, val response: Any?)

/** Owns the process-wide LiteRT-LM engine and conversation. */
class LiteRtEngineManager(private val events: LiteRtEvents) {
    enum class State { NOT_LOADED, LOADING, READY, GENERATING, STOPPING, UNLOADING, ERROR }

    private class ActiveGeneration(val requestId: String, val conversation: Conversation) {
        val latch = CountDownLatch(1)

        @Volatile
        var awaitingToolResponse = false

        var callback: MessageCallback? = null
    }

    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val gson = Gson()

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
        visionEnabled: Boolean,
        audioEnabled: Boolean,
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
                initializeEngine(
                    modelPath,
                    if (requestedGpu) Backend.GPU() else Backend.CPU(),
                    cacheDir,
                    maxNumTokens,
                    visionEnabled,
                    audioEnabled,
                )
            } catch (primaryError: Throwable) {
                if (!requestedGpu) {
                    synchronized(lock) { state = State.ERROR }
                    onResult(Result.failure(primaryError))
                    return@post
                }
                actualBackend = "cpu"
                try {
                    initializeEngine(
                        modelPath,
                        Backend.CPU(),
                        cacheDir,
                        maxNumTokens,
                        visionEnabled,
                        audioEnabled,
                    )
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
        visionEnabled: Boolean,
        audioEnabled: Boolean,
    ): Engine {
        val config = EngineConfig(
            modelPath = modelPath,
            backend = backend,
            visionBackend = if (visionEnabled) backend else null,
            audioBackend = if (audioEnabled) backend else null,
            maxNumTokens = maxNumTokens,
            cacheDir = cacheDir,
        )
        val instance = Engine(config)
        try {
            instance.initialize()
            return instance
        } catch (error: Throwable) {
            runCatching { instance.close() }
            throw error
        }
    }

    fun unloadModel(onResult: (Result<Unit>) -> Unit) {
        post({ onResult(Result.failure(it)) }) {
            val pending = synchronized(lock) { activeGeneration }
            if (pending != null) {
                synchronized(lock) { state = State.STOPPING }
                runCatching { pending.conversation.cancelProcess() }
                if (!pending.latch.await(10, TimeUnit.SECONDS)) {
                    synchronized(lock) { state = State.ERROR }
                    onResult(Result.failure(IllegalStateException("cancel_timeout")))
                    return@post
                }
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
        initialMessages: List<LiteRtMessage>,
        temperature: Double?,
        topK: Int?,
        topP: Double?,
        maxOutputTokens: Int?,
        thinkingEnabled: Boolean,
        thinkingBudget: Int?,
        tools: List<Map<String, Any?>>,
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
            val sampler = if (temperature != null && topK != null && topP != null) {
                SamplerConfig(topK = topK, topP = topP, temperature = temperature)
            } else {
                null
            }
            val config = ConversationConfig(
                systemInstruction = systemInstruction?.let { Contents.of(it) },
                initialMessages = initialMessages.map(::messageFor),
                tools = tools.map(::openApiTool),
                samplerConfig = sampler,
                automaticToolCalling = false,
                // DeepSeek-R1/Qwen emit their scratchpad between these tokens.
                // Register it as a non-user-visible channel so it is removed from
                // Message.contents before the text callback reaches the chat.
                channels = listOf(Channel("analysis", "<think>", "</think>")),
                maxOutputToken = maxOutputTokens,
                thinkingConfig = ThinkingConfig(
                    enableThinking = thinkingEnabled,
                    thinkingTokenBudget = thinkingBudget ?: -1,
                ),
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

    private fun openApiTool(raw: Map<String, Any?>) = tool(
        object : OpenApiTool {
            override fun getToolDescriptionJsonString(): String {
                val description = (raw["function"] as? Map<*, *>) ?: raw
                return gson.toJson(description)
            }

            override fun execute(paramsJsonString: String): String =
                error("Automatic tool execution is disabled")
        },
    )

    private fun messageFor(message: LiteRtMessage): Message {
        val contents = contentsFor(message.contents)
        return when (message.role) {
            "system" -> Message.system(contents)
            "model", "assistant" -> Message.model(
                contents = contents,
                toolCalls = message.toolCalls.map { ToolCall(it.name, it.arguments) },
            )
            "tool" -> Message.tool(contents)
            else -> Message.user(contents)
        }
    }

    private fun contentsFor(contents: List<LiteRtContent>): Contents = Contents.of(
        contents.mapNotNull { content ->
            when (content.type) {
                "text" -> content.text?.let(Content::Text)
                "image" -> content.path?.let(Content::ImageFile)
                "audio" -> content.path?.let(Content::AudioFile)
                "tool_response" -> content.name?.let {
                    Content.ToolResponse(it, content.response)
                }
                else -> null
            }
        },
    )

    fun sendMessage(
        requestId: String,
        conversationToken: String,
        contents: List<LiteRtContent>,
        onAccepted: (Result<Unit>) -> Unit,
    ) {
        post({ onAccepted(Result.failure(it)) }) {
            val target = createGeneration(requestId, conversationToken)
            sendAsync(target, Message.user(contentsFor(contents)), onAccepted)
        }
    }

    fun sendToolResponses(
        requestId: String,
        conversationToken: String,
        responses: List<LiteRtToolResponse>,
        onAccepted: (Result<Unit>) -> Unit,
    ) {
        post({ onAccepted(Result.failure(it)) }) {
            val target = synchronized(lock) {
                val active = activeGeneration ?: throw IllegalStateException("not_generating")
                check(active.requestId == requestId) { "stale_request" }
                check(this.conversationToken == conversationToken) { "stale_conversation" }
                check(active.awaitingToolResponse) { "not_awaiting_tool" }
                active.awaitingToolResponse = false
                active
            }
            val contents = Contents.of(
                responses.map { Content.ToolResponse(it.name, it.response) },
            )
            sendAsync(target, Message.tool(contents), onAccepted)
        }
    }

    private fun createGeneration(requestId: String, token: String): ActiveGeneration =
        synchronized(lock) {
            check(state == State.READY) { "busy" }
            check(conversationToken == token) { "stale_conversation" }
            val current = conversation ?: throw IllegalStateException("not_loaded")
            ActiveGeneration(requestId, current).also {
                activeGeneration = it
                state = State.GENERATING
            }
        }

    private fun sendAsync(
        generation: ActiveGeneration,
        message: Message,
        onAccepted: (Result<Unit>) -> Unit,
    ) {
        val callback = generation.callback ?: callbackFor(generation).also {
            generation.callback = it
        }
        try {
            generation.conversation.sendMessageAsync(message, callback)
            onAccepted(Result.success(Unit))
        } catch (error: Throwable) {
            finishGeneration(generation)
            events.emit(
                mapOf(
                    "type" to "error",
                    "requestId" to generation.requestId,
                    "cancelled" to false,
                    "message" to (error.message ?: error.toString()),
                ),
            )
            onAccepted(Result.failure(error))
        }
    }

    private fun callbackFor(generation: ActiveGeneration) = object : MessageCallback {
        override fun onMessage(message: Message) {
            // SDK channel data can contain private model reasoning (for example
            // DeepSeek's analysis channel). Never forward it into chat history/UI.
            val text = message.toString()
            if (text.isNotEmpty()) {
                events.emit(
                    mapOf(
                        "type" to "textDelta",
                        "requestId" to generation.requestId,
                        "text" to text,
                    ),
                )
            }
            if (message.toolCalls.isNotEmpty()) {
                synchronized(lock) {
                    if (activeGeneration === generation) {
                        generation.awaitingToolResponse = true
                    }
                }
                events.emit(
                    mapOf(
                        "type" to "toolCalls",
                        "requestId" to generation.requestId,
                        "calls" to message.toolCalls.map {
                            mapOf("name" to it.name, "arguments" to it.arguments)
                        },
                    ),
                )
            }
        }

        override fun onDone() {
            if (generation.awaitingToolResponse) return
            finishGeneration(generation)
            events.emit(mapOf("type" to "done", "requestId" to generation.requestId))
        }

        override fun onError(throwable: Throwable) {
            val cancelled = throwable is java.util.concurrent.CancellationException
            finishGeneration(generation)
            events.emit(
                mapOf(
                    "type" to "error",
                    "requestId" to generation.requestId,
                    "cancelled" to cancelled,
                    "message" to (throwable.message ?: throwable.toString()),
                ),
            )
        }
    }

    private fun finishGeneration(generation: ActiveGeneration) {
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
            "awaitingToolResponse" to (activeGeneration?.awaitingToolResponse == true),
        )
    }
}

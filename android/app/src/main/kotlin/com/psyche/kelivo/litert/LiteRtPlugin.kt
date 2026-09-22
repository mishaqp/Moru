package com.psyche.kelivo.litert

import android.app.ActivityManager
import android.content.Context
import com.google.gson.Gson
import com.google.gson.JsonParser
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Dart/Kotlin bridge for the on-device LiteRT-LM provider. */
class LiteRtPlugin(private val context: Context) {
    companion object {
        const val CHANNEL_NAME = "app.litert"
        const val EVENT_CHANNEL_NAME = "app.litert/events"
    }

    private val events = LiteRtEvents()
    private val manager = LiteRtEngineManager(events)
    private val gson = Gson()

    fun configure(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(events)
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(manager.status())
                    "storageInfo" -> result.success(storageInfo())
                    "loadModel" -> handleLoad(asMap(call.arguments), result)
                    "unloadModel" -> manager.unloadModel { outcome ->
                        outcome.fold(
                            onSuccess = { result.success(null) },
                            onFailure = { result.error(errorCode(it), it.message, null) },
                        )
                    }
                    "startConversation" -> handleStartConversation(asMap(call.arguments), result)
                    "sendMessage" -> handleSendMessage(asMap(call.arguments), result)
                    "sendToolResponses" -> handleToolResponses(asMap(call.arguments), result)
                    "cancel" -> {
                        val args = asMap(call.arguments)
                        manager.cancel(requiredString(args, "requestId")) { outcome ->
                            outcome.fold(
                                onSuccess = { matched -> result.success(matched) },
                                onFailure = { result.error(errorCode(it), it.message, null) },
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: IllegalArgumentException) {
                result.error("invalid_args", error.message, null)
            } catch (error: Exception) {
                result.error("litert", error.message, null)
            }
        }
    }

    private fun handleLoad(args: Map<*, *>, result: MethodChannel.Result) {
        manager.loadModel(
            modelPath = requiredString(args, "modelPath"),
            backend = args["backend"]?.toString() ?: "cpu",
            cacheDir = args["cacheDir"]?.toString(),
            maxNumTokens = (args["maxNumTokens"] as? Number)?.toInt(),
            visionEnabled = args["visionEnabled"] == true,
            audioEnabled = args["audioEnabled"] == true,
        ) { outcome ->
            outcome.fold(
                onSuccess = { backend -> result.success(mapOf("backend" to backend)) },
                onFailure = { result.error(errorCode(it), it.message, null) },
            )
        }
    }

    private fun handleStartConversation(args: Map<*, *>, result: MethodChannel.Result) {
        val initial = (args["initialMessages"] as? List<*>)
            .orEmpty()
            .mapNotNull(::parseMessage)
        val tools = (args["tools"] as? List<*>)
            .orEmpty()
            .mapNotNull { value -> (value as? Map<*, *>)?.let(::stringMap) }
        manager.startConversation(
            token = requiredString(args, "conversationToken"),
            systemInstruction = args["systemInstruction"]?.toString(),
            initialMessages = initial,
            temperature = (args["temperature"] as? Number)?.toDouble(),
            topK = (args["topK"] as? Number)?.toInt(),
            topP = (args["topP"] as? Number)?.toDouble(),
            maxOutputTokens = (args["maxOutputTokens"] as? Number)?.toInt(),
            thinkingEnabled = args["thinkingEnabled"] == true,
            thinkingBudget = (args["thinkingBudget"] as? Number)?.toInt(),
            tools = tools,
        ) { outcome ->
            outcome.fold(
                onSuccess = { result.success(null) },
                onFailure = { result.error(errorCode(it), it.message, null) },
            )
        }
    }

    private fun handleSendMessage(args: Map<*, *>, result: MethodChannel.Result) {
        manager.sendMessage(
            requestId = requiredString(args, "requestId"),
            conversationToken = requiredString(args, "conversationToken"),
            contents = parseContents(args["contents"]),
        ) { outcome ->
            outcome.fold(
                onSuccess = { result.success(null) },
                onFailure = { result.error(errorCode(it), it.message, null) },
            )
        }
    }

    private fun handleToolResponses(args: Map<*, *>, result: MethodChannel.Result) {
        val responses = (args["responses"] as? List<*>)
            .orEmpty()
            .mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val name = map["name"]?.toString()?.trim().orEmpty()
                if (name.isEmpty()) return@mapNotNull null
                LiteRtToolResponse(name, parseJsonValue(map["response"]))
            }
        require(responses.isNotEmpty()) { "missing responses" }
        manager.sendToolResponses(
            requestId = requiredString(args, "requestId"),
            conversationToken = requiredString(args, "conversationToken"),
            responses = responses,
        ) { outcome ->
            outcome.fold(
                onSuccess = { result.success(null) },
                onFailure = { result.error(errorCode(it), it.message, null) },
            )
        }
    }

    private fun parseMessage(value: Any?): LiteRtMessage? {
        val map = value as? Map<*, *> ?: return null
        val role = map["role"]?.toString()?.trim().orEmpty()
        if (role.isEmpty()) return null
        val toolCalls = (map["toolCalls"] as? List<*>)
            .orEmpty()
            .mapNotNull { raw ->
                val call = raw as? Map<*, *> ?: return@mapNotNull null
                val name = call["name"]?.toString()?.trim().orEmpty()
                if (name.isEmpty()) return@mapNotNull null
                val arguments = (call["arguments"] as? Map<*, *>)
                    ?.let(::stringMap)
                    ?: emptyMap()
                LiteRtToolCall(name, arguments)
            }
        return LiteRtMessage(role, parseContents(map["contents"]), toolCalls)
    }

    private fun parseContents(value: Any?): List<LiteRtContent> =
        (value as? List<*>)
            .orEmpty()
            .mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val type = map["type"]?.toString()?.trim().orEmpty()
                if (type.isEmpty()) return@mapNotNull null
                LiteRtContent(
                    type = type,
                    text = map["text"]?.toString(),
                    path = map["path"]?.toString(),
                    name = map["name"]?.toString(),
                    response = parseJsonValue(map["response"]),
                )
            }

    private fun parseJsonValue(value: Any?): Any? {
        if (value !is String) return value
        return try {
            gson.fromJson(JsonParser.parseString(value), Any::class.java)
        } catch (_: Throwable) {
            value
        }
    }

    private fun stringMap(value: Map<*, *>): Map<String, Any?> =
        value.entries.associate { (key, item) -> key.toString() to normalizeValue(item) }

    private fun normalizeValue(value: Any?): Any? = when (value) {
        is Map<*, *> -> stringMap(value)
        is List<*> -> value.map(::normalizeValue)
        else -> value
    }

    private fun storageInfo(): Map<String, Long> {
        val memory = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
            .getMemoryInfo(memory)
        return mapOf(
            "availableBytes" to context.filesDir.usableSpace,
            "totalMemoryBytes" to memory.totalMem,
        )
    }

    private fun errorCode(error: Throwable): String = when (error.message) {
        "busy",
        "already_loaded",
        "not_loaded",
        "not_generating",
        "not_awaiting_tool",
        "stale_conversation",
        "stale_request",
        "cancel_timeout" -> error.message!!
        else -> "litert_native"
    }

    private fun asMap(value: Any?): Map<*, *> = value as? Map<*, *> ?: emptyMap<Any, Any>()

    private fun requiredString(args: Map<*, *>, key: String): String {
        val text = args[key]?.toString()?.trim().orEmpty()
        require(text.isNotEmpty()) { "missing $key" }
        return text
    }
}

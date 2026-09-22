package com.psyche.kelivo.litert

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Dart<->Kotlin bridge for the local "Локальные модели · LiteRT" provider.
 * Mirrors `com.psyche.kelivo.workspace.WorkspacePlugin`'s shape: one
 * MethodChannel for commands, one EventChannel for the token stream and
 * engine-state changes, all real work handed off to [LiteRtEngineManager]
 * so nothing here ever blocks the Flutter/Android main thread. Only
 * identifiers, small config values, and text ever cross this channel --
 * never model weight bytes.
 */
class LiteRtPlugin(private val context: Context) {
    companion object {
        const val CHANNEL_NAME = "app.litert"
        const val EVENT_CHANNEL_NAME = "app.litert/events"
    }

    private val events = LiteRtEvents()
    private val manager = LiteRtEngineManager(events)

    fun configure(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(events)
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(manager.status())
                    "loadModel" -> {
                        val args = asMap(call.arguments)
                        manager.loadModel(
                            modelPath = requiredString(args, "modelPath"),
                            backend = args["backend"]?.toString() ?: "cpu",
                            cacheDir = args["cacheDir"]?.toString(),
                            maxNumTokens = (args["maxNumTokens"] as? Number)?.toInt(),
                        ) { outcome ->
                            outcome.fold(
                                onSuccess = { backend -> result.success(mapOf("backend" to backend)) },
                                onFailure = { result.error(errorCode(it), it.message, null) },
                            )
                        }
                    }
                    "unloadModel" -> manager.unloadModel { outcome ->
                        outcome.fold(
                            onSuccess = { result.success(null) },
                            onFailure = { result.error(errorCode(it), it.message, null) },
                        )
                    }
                    "startConversation" -> {
                        val args = asMap(call.arguments)
                        val initial = (args["initialMessages"] as? List<*>).orEmpty().mapNotNull { entry ->
                            val map = entry as? Map<*, *> ?: return@mapNotNull null
                            val role = map["role"]?.toString() ?: return@mapNotNull null
                            val text = map["text"]?.toString() ?: return@mapNotNull null
                            role to text
                        }
                        manager.startConversation(
                            token = requiredString(args, "conversationToken"),
                            systemInstruction = args["systemInstruction"]?.toString(),
                            initialMessages = initial,
                            temperature = (args["temperature"] as? Number)?.toDouble(),
                            topK = (args["topK"] as? Number)?.toInt(),
                            topP = (args["topP"] as? Number)?.toDouble(),
                        ) { outcome ->
                            outcome.fold(
                                onSuccess = { result.success(null) },
                                onFailure = { result.error(errorCode(it), it.message, null) },
                            )
                        }
                    }
                    "sendMessage" -> {
                        val args = asMap(call.arguments)
                        manager.sendMessage(
                            requestId = requiredString(args, "requestId"),
                            conversationToken = requiredString(args, "conversationToken"),
                            text = requiredString(args, "text"),
                        ) { outcome ->
                            outcome.fold(
                                onSuccess = { result.success(null) },
                                onFailure = { result.error(errorCode(it), it.message, null) },
                            )
                        }
                    }
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

    private fun errorCode(error: Throwable): String = when (error.message) {
        "busy", "already_loaded", "not_loaded", "stale_conversation" -> error.message!!
        else -> "litert_native"
    }

    private fun asMap(value: Any?): Map<*, *> = value as? Map<*, *> ?: emptyMap<Any, Any>()

    private fun requiredString(args: Map<*, *>, key: String): String {
        val text = args[key]?.toString()?.trim().orEmpty()
        require(text.isNotEmpty()) { "missing $key" }
        return text
    }
}

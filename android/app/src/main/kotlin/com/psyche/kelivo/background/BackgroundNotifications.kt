package com.psyche.kelivo.background

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.psyche.kelivo.R
import org.json.JSONObject

/** A snapshot of live Dart approvals, never a persisted queue of decisions. */
internal class BackgroundNotifications(
    private val context: Context,
    private val runtime: BackgroundRuntime,
) {
    companion object {
        const val APPROVAL_CHANNEL = "moru_tool_approvals"
        const val RESULT_CHANNEL = "kelivo_bg_chat_v2"
        private const val APPROVAL_ID = 31
        private const val RESULT_ID = 32
        private const val SAVED_LABELS = "approval_notification_labels"
        private const val SAVED_ENABLED = "notification_alerts_enabled"
        private val uuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        private val labelKeys = setOf("allow", "deny", "open", "staleTitle", "staleBody",
            "privateTitle", "privateBody", "channelName", "channelDescription")

        fun actionUri(target: ApprovalTarget, action: String): Uri = Uri.Builder()
            .scheme("moru").authority("approval").appendPath(target.approvalId)
            .appendPath(target.conversationId).appendPath(target.generationRunId)
            .appendPath(target.assistantMessageId).appendPath(action).build()

        fun readAction(intent: Intent): Pair<ApprovalTarget, String>? {
            if (intent.action?.startsWith("moru.approval.") != true) return null
            val action = intent.action!!.removePrefix("moru.approval.")
            if (action !in setOf("allow", "deny")) return null
            val target = ApprovalTarget.fromMap(mapOf(
                "approvalId" to intent.getStringExtra("approvalId"),
                "conversationId" to intent.getStringExtra("conversationId"),
                "generationRunId" to intent.getStringExtra("generationRunId"),
                "assistantMessageId" to intent.getStringExtra("assistantMessageId"),
            )) ?: return null
            if (intent.data != actionUri(target, action)) return null
            return target to action
        }
    }

    internal data class ApprovalTarget(val approvalId: String, val conversationId: String,
        val generationRunId: String, val assistantMessageId: String) {
        fun toMap() = mapOf("approvalId" to approvalId, "conversationId" to conversationId,
            "generationRunId" to generationRunId, "assistantMessageId" to assistantMessageId)
        companion object {
            fun fromMap(map: Map<*, *>): ApprovalTarget? {
                val id = map["approvalId"] as? String ?: return null
                val conversation = map["conversationId"] as? String ?: return null
                val run = map["generationRunId"] as? String ?: return null
                val message = map["assistantMessageId"] as? String ?: return null
                if (!uuid.matches(id) || conversation.isBlank() || run.isBlank() || message.isBlank()) return null
                return ApprovalTarget(id, conversation, run, message)
            }
        }
    }

    private data class Approval(val target: ApprovalTarget, val title: String, val body: String)
    private data class Result(val conversationId: String, val runId: String, val messageId: String,
        val title: String, val body: String, val privateTitle: String, val privateBody: String)

    private val prefs = context.getSharedPreferences("kelivo_background", Context.MODE_PRIVATE)
    private val manager get() = context.getSystemService(NotificationManager::class.java)
    private var revision = -1L
    private var privateApprovals = false
    private var alertsEnabled = prefs.getBoolean(SAVED_ENABLED, true)
    private var labels: Map<String, String> = readLabels()
    private val pending = linkedMapOf<String, Approval>()
    private val consumed = mutableSetOf<ApprovalTarget>()
    private val results = linkedMapOf<String, Result>()
    val pendingCount get() = pending.size

    private fun readLabels(): Map<String, String> = try {
        val value = JSONObject(prefs.getString(SAVED_LABELS, "{}") ?: "{}")
        labelKeys.mapNotNull { key -> value.optString(key).takeIf { it.isNotBlank() }?.let { key to it } }.toMap()
    } catch (_: Exception) { emptyMap() }

    private fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback
    private fun privateMode() = runtime.enabled("privacyMode") || privateApprovals
    private fun canPost(channel: String): Boolean = alertsEnabled &&
        runtime.setting("notificationsEnabled") != false &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context,
            Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 26 || manager?.getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE)

    fun sync(args: Map<*, *>) {
        if ((args["version"] as? Number)?.toInt() != 1) return
        val next = (args["revision"] as? Number)?.toLong() ?: return
        if (next <= revision) return
        revision = next
        val settings = args["settings"] as? Map<*, *> ?: emptyMap<String, Any>()
        alertsEnabled = settings["enabled"] == true
        privateApprovals = settings["privacyMode"] == true
        val nextLabels = args["labels"] as? Map<*, *>
        if (nextLabels != null) labels = labelKeys.mapNotNull { key ->
            (nextLabels[key] as? String)?.takeIf { it.isNotBlank() }?.let { key to it }
        }.toMap()
        // Only generic localized labels survive death; no targets, previews or decisions.
        prefs.edit().putString(SAVED_LABELS, JSONObject(labels).toString())
            .putBoolean(SAVED_ENABLED, alertsEnabled).apply()
        val incoming = (args["pending"] as? List<*>)?.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val target = ApprovalTarget.fromMap(map) ?: return@mapNotNull null
            Approval(target, map["title"] as? String ?: label("privateTitle", "Approval needed"),
                map["body"] as? String ?: label("privateBody", "Review in Moru"))
        } ?: emptyList()
        consumed.retainAll(incoming.map { it.target }.toSet())
        val replacement = incoming.filter { alertsEnabled && it.target !in consumed }
            .associateBy { it.target.approvalId }
        for (id in pending.keys - replacement.keys) cancelApproval(id)
        manager?.activeNotifications?.filter { it.tag?.startsWith("moru.approval:") == true &&
            it.tag.removePrefix("moru.approval:") !in replacement }?.forEach { manager?.cancel(it.tag, it.id) }
        pending.clear()
        pending.putAll(replacement)
        refreshPrivacy()
    }

    fun onSettingsChanged() {
        (runtime.setting("notificationsEnabled") as? Boolean)?.let {
            alertsEnabled = it
            prefs.edit().putBoolean(SAVED_ENABLED, it).apply()
        }
        refreshPrivacy()
    }

    fun refreshPrivacy() {
        pending.values.forEach(::postApproval)
        // Privacy updates redact visible results; reading/dismissing a result
        // must not cause a later task snapshot to resurrect its notification.
        val visible = manager?.activeNotifications?.mapNotNull { it.tag }?.toSet() ?: emptySet()
        results.keys.filter { "moru.result:$it" !in visible }.forEach { results.remove(it) }
        results.values.forEach(::postResult)
    }

    fun ownsResult(tag: String?) = tag?.removePrefix("moru.result:")?.let { it in results } == true

    fun clearApprovals() {
        pending.keys.toList().forEach(::cancelApproval)
        pending.clear()
        consumed.clear()
    }

    fun showServiceFailure() {
        // A service-start failure has no persisted terminal chat result yet.
        // Use a separate, generic status alert, never a fake completed run.
        if (runtime.setting("notificationsEnabled") != true) return
        ensureResultChannel()
        if (!canPost(RESULT_CHANNEL)) return
        val title = runtime.label("interrupted", "Interrupted")
        val body = runtime.label("open", "Open")
        post("moru.background.failure", RESULT_ID, builder(RESULT_CHANNEL, title, body)
            .setPublicVersion(builder(RESULT_CHANNEL, title, body).build())
            .setContentIntent(openPendingIntent("", "", "", "status", "failure")).build())
    }

    private fun cancelApproval(id: String) { manager?.cancel("moru.approval:$id", APPROVAL_ID) }

    private fun ensureApprovalChannel() {
        if (Build.VERSION.SDK_INT >= 26) manager?.createNotificationChannel(
            NotificationChannel(APPROVAL_CHANNEL, label("channelName", "Tool approvals"), NotificationManager.IMPORTANCE_HIGH).apply {
                description = label("channelDescription", "Requests awaiting your decision")
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
    }

    private fun ensureResultChannel() {
        if (Build.VERSION.SDK_INT >= 26 && manager?.getNotificationChannel(RESULT_CHANNEL) == null)
            manager?.createNotificationChannel(NotificationChannel(RESULT_CHANNEL, "Chat notifications", NotificationManager.IMPORTANCE_HIGH))
    }

    private fun openPendingIntent(conversation: String, run: String, message: String, kind: String,
        identity: String): PendingIntent {
        val data = Uri.Builder().scheme("moru").authority("notification").appendPath(kind)
            .appendPath(identity).appendPath(conversation).appendPath(run).appendPath(message)
            .appendPath("open").build()
        return PendingIntent.getActivity(context, 0, runtime.openIntent(conversation, message).setData(data),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun actionPendingIntent(target: ApprovalTarget, action: String): PendingIntent {
        val intent = Intent(context, ApprovalNotificationReceiver::class.java)
            .setAction("moru.approval.$action").setData(actionUri(target, action))
        target.toMap().forEach { (key, value) -> intent.putExtra(key, value) }
        return PendingIntent.getBroadcast(context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun builder(channel: String, title: String, body: String) = NotificationCompat.Builder(context, channel)
        .setSmallIcon(R.drawable.ic_background_generation).setContentTitle(title).setContentText(body)
        .setStyle(NotificationCompat.BigTextStyle().bigText(body)).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        .setAutoCancel(true).setOnlyAlertOnce(true)

    private fun postApproval(approval: Approval) {
        ensureApprovalChannel()
        if (!canPost(APPROVAL_CHANNEL)) { cancelApproval(approval.target.approvalId); return }
        val privateTitle = label("privateTitle", "Approval needed")
        val privateBody = label("privateBody", "Review in Moru")
        val notification = builder(APPROVAL_CHANNEL, if (privateMode()) privateTitle else approval.title,
            if (privateMode()) privateBody else approval.body)
            .setPublicVersion(builder(APPROVAL_CHANNEL, privateTitle, privateBody).build())
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openPendingIntent(approval.target.conversationId, approval.target.generationRunId,
                approval.target.assistantMessageId, "approval", approval.target.approvalId))
        for (action in listOf("allow", "deny")) {
            val button = NotificationCompat.Action.Builder(0, label(action, if (action == "allow") "Allow" else "Deny"),
                actionPendingIntent(approval.target, action))
            if (Build.VERSION.SDK_INT >= 31) button.setAuthenticationRequired(true)
            notification.addAction(button.build())
        }
        post("moru.approval:${approval.target.approvalId}", APPROVAL_ID, notification.build())
    }

    fun showResult(args: Map<*, *>) {
        val conversation = (args["conversationId"] as? String)?.takeIf { it.isNotBlank() } ?: return
        val run = (args["generationRunId"] as? String)?.takeIf { it.isNotBlank() } ?: return
        if (args["outcome"] !in setOf("completed", "failed", "interrupted")) return
        val value = Result(conversation, run, args["assistantMessageId"] as? String ?: "",
            args["title"] as? String ?: "Moru", args["body"] as? String ?: "",
            args["privateTitle"] as? String ?: "Moru", args["privateBody"] as? String ?: "Task finished")
        // Keep only in-process, already-delivered metadata for immediate privacy redaction.
        results[run] = value
        results.keys.filter { key -> key != run && manager?.activeNotifications?.none { it.tag == "moru.result:$key" } == true }
            .forEach { results.remove(it) }
        postResult(value)
    }

    private fun postResult(result: Result) {
        ensureResultChannel()
        if (!canPost(RESULT_CHANNEL)) { manager?.cancel("moru.result:${result.runId}", RESULT_ID); return }
        val notification = builder(RESULT_CHANNEL, if (privateMode()) result.privateTitle else result.title,
            if (privateMode()) result.privateBody else result.body)
            .setPublicVersion(builder(RESULT_CHANNEL, result.privateTitle, result.privateBody).build())
            .setContentIntent(openPendingIntent(result.conversationId, result.runId, result.messageId, "result", result.runId))
            .build()
        post("moru.result:${result.runId}", RESULT_ID, notification)
    }

    private fun post(tag: String, id: Int, notification: Notification) {
        try { manager?.notify(tag, id, notification) }
        catch (_: SecurityException) { /* Permission may have changed after the check. */ }
    }

    fun handleAction(target: ApprovalTarget, action: String, finished: () -> Unit) {
        val live = pending[target.approvalId]
        if (live?.target != target || !runtime.canResolveApproval()) {
            postStale(target)
            finished()
            return
        }
        pending.remove(target.approvalId)
        consumed.add(target)
        cancelApproval(target.approvalId)
        runtime.dispatchApprovalAction(target.toMap() + ("action" to action)) { resolved ->
            if (!resolved) postStale(target)
            finished()
        }
    }

    private fun postStale(target: ApprovalTarget) {
        // An old action must not replace a new request which reused the same UUID.
        if (pending[target.approvalId]?.target?.let { it != target } == true) return
        ensureApprovalChannel()
        if (!canPost(APPROVAL_CHANNEL)) { cancelApproval(target.approvalId); return }
        val title = label("staleTitle", "Approval no longer available")
        val body = label("staleBody", "Open Moru to check this request")
        post("moru.approval:${target.approvalId}", APPROVAL_ID,
            builder(APPROVAL_CHANNEL, title, body).setPublicVersion(builder(APPROVAL_CHANNEL, title, body).build())
                .setContentIntent(openPendingIntent(target.conversationId, target.generationRunId,
                    target.assistantMessageId, "stale", target.approvalId)).build())
    }
}

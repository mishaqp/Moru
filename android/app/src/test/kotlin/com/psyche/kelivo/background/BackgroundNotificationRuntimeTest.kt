package com.psyche.kelivo.background

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Looper
import android.os.PowerManager
import com.psyche.kelivo.KelivoApplication
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowPowerManager
import org.robolectric.util.ReflectionHelpers
import java.nio.ByteBuffer
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = KelivoApplication::class)
class BackgroundNotificationRuntimeTest {
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val events = mutableListOf<MethodCall>()
        var acknowledgement: Any? = mapOf("status" to "resolved")
        var holdApprovalAcknowledgement = false
        override fun setMessageHandler(name: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(name) else handlers[name] = handler
        }
        override fun send(name: String, message: ByteBuffer?) = send(name, message, null)
        override fun send(name: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            message?.flip()
            val call = message?.let { StandardMethodCodec.INSTANCE.decodeMethodCall(it) }
            if (call != null) events += call
            if (call?.method == "approvalAction" && holdApprovalAcknowledgement) return
            val response = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(
                if (call?.method == "approvalAction") acknowledgement else null)
            response.flip()
            callback?.reply(response)
        }
        fun call(method: String, args: Any? = null, channel: String = "app.mobile_background", reply: (Any?) -> Unit = {}) {
            val data = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args))
            data.flip()
            handlers.getValue(channel).onMessage(data) { response ->
                response?.flip()
                reply(response?.let { StandardMethodCodec.INSTANCE.decodeEnvelope(it) })
            }
        }
    }

    private val app get() = RuntimeEnvironment.getApplication() as KelivoApplication
    private val manager get() = app.getSystemService(NotificationManager::class.java)
    private fun setup(): Pair<BackgroundRuntime, Messenger> {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val m = Messenger()
        val runtime = app.backgroundRuntime
        runtime.configure(m)
        m.call("takePendingConversation")
        return runtime to m
    }
    private fun target(id: Int, run: String = "run-$id") = mapOf(
        "approvalId" to "00000000-0000-4000-8000-${id.toString().padStart(12, '0')}",
        "conversationId" to "chat-$id", "generationRunId" to run,
        "assistantMessageId" to "message-$id", "title" to "Task $id", "body" to "Review $id")
    private fun approvals(m: Messenger, revision: Int, pending: List<Map<String, String>>, privacy: Boolean = false) {
        m.call("syncApprovals", mapOf("version" to 1, "revision" to revision,
            "settings" to mapOf("enabled" to true, "privacyMode" to privacy),
            "pending" to pending, "labels" to mapOf("allow" to "Allow", "deny" to "Deny",
                "privateTitle" to "Private task", "privateBody" to "Review in Moru",
                "staleTitle" to "Request expired", "staleBody" to "Open Moru to review current work")))
    }
    private fun approval(id: Int) = manager.activeNotifications.single {
        it.tag == "moru.approval:${target(id)["approvalId"]}"
    }.notification
    private fun result(m: Messenger, run: String, message: String = "message-$run") {
        m.call("showResult", mapOf("conversationId" to "chat-$run", "generationRunId" to run,
            "assistantMessageId" to message, "outcome" to "completed", "title" to "Result $run",
            "body" to "Safe preview $run", "privateTitle" to "Private result", "privateBody" to "Finished"))
    }

    @Test fun manifestDeclaresSpecialUseAndPrivateApprovalReceiver() {
        val info = app.packageManager.getServiceInfo(ComponentName(app, GenerationForegroundService::class.java), 0)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE, info.foregroundServiceType)
        val receiver = app.packageManager.getReceiverInfo(ComponentName(app,
            "com.psyche.kelivo.background.ApprovalNotificationReceiver"), 0)
        assertFalse(receiver.exported)
    }

    @Test fun serviceRunsAsSpecialUseOnAndroid14() {
        val (runtime, m) = setup()
        m.call("sync", mapOf("revision" to 1, "settings" to mapOf("androidEnabled" to true),
            "tasks" to listOf(mapOf("id" to "run", "conversationId" to "chat"))))
        val service = Robolectric.buildService(GenerationForegroundService::class.java).create()
        service.get().onStartCommand(Intent(), 0, 1)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE, service.get().foregroundServiceType)
        runtime.stopTasks()
        service.destroy()
    }

    @Test fun approvalActionsArePrivateAuthenticatedAndKeepFullTargetIdentity() {
        val (_, m) = setup()
        approvals(m, 1, listOf(target(1), target(2)))
        val first = approval(1)
        val second = approval(2)
        assertEquals(Notification.VISIBILITY_PRIVATE, first.visibility)
        assertTrue(first.actions.all { it.isAuthenticationRequired })
        assertNotEquals(first.actions[0].actionIntent, first.actions[1].actionIntent)
        assertNotEquals(first.actions[0].actionIntent, second.actions[0].actionIntent)
        val intent = shadowOf(first.actions[0].actionIntent).savedIntent
        assertNotNull(intent.data)
        assertEquals(target(1)["generationRunId"], intent.getStringExtra("generationRunId"))
        first.actions[0].actionIntent.send()
        shadowOf(Looper.getMainLooper()).idle()
        val action = m.events.single { it.method == "approvalAction" }.arguments as Map<*, *>
        assertEquals("allow", action["action"])
        target(1).filterKeys { it !in listOf("title", "body") }.forEach { (key, value) -> assertEquals(value, action[key]) }
        assertFalse(action.containsKey("body"))
        assertFalse(manager.activeNotifications.any { it.tag == "moru.approval:${target(1)["approvalId"]}" })
    }

    @Test fun duplicateActionIsStaleAndCannotResolveTheSameApprovalTwice() {
        val (_, m) = setup()
        approvals(m, 1, listOf(target(1)))
        val action = approval(1).actions[0].actionIntent
        action.send()
        shadowOf(Looper.getMainLooper()).idle()
        action.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, m.events.count { it.method == "approvalAction" })
        assertEquals("Request expired", approval(1).extras.getCharSequence(Notification.EXTRA_TITLE).toString())
    }

    @Test fun oldActionCannotResolveOrOverwriteASuccessorWithTheSameApprovalId() {
        val (_, m) = setup()
        approvals(m, 1, listOf(target(1, "old")))
        val old = approval(1).actions[0].actionIntent
        approvals(m, 2, listOf(target(1, "new")))
        old.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(m.events.none { it.method == "approvalAction" })
        assertEquals("new", shadowOf(approval(1).actions[0].actionIntent).savedIntent.getStringExtra("generationRunId"))
    }

    @Test fun missingOrMalformedAcknowledgementDoesNotCountAsApproval() {
        val (_, m) = setup()
        m.acknowledgement = true
        approvals(m, 1, listOf(target(1)))
        approval(1).actions[1].actionIntent.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("Request expired", approval(1).extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals("deny", (m.events.single { it.method == "approvalAction" }.arguments as Map<*, *>)["action"])
    }

    @Test fun actionAfterProcessDeathDoesNotCreateAnEngineOrReplayToDart() {
        val (runtime, m) = setup()
        approvals(m, 1, listOf(target(1)))
        val action = approval(1).actions[0].actionIntent
        // Android retains the PendingIntent; the new application has an empty runtime.
        ReflectionHelpers.setField(app, "backgroundRuntime\$delegate", lazyOf(BackgroundRuntime(app)))
        action.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(app.hasEngine)
        assertTrue(m.events.none { it.method == "approvalAction" })
        assertEquals("Request expired", approval(1).extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertNotSame(runtime, app.backgroundRuntime)
    }

    @Test fun approvalReconciliationIgnoresOldRevisionsAndDoesNotClearResults() {
        val (_, m) = setup()
        result(m, "run")
        approvals(m, 2, listOf(target(1)))
        approvals(m, 1, listOf(target(2)))
        assertEquals(1, manager.activeNotifications.count { it.tag?.startsWith("moru.approval:") == true })
        approval(1)
        approvals(m, 3, emptyList())
        assertTrue(manager.activeNotifications.none { it.tag?.startsWith("moru.approval:") == true })
        assertTrue(manager.activeNotifications.any { it.tag == "moru.result:run" })
    }

    @Test fun privacyUpdatesAlreadyPostedApprovalsAndResults() {
        val (_, m) = setup()
        result(m, "run")
        approvals(m, 1, listOf(target(1)))
        m.call("sync", mapOf("revision" to 1, "settings" to mapOf("privacyMode" to true), "tasks" to emptyList<Any>()))
        assertEquals("Private task", approval(1).extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        val done = manager.activeNotifications.single { it.tag == "moru.result:run" }.notification
        assertEquals("Private result", done.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals("Finished", done.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
    }

    @Test fun resultTagsAndContentIntentsDoNotCollideForHashCollisionRuns() {
        val (runtime, m) = setup()
        assertEquals("Aa".hashCode(), "BB".hashCode())
        result(m, "Aa")
        result(m, "BB", "")
        val first = manager.activeNotifications.single { it.tag == "moru.result:Aa" }.notification
        val second = manager.activeNotifications.single { it.tag == "moru.result:BB" }.notification
        assertNotEquals(first.contentIntent, second.contentIntent)
        val intent = shadowOf(first.contentIntent).savedIntent
        runtime.receiveConversation(intent)
        val opened = m.events.single { it.method == "openConversation" }.arguments as Map<*, *>
        assertEquals("chat-Aa", opened["conversationId"])
        assertEquals("message-Aa", opened["assistantMessageId"])
    }

    @Test fun coldConversationTapRetainsTheMessageTargetExactlyOnce() {
        val runtime = app.backgroundRuntime
        val m = Messenger()
        runtime.configure(m)
        runtime.receiveConversation(Intent().putExtra(BackgroundRuntime.CONVERSATION_EXTRA, "chat")
            .putExtra("kelivo.background.message", "message"))
        var pending: Any? = null
        m.call("takePendingConversation") { pending = it }
        assertEquals(mapOf("conversationId" to "chat", "assistantMessageId" to "message"), pending)
        m.call("takePendingConversation") { pending = it }
        assertNull(pending)
    }

    @Test fun stopCancelsApprovalsWithoutMakingADecision() {
        val (runtime, m) = setup()
        approvals(m, 1, listOf(target(1)))
        val old = approval(1).actions[0].actionIntent
        runtime.stopTasks()
        assertTrue(manager.activeNotifications.none { it.tag?.startsWith("moru.approval:") == true })
        old.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(m.events.none { it.method == "approvalAction" })
    }

    @Test fun holdAcknowledgementWaitsForPromotionAndLastReleaseDropsTheWakeLock() {
        val (runtime, m) = setup()
        runtime.configureKeepAlive(m)
        var acknowledged: Any? = null
        m.call("hold", mapOf("id" to "server", "text" to "Local server"), "app.keep_alive") { acknowledged = it }
        assertNull("Starting the service is not yet foreground promotion", acknowledged)
        val service = Robolectric.buildService(GenerationForegroundService::class.java).create()
        service.get().onStartCommand(Intent(), 0, 1)
        assertEquals(true, acknowledged)
        val lock = ShadowPowerManager.getLatestWakeLock()
        assertTrue(lock.isHeld)
        m.call("hold", mapOf("id" to "shell"), "app.keep_alive")
        assertEquals(2, runtime.status()["keepAliveOwners"])
        m.call("release", mapOf("id" to "server"), "app.keep_alive")
        assertTrue(lock.isHeld)
        m.call("release", mapOf("id" to "shell"), "app.keep_alive")
        assertFalse(lock.isHeld)
        assertEquals(0, runtime.status()["activeOwners"])
        service.destroy()
    }

    @Test fun failedPromotionRejectsAndReleasesOnlyTheExactPendingOwners() {
        val (runtime, m) = setup()
        runtime.configureKeepAlive(m)
        var acknowledged: Any? = null
        m.call("hold", mapOf("id" to "pending"), "app.keep_alive") { acknowledged = it }
        runtime.serviceFailed("foreground_service_failed")
        assertEquals(false, acknowledged)
        assertEquals(0, runtime.status()["keepAliveOwners"])
        assertEquals(listOf("pending"), m.events.single { it.method == "released" }.arguments)
        assertFalse(runtime.shouldRunService())
    }

    @Test fun releaseBeforePromotionRejectsThePendingHoldAndLeavesNoWakeLock() {
        val (runtime, m) = setup()
        runtime.configureKeepAlive(m)
        var acknowledged: Any? = null
        m.call("hold", mapOf("id" to "pending"), "app.keep_alive") { acknowledged = it }
        m.call("release", mapOf("id" to "pending"), "app.keep_alive")
        assertEquals(false, acknowledged)
        val service = Robolectric.buildService(GenerationForegroundService::class.java).create()
        service.get().onStartCommand(Intent(), 0, 1)
        assertFalse(runtime.shouldRunService())
        assertNull(runtime.service)
        service.destroy()
    }

    @Test fun stopIntentDuringStartupRejectsPendingHoldsInsteadOfAcceptingAnUnprotectedLaunch() {
        val (runtime, m) = setup()
        runtime.configureKeepAlive(m)
        var acknowledged: Any? = null
        m.call("hold", mapOf("id" to "pending"), "app.keep_alive") { acknowledged = it }
        val service = Robolectric.buildService(GenerationForegroundService::class.java).create()
        service.get().onStartCommand(Intent().setAction(GenerationForegroundService.STOP), 0, 1)
        assertEquals(false, acknowledged)
        assertFalse(runtime.shouldRunService())
        assertNull(runtime.service)
        assertEquals(listOf("pending"), m.events.single { it.method == "released" }.arguments)
        service.destroy()
    }

    @Test fun statusReadsBackgroundRestrictionAndStandbyExemptionIndependently() {
        val (runtime, _) = setup()
        shadowOf(app.getSystemService(ActivityManager::class.java)).setBackgroundRestricted(true)
        val power = shadowOf(app.getSystemService(PowerManager::class.java))
        power.setLowPowerStandbySupported(true)
        power.setLowPowerStandbyEnabled(true)
        power.setExemptFromLowPowerStandby(false)
        val status = runtime.status()
        assertEquals(true, status["backgroundRestricted"])
        assertEquals(true, status["lowPowerStandbyEnabled"])
        assertEquals(false, status["lowPowerStandbyExempt"])
        power.setExemptFromLowPowerStandby(true)
        assertEquals(true, runtime.status()["lowPowerStandbyExempt"])
    }

    @Test fun deniedNotificationPermissionPostsNoApprovalOrResultAndRequestsNoPermission() {
        val (_, m) = setup()
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        approvals(m, 1, listOf(target(1)))
        result(m, "run")
        assertTrue(manager.activeNotifications.isEmpty())
        assertNull(shadowOf(app).nextStartedActivity)
    }

    @Test fun unresponsiveEngineAcknowledgementExpiresWithoutReplayingTheAction() {
        val (_, m) = setup()
        m.holdApprovalAcknowledgement = true
        approvals(m, 1, listOf(target(1)))
        approval(1).actions[0].actionIntent.send()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertEquals("Request expired", approval(1).extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals(1, m.events.count { it.method == "approvalAction" })
        assertFalse(app.hasEngine)
    }

    @Test fun resourceSnapshotCannotResurrectAResultTheUserDismissed() {
        val (_, m) = setup()
        result(m, "run")
        val posted = manager.activeNotifications.single { it.tag == "moru.result:run" }
        manager.cancel(posted.tag, posted.id)
        m.call("sync", mapOf("revision" to 1, "settings" to mapOf("privacyMode" to true), "tasks" to emptyList<Any>()))
        assertTrue(manager.activeNotifications.none { it.tag == "moru.result:run" })
    }

    @Test fun emptySnapshotAfterProcessDeathCancelsOnlyApprovalAlerts() {
        val (_, m) = setup()
        result(m, "run")
        approvals(m, 1, listOf(target(1)))
        ReflectionHelpers.setField(app, "backgroundRuntime\$delegate", lazyOf(BackgroundRuntime(app)))
        val next = Messenger()
        app.backgroundRuntime.configure(next)
        approvals(next, 1, emptyList())
        assertTrue(manager.activeNotifications.none { it.tag?.startsWith("moru.approval:") == true })
        assertTrue(manager.activeNotifications.any { it.tag == "moru.result:run" })
        assertFalse(app.hasEngine)
    }
}

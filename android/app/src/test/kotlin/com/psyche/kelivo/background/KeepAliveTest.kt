package com.psyche.kelivo.background

import com.psyche.kelivo.KelivoApplication
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.nio.ByteBuffer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = KelivoApplication::class)
class KeepAliveTest {
    /** Records what native sends to Dart and lets the test call native. */
    private class Messenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        val sent = mutableListOf<MethodCall>()
        override fun setMessageHandler(channel: String, value: BinaryMessenger.BinaryMessageHandler?) { handler = value }
        override fun send(channel: String, message: ByteBuffer?) { send(channel, message, null) }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            message?.let {
                it.rewind()
                sent.add(StandardMethodCodec.INSTANCE.decodeMethodCall(it))
            }
        }
        fun call(method: String, args: Any? = null) {
            val data = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args))
            data.flip()
            handler!!.onMessage(data) { }
        }
    }

    private val app get() = RuntimeEnvironment.getApplication() as KelivoApplication
    private val runtime get() = app.backgroundRuntime

    @Test fun holdsKeepTheServiceUntilReleased() {
        val m = Messenger().also { runtime.configureKeepAlive(it) }
        assertFalse(runtime.shouldRunService())
        m.call("hold", mapOf("id" to "web", "text" to "Web server: http://moru.local:8080"))
        assertTrue(runtime.shouldRunService())
        m.call("hold", mapOf("id" to "other", "text" to ""))
        m.call("release", mapOf("id" to "web"))
        assertTrue(runtime.shouldRunService())
        m.call("release", mapOf("id" to "other"))
        assertFalse(runtime.shouldRunService())
    }

    @Test fun stoppingFromTheNotificationReleasesTheHolders() {
        val m = Messenger().also { runtime.configureKeepAlive(it) }
        m.call("hold", mapOf("id" to "web", "text" to "Web server"))
        runtime.stopTasks()
        assertFalse(runtime.shouldRunService())
        val released = m.sent.single { it.method == "released" }
        assertEquals(listOf("web"), released.arguments)
    }

    @Test fun multicastLockCanBeTakenAndReturned() {
        val m = Messenger().also { runtime.configureKeepAlive(it) }
        m.call("multicast", mapOf("enabled" to true))
        m.call("multicast", mapOf("enabled" to true))
        m.call("multicast", mapOf("enabled" to false))
    }
}

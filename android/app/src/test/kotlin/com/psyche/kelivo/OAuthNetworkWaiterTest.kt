package com.psyche.kelivo

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 35], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class OAuthNetworkWaiterTest {
    private lateinit var manager: ConnectivityManager
    private lateinit var waiter: OAuthNetworkWaiter
    private val main get() = shadowOf(Looper.getMainLooper())

    @Before fun setUp() {
        manager = RuntimeEnvironment.getApplication().getSystemService(
            Context.CONNECTIVITY_SERVICE,
        ) as ConnectivityManager
        waiter = OAuthNetworkWaiter(manager)
    }

    @After fun tearDown() {
        waiter.close()
        main.idle()
        assertTrue(shadowOf(manager).networkCallbacks.isEmpty())
    }

    @Test fun waitsForUnblockedDefaultNetworkAndUnregisters() {
        val result = Result()
        waiter.awaitNetwork("one", 1000, result)
        val callback = shadowOf(manager).networkCallbacks.single()
        val network = Network(100)
        callback.onAvailable(network)
        main.idle()
        assertEquals(0, result.completions)
        if (Build.VERSION.SDK_INT >= 29) {
            callback.onBlockedStatusChanged(network, true)
            main.idle()
            assertEquals(0, result.completions)
            callback.onBlockedStatusChanged(network, false)
        } else {
            callback.onCapabilitiesChanged(network, internet())
        }
        main.idle()
        assertEquals(1, result.completions)
        assertNull(result.error)
        assertTrue(shadowOf(manager).networkCallbacks.isEmpty())
    }

    @Test fun cancellationDoesNotCompleteASecondTimeOnLateCallback() {
        val result = Result()
        waiter.awaitNetwork("one", 1000, result)
        val callback = shadowOf(manager).networkCallbacks.single()
        waiter.cancel("one")
        ready(callback, Network(100))
        main.idle()
        assertEquals("authorization_cancelled", result.error)
        assertEquals(1, result.completions)
    }

    @Test fun timeoutUnregistersEvenWithoutAnyNetwork() {
        val result = Result()
        waiter.awaitNetwork("one", 1000, result)
        main.idleFor(Duration.ofMillis(1001))
        assertEquals("network_timeout", result.error)
        assertEquals(1, result.completions)
        assertTrue(shadowOf(manager).networkCallbacks.isEmpty())
    }

    @Test fun lostNetworkCannotReleaseAWaitForItsReplacement() {
        val result = Result()
        waiter.awaitNetwork("one", 1000, result)
        val callback = shadowOf(manager).networkCallbacks.single()
        val old = Network(100)
        val replacement = Network(101)
        callback.onAvailable(old)
        callback.onLost(old)
        callback.onAvailable(replacement)
        if (Build.VERSION.SDK_INT >= 29) {
            callback.onBlockedStatusChanged(old, false)
        } else {
            callback.onCapabilitiesChanged(old, internet())
        }
        main.idle()
        assertEquals(0, result.completions)
        ready(callback, replacement)
        main.idle()
        assertEquals(1, result.completions)
        assertNull(result.error)
    }

    @Test fun cancellingOneSessionDoesNotCancelAnother() {
        val first = Result()
        val second = Result()
        waiter.awaitNetwork("one", 1000, first)
        waiter.awaitNetwork("two", 1000, second)
        waiter.cancel("one")
        assertEquals("authorization_cancelled", first.error)
        assertEquals(0, second.completions)
        val callback = shadowOf(manager).networkCallbacks.single()
        ready(callback, Network(101))
        main.idle()
        assertEquals(1, second.completions)
        assertNull(second.error)
    }

    private fun internet() = NetworkCapabilities().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun ready(callback: ConnectivityManager.NetworkCallback, network: Network) {
        callback.onAvailable(network)
        if (Build.VERSION.SDK_INT >= 29) {
            callback.onBlockedStatusChanged(network, false)
        } else {
            callback.onCapabilitiesChanged(network, internet())
        }
    }

    private class Result : MethodChannel.Result {
        var completions = 0
        var error: String? = null
        override fun success(result: Any?) { completions++ }
        override fun error(code: String, message: String?, details: Any?) {
            completions++
            error = code
        }
        override fun notImplemented() { fail("Unexpected method") }
    }
}

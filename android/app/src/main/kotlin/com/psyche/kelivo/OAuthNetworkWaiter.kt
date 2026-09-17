package com.psyche.kelivo

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** A bounded, cancellable wait for this application's default (including VPN)
 * network. Does not change routing, DNS, background policy or TLS validation. */
internal class OAuthNetworkWaiter(
    private val manager: ConnectivityManager,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val pending = mutableMapOf<String, Pending>()
    private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id.isNullOrEmpty()) {
            result.error("invalid_arguments", "A network wait ID is required.", null)
            return
        }
        when (call.method) {
            "awaitNetwork" -> awaitNetwork(
                id,
                (call.argument<Number>("timeoutMillis")?.toLong() ?: 900_000L)
                    .coerceIn(1L, 900_000L),
                result,
            )
            "cancelNetworkWait" -> {
                cancel(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun awaitNetwork(id: String, timeoutMillis: Long, result: MethodChannel.Result) {
        if (closed) {
            result.error("authorization_cancelled", "The login session was closed.", null)
            return
        }
        // Default-network callbacks were added in Android 7. Older supported
        // runtimes still use the Dart foreground gate, without a native wait.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.success(null)
            return
        }
        cancel(id)
        val entry = Pending(id, result)
        pending[id] = entry
        main.postDelayed(entry.timeout, timeoutMillis.coerceIn(1L, 900_000L))
        try {
            manager.registerDefaultNetworkCallback(entry.callback)
        } catch (_: RuntimeException) {
            finish(entry, "network_unavailable")
        }
    }

    fun cancel(id: String) {
        pending[id]?.let { finish(it, "authorization_cancelled") }
    }

    fun close() {
        closed = true
        pending.values.toList().forEach { finish(it, "authorization_cancelled") }
    }

    private fun finish(entry: Pending, error: String? = null) {
        if (pending[entry.id] !== entry) return
        pending.remove(entry.id)
        main.removeCallbacks(entry.timeout)
        runCatching { manager.unregisterNetworkCallback(entry.callback) }
        if (error == null) entry.result.success(null)
        else entry.result.error(error, "The login network wait did not complete.", null)
    }

    private inner class Pending(val id: String, val result: MethodChannel.Result) {
        var network: Network? = null
        val timeout = Runnable { finish(this, "network_timeout") }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post { if (pending[id] === this@Pending) this@Pending.network = network }
            }

            override fun onLost(network: Network) {
                main.post {
                    if (this@Pending.network == network) this@Pending.network = null
                }
            }

            override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
                main.post {
                    if (this@Pending.network == network && !blocked) finish(this@Pending)
                }
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                // Android 10+ reports per-UID blocking separately. onAvailable
                // alone is not evidence that a background UID may use a network.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return
                val internet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                main.post {
                    if (this@Pending.network == network && internet) finish(this@Pending)
                }
            }
        }
    }
}

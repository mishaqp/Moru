package com.psyche.kelivo

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

/** Shared, coalesced observers exist only while a Dart/native viewer watches. */
class MiniAppDeviceEvents(
    private val context: Context,
    private val snapshot: () -> Map<String, Any?>,
    private val torchChanged: (String, Boolean?, String?) -> Unit,
    private val worker: Executor,
) {
    private val main = Handler(Looper.getMainLooper())
    private val watchers = LinkedHashSet<(Map<String, Any?>) -> Unit>()
    private var receiver: BroadcastReceiver? = null
    private var observer: ContentObserver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var torchCallback: CameraManager.TorchCallback? = null
    private var generation = 0
    val watcherCount get() = synchronized(watchers) { watchers.size }

    fun watch(listener: (Map<String, Any?>) -> Unit): AutoCloseable {
        synchronized(watchers) {
            val first = watchers.isEmpty()
            watchers.add(listener)
            if (first) { generation++; start() }
        }
        refresh()
        val closed = AtomicBoolean(false)
        return AutoCloseable {
            if (closed.compareAndSet(false, true)) synchronized(watchers) {
                watchers.remove(listener)
                if (watchers.isEmpty()) { generation++; stop() }
            }
        }
    }

    private val emit = Runnable {
        val captured = synchronized(watchers) { if (watchers.isEmpty()) null else generation } ?: return@Runnable
        worker.execute {
            val state = snapshot()
            main.post {
                val listeners = synchronized(watchers) { if (captured == generation) watchers.toList() else emptyList() }
                listeners.forEach { it(state) }
            }
        }
    }

    fun refresh() {
        synchronized(watchers) {
            if (watchers.isEmpty()) return
            main.removeCallbacks(emit)
            main.postDelayed(emit, 160)
        }
    }

    private fun start() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            addAction(android.net.wifi.WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
            addAction("android.media.VOLUME_CHANGED_ACTION")
            addAction("android.app.action.INTERRUPTION_FILTER_CHANGED")
            addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED)
        }
        val freshReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { refresh() }
        }
        runCatching {
            // Payloads are ignored; even a spoofed notification triggers only
            // a fresh Android read. Bluetooth system apps use a separate UID.
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(freshReceiver, filter, Context.RECEIVER_EXPORTED)
            else @Suppress("DEPRECATION") context.registerReceiver(freshReceiver, filter)
            receiver = freshReceiver
        }
        val freshObserver = object : ContentObserver(main) {
            override fun onChange(selfChange: Boolean) { refresh() }
        }
        runCatching {
            context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, freshObserver)
            // Keep the first registration owned even if the second one fails.
            observer = freshObserver
            context.contentResolver.registerContentObserver(Settings.Global.CONTENT_URI, true, freshObserver)
        }
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val freshNetwork = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { refresh() }
            override fun onLost(network: Network) { refresh() }
            override fun onCapabilitiesChanged(network: Network, caps: android.net.NetworkCapabilities) { refresh() }
        }
        runCatching { connectivity?.registerDefaultNetworkCallback(freshNetwork); if (connectivity != null) networkCallback = freshNetwork }
        val camera = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        val freshTorch = object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(cameraId: String, enabled: Boolean) { torchChanged(cameraId, enabled, null); refresh() }
            override fun onTorchModeUnavailable(cameraId: String) { torchChanged(cameraId, null, "camera_unavailable"); refresh() }
        }
        runCatching { camera?.registerTorchCallback(freshTorch, main); if (camera != null) torchCallback = freshTorch }
    }

    private fun stop() {
        main.removeCallbacks(emit)
        receiver?.let { runCatching { context.unregisterReceiver(it) } }; receiver = null
        observer?.let { runCatching { context.contentResolver.unregisterContentObserver(it) } }; observer = null
        networkCallback?.let { callback -> runCatching { (context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)?.unregisterNetworkCallback(callback) } }; networkCallback = null
        torchCallback?.let { callback -> runCatching { (context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager)?.unregisterTorchCallback(callback) } }; torchCallback = null
    }
}

package com.psyche.kelivo

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Fixed typed Android operations. The shared runtime owns app grants/consent. */
class MiniAppDeviceHandler(
    context: Context,
    private val rootRunner: MiniAppRootRunner = MiniAppRootRunner(),
    private val readbackTimeoutMs: Long = 1500,
) {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "mini-app-device").apply { isDaemon = true } }
    private var activity = WeakReference<Activity>(null)
    @Volatile private var foreground = false
    private var messenger: BinaryMessenger? = null
    private var channel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventWatch: AutoCloseable? = null
    private val pending = ConcurrentHashMap<String, MiniAppRootCancellation>()
    private val packages = MiniAppPackages(this.context)
    private val torchValues = ConcurrentHashMap<String, TorchValue>()
    private val torchThread by lazy { HandlerThread("mini-app-torch-read").apply { start() } }
    @Volatile private var rootAvailable: Boolean? = null
    @Volatile private var rootReason: String? = "not_checked"

    val events = MiniAppDeviceEvents(this.context, { snapshot() }, { id, enabled, reason -> torchValues[id] = TorchValue(enabled, reason) }, worker)

    fun attachActivity(value: Activity) { foreground = false; activity = WeakReference(value) }
    fun detachActivity(value: Activity) { if (activity.get() === value) { foreground = false; activity.clear() } }
    fun setForeground(value: Activity, enabled: Boolean) { if (activity.get() === value) foreground = enabled }
    fun refresh() { events.refresh() }

    fun configure(value: BinaryMessenger) {
        if (messenger === value) return
        eventWatch?.close(); eventWatch = null
        channel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        messenger = value
        channel = MethodChannel(value, "app.mini_app_device").also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> worker.execute { val state = snapshot(); main.post { result.success(state) } }
                    "cancel" -> {
                        val id = call.argument<String>("requestId")
                        if (id != null) pending[id]?.cancel()
                        result.success(null)
                    }
                    "execute" -> {
                        val raw = call.arguments as? Map<*, *>
                        val handler = raw?.get("handler") as? String
                        val id = raw?.get("requestId") as? String
                        val rawArgs = raw?.get("args") as? Map<*, *>
                        if (raw == null || raw.keys.any { it !in setOf("handler", "args", "requestId") } || handler == null || id == null || !Regex("^[A-Za-z0-9_-]{1,80}$").matches(id) || rawArgs == null || rawArgs.keys.any { it !is String }) {
                            result.success(mapOf("status" to "failed", "message" to "Invalid device request.", "state" to emptyMap<String, Any?>()))
                            return@setMethodCallHandler
                        }
                        if (pending.size >= 16) {
                            result.success(mapOf("status" to "failed", "message" to "Too many pending device requests.", "state" to emptyMap<String, Any?>()))
                            return@setMethodCallHandler
                        }
                        val token = MiniAppRootCancellation()
                        if (pending.putIfAbsent(id, token) != null) {
                            result.success(mapOf("status" to "failed", "message" to "Duplicate device request.", "state" to emptyMap<String, Any?>()))
                            return@setMethodCallHandler
                        }
                        val args = rawArgs.entries.associate { it.key as String to it.value }
                        worker.execute {
                            val reply = try { execute(handler, args, token) } finally { pending.remove(id, token) }
                            main.post { result.success(reply) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        eventChannel = EventChannel(value, "app.mini_app_device/events").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventWatch?.close()
                    torchValues.clear()
                    eventWatch = events.watch { state -> sink.success(state) }
                }
                override fun onCancel(arguments: Any?) { eventWatch?.close(); eventWatch = null }
            })
        }
    }

    private class Group {
        private val fields = linkedMapOf<String, Any?>()
        private val reasons = linkedMapOf<String, String>()
        fun put(key: String, value: Any?, reason: String = "sensor_unavailable") {
            fields[key] = value
            if (value == null) reasons[key] = reason
        }
        fun finish(): Map<String, Any?> = fields + ("reasons" to reasons)
        fun reason(key: String, reason: String) { reasons[key] = reason }
    }

    fun snapshot(): Map<String, Any?> = linkedMapOf(
        "battery" to battery(),
        "screen" to screen(),
        "audio" to audio(),
        "connectivity" to connectivity(),
        "flashlight" to flashlight(),
        "system" to system(),
        "observedAtMs" to System.currentTimeMillis(),
    )

    private fun battery(): Map<String, Any?> {
        val group = Group()
        val sticky = runCatching { context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) }.getOrNull()
        fun extra(key: String): Int? = sticky?.takeIf { it.hasExtra(key) }?.getIntExtra(key, Int.MIN_VALUE)?.takeIf { it != Int.MIN_VALUE }
        val level = extra(BatteryManager.EXTRA_LEVEL)
        val scale = extra(BatteryManager.EXTRA_SCALE)
        val percent = if (level != null && scale != null && scale > 0 && level in 0..scale) level * 100.0 / scale else null
        val status = extra(BatteryManager.EXTRA_STATUS)
        val plugged = extra(BatteryManager.EXTRA_PLUGGED)
        group.put("levelPercent", percent)
        group.put("charging", status?.let { it == BatteryManager.BATTERY_STATUS_CHARGING || (it == BatteryManager.BATTERY_STATUS_FULL && plugged != null && plugged != 0) })
        group.put("status", when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not_charging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            else -> null
        })
        group.put("plugged", when (plugged) { 0 -> "none"; BatteryManager.BATTERY_PLUGGED_AC -> "ac"; BatteryManager.BATTERY_PLUGGED_USB -> "usb"; BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"; 8 -> "dock"; else -> null })
        group.put("temperatureC", extra(BatteryManager.EXTRA_TEMPERATURE)?.takeIf { it in -400..1200 }?.div(10.0))
        group.put("voltageMv", extra(BatteryManager.EXTRA_VOLTAGE)?.takeIf { it in 1..20000 })
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        fun intProperty(id: Int): Int? = runCatching { manager?.getIntProperty(id)?.takeIf { it != Int.MIN_VALUE } }.getOrNull()
        group.put("currentMicroamps", intProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
        group.put("currentAverageMicroamps", intProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE))
        group.put("chargeCounterMicroampHours", intProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)?.takeIf { it >= 0 })
        group.put("energyNanowattHours", runCatching { manager?.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)?.takeIf { it >= 0 } }.getOrNull())
        group.put("chargeTimeRemainingMs", if (Build.VERSION.SDK_INT >= 28) runCatching { manager?.computeChargeTimeRemaining()?.takeIf { it >= 0 } }.getOrNull() else null, if (Build.VERSION.SDK_INT < 28) "unsupported_android_version" else "estimate_unavailable")
        group.put("cycleCount", if (Build.VERSION.SDK_INT >= 34) extra(BatteryManager.EXTRA_CYCLE_COUNT)?.takeIf { it >= 0 } else null, if (Build.VERSION.SDK_INT < 34) "unsupported_android_version" else "sensor_unavailable")
        group.put("powerSave", runCatching { (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode }.getOrNull(), "service_unavailable")
        return group.finish()
    }

    private fun systemSetting(key: String): Int? = runCatching { Settings.System.getInt(context.contentResolver, key) }.getOrNull()

    private fun screen(): Map<String, Any?> {
        val group = Group()
        group.put("brightness", systemSetting(Settings.System.SCREEN_BRIGHTNESS)?.takeIf { it in 0..255 }, "setting_unavailable")
        group.put("brightnessMode", when (systemSetting(Settings.System.SCREEN_BRIGHTNESS_MODE)) { Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL -> "manual"; Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC -> "automatic"; else -> null }, "setting_unavailable")
        group.put("timeoutMs", systemSetting(Settings.System.SCREEN_OFF_TIMEOUT), "setting_unavailable")
        group.put("interactive", runCatching { (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isInteractive }.getOrNull(), "service_unavailable")
        group.put("canWrite", runCatching { Settings.System.canWrite(context) }.getOrDefault(false))
        group.put("refreshRateHz", runCatching { (context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)?.getDisplay(Display.DEFAULT_DISPLAY)?.refreshRate?.takeIf { it > 0 && it.isFinite() } }.getOrNull(), "display_unavailable")
        return group.finish()
    }

    private fun audio(): Map<String, Any?> {
        val group = Group()
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        group.put("volumes", manager?.let {
            STREAM_IDS.mapValues { (_, id) ->
                runCatching { mapOf("value" to it.getStreamVolume(id), "max" to it.getStreamMaxVolume(id), "min" to if (Build.VERSION.SDK_INT >= 28) it.getStreamMinVolume(id) else 0) }.getOrNull()
            }
        }, "service_unavailable")
        group.put("ringerMode", when (runCatching { manager?.ringerMode }.getOrNull()) { AudioManager.RINGER_MODE_NORMAL -> "normal"; AudioManager.RINGER_MODE_VIBRATE -> "vibrate"; AudioManager.RINGER_MODE_SILENT -> "silent"; else -> null }, "service_unavailable")
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        group.put("dnd", runCatching { dndName(notifications?.currentInterruptionFilter) }.getOrNull(), "service_unavailable")
        val policyAccess = runCatching { notifications?.isNotificationPolicyAccessGranted }.getOrDefault(false) ?: false
        group.put("canAccessDnd", policyAccess)
        group.put("canChangeDnd", Build.VERSION.SDK_INT < 35 && policyAccess)
        if (Build.VERSION.SDK_INT >= 35) group.reason("canChangeDnd", "unsupported_android_version")
        return group.finish()
    }

    private fun hasPermission(permission: String): Boolean = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun wifiEnabled(): Boolean? = runCatching { (context.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.isWifiEnabled }.getOrNull()
    private fun bluetoothEnabled(): Boolean? {
        if (Build.VERSION.SDK_INT >= 31 && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) return null
        return runCatching { (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter?.isEnabled }.getOrNull()
    }

    private fun mobileDataEnabled(): Boolean? = runCatching {
        var manager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val subscription = SubscriptionManager.getDefaultDataSubscriptionId()
        if (subscription != SubscriptionManager.INVALID_SUBSCRIPTION_ID) manager = manager?.createForSubscriptionId(subscription)
        manager?.isDataEnabled
    }.getOrNull()

    private fun connectivity(): Map<String, Any?> {
        val group = Group()
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val network = runCatching { manager?.activeNetwork }.getOrNull()
        val caps = runCatching { manager?.getNetworkCapabilities(network) }.getOrNull()
        group.put("connected", manager?.let { network != null }, "permission_required")
        group.put("validated", manager?.let { caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ?: false }, "permission_required")
        group.put("metered", runCatching { manager?.isActiveNetworkMetered }.getOrNull(), "permission_required")
        group.put("networkType", when {
            manager == null -> null
            network == null -> "none"
            caps == null -> null
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }, "network_unavailable")
        group.put("wifiEnabled", wifiEnabled(), "service_or_permission_unavailable")
        group.put("bluetoothEnabled", bluetoothEnabled(), if (Build.VERSION.SDK_INT >= 31 && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) "permission_required" else "adapter_unavailable")
        group.put("mobileDataEnabled", mobileDataEnabled(), "phone_state_permission_or_subscription_unavailable")
        group.put("airplaneMode", runCatching { Settings.Global.getInt(context.contentResolver, Settings.Global.AIRPLANE_MODE_ON) != 0 }.getOrNull(), "setting_unavailable")
        return group.finish()
    }

    private data class TorchValue(val enabled: Boolean?, val reason: String?)
    private fun flashCameraId(): String? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return null
        return manager.cameraIdList.take(16).sortedBy { id -> if (manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK) 0 else 1 }
            .firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true }
    }

    private fun torchValue(cameraId: String): TorchValue {
        if (events.watcherCount > 0) torchValues[cameraId]?.let { return it }
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return TorchValue(null, "camera_unavailable")
        val latch = CountDownLatch(1)
        var value = TorchValue(null, "read_timeout")
        val callback = object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(id: String, enabled: Boolean) { if (id == cameraId) { value = TorchValue(enabled, null); latch.countDown() } }
            override fun onTorchModeUnavailable(id: String) { if (id == cameraId) { value = TorchValue(null, "camera_unavailable"); latch.countDown() } }
        }
        try {
            // Android has no torch getter. This one-shot subscription is bounded
            // and always removed, even when no mini-app screen is open.
            manager.registerTorchCallback(callback, Handler(torchThread.looper))
            latch.await(300, TimeUnit.MILLISECONDS)
        } catch (_: SecurityException) { value = TorchValue(null, "permission_required") }
        catch (_: Exception) { value = TorchValue(null, "camera_unavailable") }
        finally { runCatching { manager.unregisterTorchCallback(callback) } }
        return value
    }

    private fun flashlight(): Map<String, Any?> {
        val group = Group()
        val discovered = runCatching { flashCameraId() }
        val cameraId = discovered.getOrNull()
        val value = cameraId?.let { torchValue(it) }
        group.put("available", if (discovered.isSuccess) cameraId != null else null, if (discovered.exceptionOrNull() is SecurityException) "permission_required" else "camera_unavailable")
        group.put("enabled", value?.enabled, value?.reason ?: "no_flash_camera")
        group.put("canControl", cameraId != null && hasPermission(Manifest.permission.CAMERA))
        return group.finish()
    }

    private fun system(): Map<String, Any?> {
        val group = Group()
        group.put("sdkInt", Build.VERSION.SDK_INT)
        group.put("uptimeMs", SystemClock.elapsedRealtime())
        group.put("androidVersion", Build.VERSION.RELEASE)
        group.put("manufacturer", Build.MANUFACTURER)
        group.put("model", Build.MODEL)
        group.put("appVersion", runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull(), "package_unavailable")
        val memory = runCatching { (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)?.let { manager -> ActivityManager.MemoryInfo().also { manager.getMemoryInfo(it) } } }.getOrNull()
        group.put("totalRamBytes", memory?.totalMem?.takeIf { it > 0 })
        group.put("availableRamBytes", memory?.availMem?.takeIf { it >= 0 })
        val storage = runCatching { StatFs(context.filesDir.absolutePath) }.getOrNull()
        group.put("totalStorageBytes", storage?.totalBytes?.takeIf { it > 0 })
        group.put("freeStorageBytes", storage?.availableBytes?.takeIf { it >= 0 })
        group.put("rootAvailable", rootAvailable, rootReason ?: "not_checked")
        group.put("rootReason", rootReason, "available")
        group.put("stoppableApps", runCatching { packages.list() }.getOrNull(), "package_visibility_unavailable")
        return group.finish()
    }

    fun execute(handler: String, args: Map<String, Any?>, cancellation: MiniAppRootCancellation = MiniAppRootCancellation()): Map<String, Any?> {
        val invalid = MiniAppDeviceCatalog.validate(handler, args)
        if (invalid != null) return result(if (invalid.startsWith("Unknown")) "unsupported" else "failed", invalid)
        if (cancellation.isCancelled) return result("denied", "The device request was cancelled before execution.")
        if (handler.endsWith(".get")) return result("applied", "Read the current Android state.")
        if (handler == "device.settings.open") return openSettings(args, cancellation)
        if (handler.startsWith("device.root.")) return executeRoot(handler, args, cancellation)
        try {
            when (handler) {
                "device.screen.brightness.set", "device.screen.timeout.set" -> {
                    if (!Settings.System.canWrite(context)) return result("permission_required", "Allow Moru to modify system settings in Android Settings.")
                    val written = if (handler == "device.screen.brightness.set") {
                        val valueWritten = Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, (args["value"] as Number).toInt())
                        val mode = args["mode"] as? String
                        val modeWritten = mode == null || Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, if (mode == "automatic") Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC else Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                        valueWritten && modeWritten
                    } else Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, (args["milliseconds"] as Number).toInt())
                    if (!written) return result("failed", "Android rejected part or all of the system setting change.")
                }
                "device.audio.volume.set" -> {
                    val manager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return result("unsupported", "Android audio controls are unavailable.")
                    val stream = STREAM_IDS[args["stream"]]!!
                    val value = (args["value"] as Number).toInt()
                    val min = if (Build.VERSION.SDK_INT >= 28) manager.getStreamMinVolume(stream) else 0
                    if (value !in min..manager.getStreamMaxVolume(stream)) return result("failed", "The requested volume is outside this device's stream range.")
                    manager.setStreamVolume(stream, value, 0)
                }
                "device.audio.dnd.set" -> {
                    // With Moru's modern target on Android 15+, this setter
                    // changes a Moru-owned implicit rule, not the global filter
                    // we read/restore. Keep that unsupported instead of changing
                    // another state under a misleading global-state contract.
                    if (Build.VERSION.SDK_INT >= 35) return result("unsupported", "Use Android Do Not Disturb settings on Android 15 or newer.")
                    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return result("unsupported", "Do Not Disturb is unavailable.")
                    if (!manager.isNotificationPolicyAccessGranted) return result("permission_required", "Allow Moru to change Do Not Disturb in Android Settings.")
                    manager.setInterruptionFilter(DND_IDS[args["mode"]]!!)
                }
                "device.flashlight.set" -> {
                    if (!hasPermission(Manifest.permission.CAMERA)) return result("permission_required", "Allow camera access for Moru in Android app permissions.")
                    val cameraId = flashCameraId() ?: return result("unsupported", "This device has no available flashlight camera.")
                    (context.getSystemService(Context.CAMERA_SERVICE) as CameraManager).setTorchMode(cameraId, args["enabled"] as Boolean)
                }
            }
        } catch (_: SecurityException) { return result("permission_required", "Android requires additional access for this operation.") }
        catch (_: UnsupportedOperationException) { return result("unsupported", "Android does not support this device operation.") }
        catch (_: Exception) { return result("failed", "Android rejected the device operation.") }
        return verifyResult(handler, args, cancellation)
    }

    private fun executeRoot(handler: String, args: Map<String, Any?>, cancellation: MiniAppRootCancellation): Map<String, Any?> {
        if (handler == "device.root.stop_app" && packages.selected(args["packageName"] as String) == null) return result("denied", "Choose a currently installed, unprotected app from the app list.")
        val command = MiniAppDeviceCatalog.rootCommand(handler, args, android.os.Process.myUid() / 100000) ?: return result("unsupported", "Unknown fixed root operation.")
        val commandResult = rootRunner.execute(command, cancellation)
        when (commandResult.outcome) {
            MiniAppRootRunner.Outcome.COMPLETED -> { rootAvailable = true; rootReason = null }
            MiniAppRootRunner.Outcome.DENIED -> { rootAvailable = false; rootReason = "root_denied"; return result("denied", "The device root manager denied this operation.") }
            MiniAppRootRunner.Outcome.UNAVAILABLE -> { rootAvailable = false; rootReason = "su_unavailable"; return result("unsupported", "The device root command is unavailable.") }
            MiniAppRootRunner.Outcome.UNSUPPORTED -> { rootAvailable = null; rootReason = "command_unsupported"; return result("unsupported", "This Android version does not support the fixed root command.") }
            MiniAppRootRunner.Outcome.TIMED_OUT, MiniAppRootRunner.Outcome.CANCELLED -> { rootAvailable = null; rootReason = "command_timeout_or_cancelled"; return result("unknown_after_timeout", "The root request was interrupted before Android's outcome could be confirmed.") }
            MiniAppRootRunner.Outcome.FAILED -> { rootAvailable = null; rootReason = "command_failed"; return result("failed", "The fixed root command failed. Check the actual device state.") }
        }
        return verifyResult(handler, args, cancellation)
    }

    private fun expectedValue(handler: String, args: Map<String, Any?>): Any? = when (handler) {
        "device.screen.brightness.set" -> systemSetting(Settings.System.SCREEN_BRIGHTNESS)?.let { value -> if (args.containsKey("mode")) listOf(value, when (systemSetting(Settings.System.SCREEN_BRIGHTNESS_MODE)) { 0 -> "manual"; 1 -> "automatic"; else -> null }) else value }
        "device.screen.timeout.set" -> systemSetting(Settings.System.SCREEN_OFF_TIMEOUT)
        "device.audio.volume.set" -> runCatching { (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.getStreamVolume(STREAM_IDS[args["stream"]]!!) }.getOrNull()
        "device.audio.dnd.set", "device.root.dnd.set" -> runCatching { dndName((context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)?.currentInterruptionFilter) }.getOrNull()
        "device.flashlight.set" -> runCatching { flashCameraId()?.let { torchValue(it).enabled } }.getOrNull()
        "device.root.power_save.set" -> runCatching { (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode }.getOrNull()
        "device.root.wifi.set" -> wifiEnabled()
        "device.root.bluetooth.set" -> bluetoothEnabled()
        "device.root.data.set" -> mobileDataEnabled()
        "device.root.airplane.set" -> runCatching { Settings.Global.getInt(context.contentResolver, Settings.Global.AIRPLANE_MODE_ON) != 0 }.getOrNull()
        "device.root.stop_app" -> packages.isStopped(args["packageName"] as String)
        else -> null
    }

    private fun desiredValue(handler: String, args: Map<String, Any?>): Any? = when (handler) {
        "device.screen.brightness.set" -> if (args.containsKey("mode")) listOf((args["value"] as Number).toInt(), args["mode"]) else (args["value"] as Number).toInt()
        "device.screen.timeout.set" -> (args["milliseconds"] as Number).toInt()
        "device.audio.volume.set" -> (args["value"] as Number).toInt()
        "device.audio.dnd.set", "device.root.dnd.set" -> args["mode"]
        "device.root.stop_app" -> true
        else -> args["enabled"]
    }

    private fun verifyResult(handler: String, args: Map<String, Any?>, cancellation: MiniAppRootCancellation): Map<String, Any?> {
        val desired = desiredValue(handler, args)
        val deadline = System.nanoTime() + readbackTimeoutMs.coerceIn(0, 3000) * 1_000_000
        var actual = expectedValue(handler, args)
        while (actual != desired && actual != null && !cancellation.isCancelled && System.nanoTime() < deadline) {
            try { Thread.sleep(40) } catch (_: InterruptedException) { Thread.currentThread().interrupt(); break }
            actual = expectedValue(handler, args)
        }
        events.refresh()
        return when {
            cancellation.isCancelled -> result("unknown_after_timeout", "The device request was cancelled after it may have changed Android state.")
            actual == desired -> result("applied", "Android confirmed the requested state.")
            actual == null -> result("unknown_after_timeout", "The request finished, but Android could not report the actual state.")
            else -> result("failed", "Android's actual state does not match the requested change.")
        }
    }

    private fun openSettings(args: Map<String, Any?>, cancellation: MiniAppRootCancellation): Map<String, Any?> {
        val page = args["page"] as String
        val packageName = args["packageName"] as? String
        if (packageName != null && runCatching { packages.selected(packageName) }.getOrNull() == null) return result("denied", "Choose a currently installed, unprotected app from the app list.")
        val owner = activity.get()?.takeIf { foreground && it.hasWindowFocus() && !it.isFinishing && !it.isDestroyed } ?: return result("permission_required", "Open Moru in the foreground to visit Android Settings.")
        val intent = when (page) {
            "battery" -> Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
            "power_save" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            "mobile_data" -> Intent(Settings.ACTION_DATA_ROAMING_SETTINGS)
            "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            "write_settings" -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}"))
            "dnd" -> Intent("android.settings.ZEN_MODE_SETTINGS")
            "dnd_access" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${packageName ?: context.packageName}"))
        }
        val expired = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        var status = "failed"
        val launch = Runnable {
            try {
                if (expired.get() || cancellation.isCancelled) { status = "denied"; return@Runnable }
                if (activity.get() !== owner || !foreground || !owner.hasWindowFocus() || owner.isFinishing || owner.isDestroyed) { status = "permission_required"; return@Runnable }
                try { owner.startActivity(intent) }
                catch (_: ActivityNotFoundException) { owner.startActivity(Intent(if (page == "dnd") Settings.ACTION_SOUND_SETTINGS else Settings.ACTION_SETTINGS)) }
                status = "opened_settings"
            } catch (_: ActivityNotFoundException) { status = "unsupported" }
            catch (_: SecurityException) { status = "denied" }
            finally { latch.countDown() }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) launch.run() else main.post(launch)
        if (!latch.await(1000, TimeUnit.MILLISECONDS)) { expired.set(true); status = "unknown_after_timeout" }
        return result(status, if (status == "opened_settings") "Opened Android Settings. The setting has not been changed by Moru." else "Android Settings could not be opened.")
    }

    private fun result(status: String, message: String): Map<String, Any?> = mapOf("status" to status, "message" to message, "state" to snapshot())

    companion object {
        private val STREAM_IDS = mapOf("music" to AudioManager.STREAM_MUSIC, "ring" to AudioManager.STREAM_RING, "notification" to AudioManager.STREAM_NOTIFICATION, "alarm" to AudioManager.STREAM_ALARM, "system" to AudioManager.STREAM_SYSTEM, "voice_call" to AudioManager.STREAM_VOICE_CALL)
        private val DND_IDS = mapOf("all" to NotificationManager.INTERRUPTION_FILTER_ALL, "priority" to NotificationManager.INTERRUPTION_FILTER_PRIORITY, "none" to NotificationManager.INTERRUPTION_FILTER_NONE, "alarms" to NotificationManager.INTERRUPTION_FILTER_ALARMS)
        private fun dndName(value: Int?): String? = DND_IDS.entries.firstOrNull { it.value == value }?.key
        @Volatile private var shared: MiniAppDeviceHandler? = null
        fun shared(context: Context): MiniAppDeviceHandler = shared ?: synchronized(this) { shared ?: MiniAppDeviceHandler(context).also { shared = it } }
    }
}

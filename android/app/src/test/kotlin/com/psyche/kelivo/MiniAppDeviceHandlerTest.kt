package com.psyche.kelivo

import android.app.Application
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ActivityInfo
import android.content.pm.PackageInfo
import android.content.pm.ResolveInfo
import android.os.BatteryManager
import android.os.SystemClock
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30], manifest = Config.NONE, application = Application::class, shadows = [MiniAppDeviceHandlerTest.MissingBatterySensors::class])
class MiniAppDeviceHandlerTest {
    class SettingsActivity : Activity() {
        var focused = true
        override fun hasWindowFocus(): Boolean = focused
    }
    @Implements(BatteryManager::class)
    class MissingBatterySensors {
        @Implementation fun getIntProperty(id: Int): Int = Int.MIN_VALUE
        @Implementation fun getLongProperty(id: Int): Long = Long.MIN_VALUE
        @Implementation fun computeChargeTimeRemaining(): Long = -1L
    }

    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun batteryReadsStickyAndroidValuesAndKeepsMissingSensorsNullWithReasons() {
        context.sendStickyBroadcast(Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra(BatteryManager.EXTRA_LEVEL, 30)
            putExtra(BatteryManager.EXTRA_SCALE, 60)
            putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_CHARGING)
            putExtra(BatteryManager.EXTRA_PLUGGED, BatteryManager.BATTERY_PLUGGED_USB)
            putExtra(BatteryManager.EXTRA_TEMPERATURE, 321)
            putExtra(BatteryManager.EXTRA_VOLTAGE, 4100)
        })
        val battery = MiniAppDeviceHandler(context).snapshot()["battery"] as Map<*, *>
        assertEquals(50.0, battery["levelPercent"])
        assertEquals(true, battery["charging"])
        assertEquals("usb", battery["plugged"])
        assertEquals(32.1, battery["temperatureC"])
        assertNull(battery["currentMicroamps"])
        assertEquals("sensor_unavailable", (battery["reasons"] as Map<*, *>)["currentMicroamps"])
        assertNull(battery["chargeTimeRemainingMs"])
    }

    @Test fun absentSystemPermissionDoesNotWriteAndSettingsOpeningHasHonestOutcome() {
        shadowOf(context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager).setMode(AppOpsManager.OPSTR_WRITE_SETTINGS, android.os.Process.myUid(), context.packageName, AppOpsManager.MODE_ERRORED)
        assertFalse("Permission fixture must actually deny Settings.System.canWrite", Settings.System.canWrite(context))
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 90)
        val handler = MiniAppDeviceHandler(context)
        assertEquals("permission_required", handler.execute("device.screen.brightness.set", mapOf("value" to 120))["status"])
        assertEquals(90, Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS))
        assertEquals("permission_required", handler.execute("device.settings.open", mapOf("page" to "write_settings"))["status"])
        assertEquals("failed", handler.execute("device.settings.open", mapOf("page" to "intent:anything"))["status"])
    }

    @Test fun ownSystemPersistentAndProtectedPackagesCannotBeForceStopped() {
        fun app(name: String, flagsValue: Int = 0, uidValue: Int = 11000) = ApplicationInfo().apply { packageName = name; flags = flagsValue; uid = uidValue }
        assertFalse(MiniAppPackagePolicy.isEligible(app(context.packageName), context.packageName, emptySet()))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.example.system", ApplicationInfo.FLAG_SYSTEM), context.packageName, emptySet()))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.example.updated", ApplicationInfo.FLAG_UPDATED_SYSTEM_APP), context.packageName, emptySet()))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.example.persistent", ApplicationInfo.FLAG_PERSISTENT), context.packageName, emptySet()))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.example.keyboard"), context.packageName, setOf("com.example.keyboard")))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.android.settings"), context.packageName, emptySet()))
        assertFalse(MiniAppPackagePolicy.isEligible(app("com.example.lowuid", uidValue = 1000), context.packageName, emptySet()))
        assertTrue(MiniAppPackagePolicy.isEligible(app("com.example.notes"), context.packageName, emptySet()))
        for (name in listOf("com.topjohnwu.magisk", "me.weishu.kernelsu", "me.bmax.apatch", "com.rifsxd.ksunext")) {
            assertFalse("Known root managers are protected", MiniAppPackagePolicy.isEligible(app(name), context.packageName, emptySet()))
        }
        assertEquals("denied", MiniAppDeviceHandler(context).execute("device.root.stop_app", mapOf("packageName" to context.packageName))["status"])
    }

    @Test fun successfulRootExitRequiresActualAndroidReadback() {
        val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "exit 0").start() }), readbackTimeoutMs = 0)
        // A command exit cannot claim a disabled root power-save mode is enabled.
        assertEquals("failed", handler.execute("device.root.power_save.set", mapOf("enabled" to true))["status"])
        assertEquals("applied", handler.execute("device.root.power_save.set", mapOf("enabled" to false))["status"])
    }

    @Test fun nativeTimeoutNeverClaimsAppliedEvenIfTheRequestedValueAlreadyMatches() {
        val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(timeoutMs = 40, launcher = { ProcessBuilder("/bin/sh", "-c", "exec sleep 10").start() }), readbackTimeoutMs = 0)
        val result = handler.execute("device.root.power_save.set", mapOf("enabled" to false))
        assertEquals("unknown_after_timeout", result["status"])
        assertEquals(false, ((result["state"] as Map<*, *>)["battery"] as Map<*, *>)["powerSave"])
    }

    @Test fun watchingOwnsNativeObserversAndCancellationReleasesThem() {
        val handler = MiniAppDeviceHandler(context)
        val before = shadowOf(context).registeredReceivers.size
        assertEquals(0, handler.events.watcherCount)
        val first = handler.events.watch { }
        val second = handler.events.watch { }
        assertEquals(2, handler.events.watcherCount)
        assertEquals(before + 1, shadowOf(context).registeredReceivers.size)
        first.close()
        assertEquals(before + 1, shadowOf(context).registeredReceivers.size)
        second.close()
        assertEquals(0, handler.events.watcherCount)
        assertEquals(before, shadowOf(context).registeredReceivers.size)
        val again = handler.events.watch { }
        assertEquals(before + 1, shadowOf(context).registeredReceivers.size)
        again.close()
        assertEquals(before, shadowOf(context).registeredReceivers.size)
    }

    @Test fun partialObserverRegistrationStillUnregistersOnLastWatch() {
        val resolver = shadowOf(context.contentResolver)
        val before = resolver.getContentObservers(Settings.System.CONTENT_URI).size
        resolver.setRegisterContentProviderException(Settings.Global.CONTENT_URI, SecurityException("fixture denies second registration"))
        try {
            val handler = MiniAppDeviceHandler(context)
            val watch = handler.events.watch { }
            assertEquals(before + 1, resolver.getContentObservers(Settings.System.CONTENT_URI).size)
            assertTrue(resolver.getContentObservers(Settings.Global.CONTENT_URI).isEmpty())
            watch.close()
            assertEquals(before, resolver.getContentObservers(Settings.System.CONTENT_URI).size)
            assertEquals(0, handler.events.watcherCount)
        } finally {
            resolver.clearRegisterContentProviderException(Settings.Global.CONTENT_URI)
        }
    }

    @Test fun uptimeReadsElapsedRealtimeAndAdvancesWithoutUsingWallClock() {
        ShadowSystemClock.advanceBy(Duration.ofMillis(2345))
        val firstExpected = SystemClock.elapsedRealtime()
        val first = (MiniAppDeviceHandler(context).snapshot()["system"] as Map<*, *>)["uptimeMs"]
        assertEquals(firstExpected, first)
        ShadowSystemClock.advanceBy(Duration.ofMillis(1234))
        val second = (MiniAppDeviceHandler(context).snapshot()["system"] as Map<*, *>)["uptimeMs"]
        assertEquals(firstExpected + 1234, second)
        assertNotEquals(System.currentTimeMillis(), second)
    }

    @Test @Config(sdk = [35]) fun modernDndDoesNotChangeGlobalFilterOrOwnedRules() {
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        shadowOf(notifications).setNotificationPolicyAccessGranted(true)
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        val beforeRules = notifications.automaticZenRules.toMap()
        val handler = MiniAppDeviceHandler(context)
        val result = handler.execute("device.audio.dnd.set", mapOf("mode" to "none"))
        assertEquals("unsupported", result["status"])
        assertEquals(NotificationManager.INTERRUPTION_FILTER_PRIORITY, notifications.currentInterruptionFilter)
        assertEquals(beforeRules, notifications.automaticZenRules)
        val audio = handler.snapshot()["audio"] as Map<*, *>
        assertEquals(false, audio["canChangeDnd"])
        assertEquals(true, audio["canAccessDnd"])
        assertEquals("unsupported_android_version", (audio["reasons"] as Map<*, *>)["canChangeDnd"])
    }

    @Test @Config(sdk = [30, 35]) fun rootDndUsesFixedCommandAndConfirmsAllFourGlobalFiltersWithoutPolicyAccess() {
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        shadowOf(notifications).setNotificationPolicyAccessGranted(false)
        val modes = mapOf(
            "all" to NotificationManager.INTERRUPTION_FILTER_ALL,
            "priority" to NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            "alarms" to NotificationManager.INTERRUPTION_FILTER_ALARMS,
            "none" to NotificationManager.INTERRUPTION_FILTER_NONE,
        )
        for ((mode, filter) in modes) {
            notifications.setInterruptionFilter(if (mode == "all") NotificationManager.INTERRUPTION_FILTER_NONE else NotificationManager.INTERRUPTION_FILTER_ALL)
            val launched = mutableListOf<List<String>>()
            val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = { argv ->
                launched.add(argv)
                // Simulate the shell's global change in Android's state fixture.
                notifications.setInterruptionFilter(filter)
                ProcessBuilder("/bin/sh", "-c", "exit 0").start()
            }), readbackTimeoutMs = 0)
            val result = handler.execute("device.root.dnd.set", mapOf("mode" to mode))
            assertEquals("Root DND mode $mode", "applied", result["status"])
            assertEquals(listOf(listOf("su", "-c", "exec '/system/bin/cmd' 'notification' 'set_dnd' '$mode'")), launched)
            assertEquals(filter, notifications.currentInterruptionFilter)
            val audio = (result["state"] as Map<*, *>)["audio"] as Map<*, *>
            assertEquals(mode, audio["dnd"])
            assertEquals(false, audio["canAccessDnd"])
            assertEquals(false, audio["canChangeDnd"])
        }
    }

    @Test @Config(sdk = [30, 35]) fun successfulRootDndExitCannotClaimAnUnchangedOrUnreadableGlobalFilter() {
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "exit 0").start() }), readbackTimeoutMs = 0)
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        val unchanged = handler.execute("device.root.dnd.set", mapOf("mode" to "none"))
        assertEquals("failed", unchanged["status"])
        assertEquals("all", ((unchanged["state"] as Map<*, *>)["audio"] as Map<*, *>)["dnd"])
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_UNKNOWN)
        val unreadable = handler.execute("device.root.dnd.set", mapOf("mode" to "none"))
        assertEquals("unknown_after_timeout", unreadable["status"])
        assertNull(((unreadable["state"] as Map<*, *>)["audio"] as Map<*, *>)["dnd"])
    }

    @Test @Config(sdk = [35]) fun rootDndDenialAndTimeoutCannotClaimAppliedEvenForAMatchingFilter() {
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        val denied = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "printf 'Permission denied'; exit 1").start() }), readbackTimeoutMs = 0)
        val refusal = denied.execute("device.root.dnd.set", mapOf("mode" to "all"))
        assertEquals("denied", refusal["status"])
        assertEquals(false, ((refusal["state"] as Map<*, *>)["system"] as Map<*, *>)["rootAvailable"])
        val timedOut = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(timeoutMs = 40, launcher = { ProcessBuilder("/bin/sh", "-c", "exec sleep 10").start() }), readbackTimeoutMs = 0)
        val timeout = timedOut.execute("device.root.dnd.set", mapOf("mode" to "all"))
        assertEquals("unknown_after_timeout", timeout["status"])
        assertEquals("all", ((timeout["state"] as Map<*, *>)["audio"] as Map<*, *>)["dnd"])
    }

    @Test @Config(sdk = [35]) fun cancelledOrInvalidRootDndNeverLaunchesSu() {
        var launches = 0
        val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = { launches++; throw AssertionError("Invalid or cancelled root DND must not launch") }), readbackTimeoutMs = 0)
        val token = MiniAppRootCancellation().apply { cancel() }
        assertEquals("denied", handler.execute("device.root.dnd.set", mapOf("mode" to "none"), token)["status"])
        assertEquals("failed", handler.execute("device.root.dnd.set", mapOf("mode" to "none;id"))["status"])
        assertEquals("failed", handler.execute("device.root.dnd.set", mapOf("mode" to "none", "argv" to listOf("id")))["status"])
        assertEquals(0, launches)
    }

    @Test @Config(sdk = [35]) fun rootDndCancellationDuringTheCommandKeepsTheOutcomeUnknown() {
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val started = CountDownLatch(1)
        val process = AtomicReference<Process>()
        val reply = AtomicReference<Map<String, Any?>>()
        val token = MiniAppRootCancellation()
        val handler = MiniAppDeviceHandler(context, rootRunner = MiniAppRootRunner(launcher = {
            notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
            ProcessBuilder("/bin/sh", "-c", "exec sleep 10").start().also { process.set(it); started.countDown() }
        }), readbackTimeoutMs = 0)
        val worker = Thread { reply.set(handler.execute("device.root.dnd.set", mapOf("mode" to "none"), token)) }
        worker.start()
        assertTrue(started.await(2, TimeUnit.SECONDS))
        token.cancel()
        worker.join(2000)
        assertFalse(worker.isAlive)
        assertFalse(process.get().isAlive)
        assertEquals("unknown_after_timeout", reply.get()["status"])
        assertEquals("none", ((reply.get()["state"] as Map<*, *>)["audio"] as Map<*, *>)["dnd"])
    }

    @Test fun settingsOpeningRequiresCurrentForegroundFocusAndNeverReportsAChange() {
        val controller = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        val activity = controller.get()
        val handler = MiniAppDeviceHandler(context)
        handler.attachActivity(activity)
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 90)
        // An attached Activity is not enough: the host may be paused/headless.
        assertEquals("permission_required", handler.execute("device.settings.open", mapOf("page" to "write_settings"))["status"])
        handler.setForeground(activity, true)
        activity.focused = false
        assertEquals("permission_required", handler.execute("device.settings.open", mapOf("page" to "write_settings"))["status"])
        activity.focused = true
        assertEquals("opened_settings", handler.execute("device.settings.open", mapOf("page" to "write_settings"))["status"])
        assertEquals(Settings.ACTION_MANAGE_WRITE_SETTINGS, shadowOf(activity).nextStartedActivity.action)
        assertEquals(90, Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS))
        assertEquals("opened_settings", handler.execute("device.settings.open", mapOf("page" to "dnd"))["status"])
        assertEquals("android.settings.ZEN_MODE_SETTINGS", shadowOf(activity).nextStartedActivity.action)
        assertEquals("opened_settings", handler.execute("device.settings.open", mapOf("page" to "dnd_access"))["status"])
        assertEquals(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS, shadowOf(activity).nextStartedActivity.action)
        assertEquals("denied", handler.execute("device.settings.open", mapOf("page" to "app_details", "packageName" to context.packageName))["status"])
        assertNull(shadowOf(activity).nextStartedActivity)
        handler.setForeground(activity, false)
        assertEquals("permission_required", handler.execute("device.settings.open", mapOf("page" to "sound"))["status"])
        assertNull(shadowOf(activity).nextStartedActivity)
        controller.pause().stop().destroy()
    }

    @Test fun selectedAppDetailsUsesEligibleInstalledPackageAndRechecksRemoval() {
        val name = "com.example.notes"
        val info = ApplicationInfo().apply { packageName = name; uid = 12000; enabled = true; nonLocalizedLabel = "Notes" }
        val pm = shadowOf(context.packageManager)
        pm.installPackage(PackageInfo().apply { packageName = name; applicationInfo = info })
        pm.addResolveInfoForIntent(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), ResolveInfo().apply {
            activityInfo = ActivityInfo().apply { packageName = name; this.name = "$name.MainActivity"; applicationInfo = info }
        })
        val controller = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        val activity = controller.get()
        val handler = MiniAppDeviceHandler(context)
        handler.attachActivity(activity)
        handler.setForeground(activity, true)
        val apps = (handler.snapshot()["system"] as Map<*, *>)["stoppableApps"] as List<*>
        assertTrue(apps.any { (it as Map<*, *>)["packageName"] == name })
        val args = mapOf("page" to "app_details", "packageName" to name)
        assertEquals("opened_settings", handler.execute("device.settings.open", args)["status"])
        val opened = shadowOf(activity).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, opened.action)
        assertEquals("package:$name", opened.dataString)
        pm.removePackage(name)
        assertEquals("denied", handler.execute("device.settings.open", args)["status"])
        assertNull(shadowOf(activity).nextStartedActivity)
        controller.pause().stop().destroy()
    }
}

package com.psyche.kelivo

import org.junit.Assert.*
import org.junit.Test

class MiniAppDeviceCatalogTest {
    @Test fun mathematicalIntegersHaveTheSameContractAcrossChannelNumberTypes() {
        for (value in listOf(80.toByte(), 80.toShort(), 80, 80L, 80.0, 80.0f)) {
            assertNull("Whole-number $value must match integer 80", MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to value)))
            assertNull(MiniAppDeviceCatalog.validate("device.audio.volume.set", mapOf("stream" to "music", "value" to value)))
        }
        assertNull(MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to 0.0)))
        assertNull(MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to 255.0)))
        assertNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 15000.0)))
        assertNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 1800000.0f)))
        for (value in listOf<Any?>(80.5, 80.5f, 80.0001, Double.NaN, Float.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, Double.MAX_VALUE, Float.MAX_VALUE, Long.MAX_VALUE, Long.MIN_VALUE, Double.MIN_VALUE, -1.0, 256.0, true, "80", null)) {
            assertNotNull("Non-integral, non-finite, mistyped or out-of-range $value must be denied", MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to value)))
        }
        assertNotNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 14999.0)))
        assertNotNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 1800001.0)))
        assertNotNull(MiniAppDeviceCatalog.validate("device.audio.volume.set", mapOf("stream" to "music", "value" to 100.5)))
    }

    @Test fun validatesFixedNativeTypesRangesAndUnknownKeys() {
        assertNull(MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to 128)))
        assertNull(MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to 0)))
        assertNull(MiniAppDeviceCatalog.validate("device.screen.brightness.set", mapOf("value" to 128, "mode" to "automatic")))
        for (args in listOf(mapOf("value" to -1), mapOf("value" to 256), mapOf("value" to 1.5), mapOf("value" to "80"), mapOf("value" to true), mapOf("value" to 80, "key" to "low_power"))) {
            assertNotNull(args.toString(), MiniAppDeviceCatalog.validate("device.screen.brightness.set", args))
        }
        assertNotNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 14999)))
        assertNotNull(MiniAppDeviceCatalog.validate("device.screen.timeout.set", mapOf("milliseconds" to 1800001)))
        assertNotNull(MiniAppDeviceCatalog.validate("device.audio.volume.set", mapOf("stream" to "unknown", "value" to 5)))
        assertNotNull(MiniAppDeviceCatalog.validate("device.audio.dnd.set", mapOf("mode" to "silent")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.settings.open", mapOf("page" to "intent:arbitrary")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.root.wifi.set", mapOf("enabled" to "true")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.root.exec", mapOf("command" to "id")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.battery.get", mapOf("command" to "id")))
    }

    @Test fun selectedAppSettingsAndDndAccessHaveFixedArguments() {
        assertNull(MiniAppDeviceCatalog.validate("device.settings.open", mapOf("page" to "app_details", "packageName" to "com.example.notes")))
        assertNull(MiniAppDeviceCatalog.validate("device.settings.open", mapOf("page" to "dnd_access")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.settings.open", mapOf("page" to "sound", "packageName" to "com.example.notes")))
        assertNotNull(MiniAppDeviceCatalog.validate("device.settings.open", mapOf("page" to "app_details", "packageName" to "com.example;id")))
    }

    @Test fun rootDndAcceptsOnlyTheFourFixedModesWithoutShellArguments() {
        for (mode in listOf("all", "priority", "alarms", "none")) {
            assertNull(MiniAppDeviceCatalog.validate("device.root.dnd.set", mapOf("mode" to mode)))
            val command = MiniAppDeviceCatalog.rootCommand("device.root.dnd.set", mapOf("mode" to mode))!!
            assertEquals(listOf("/system/bin/cmd", "notification", "set_dnd", mode), command.argv)
            assertEquals(listOf("su", "-c", "exec '/system/bin/cmd' 'notification' 'set_dnd' '$mode'"), command.suArgv())
        }
        for (mode in listOf<Any?>(null, true, 1, "silent", "on", "off", "ALL", "none;id", "$(id)", "all\nnone", "priority --user 0", listOf("all"))) {
            val args = mapOf("mode" to mode)
            assertNotNull("Invalid mode $mode must be rejected", MiniAppDeviceCatalog.validate("device.root.dnd.set", args))
            assertNull(MiniAppDeviceCatalog.rootCommand("device.root.dnd.set", args))
        }
        for (args in listOf(emptyMap(), mapOf("enabled" to true), mapOf("mode" to "all", "command" to "id"), mapOf("mode" to "all", "argv" to listOf("id")), mapOf("mode" to "all", "shell" to "id"), mapOf("mode" to "all", "extra" to null))) {
            assertNotNull(args.toString(), MiniAppDeviceCatalog.validate("device.root.dnd.set", args))
            assertNull(MiniAppDeviceCatalog.rootCommand("device.root.dnd.set", args))
        }
    }

    @Test fun rootCommandsComeOnlyFromAllowlistedOperationAndValidatedArguments() {
        val expected = mapOf(
            "power_save" to listOf("/system/bin/cmd", "power", "set-mode", "1"),
            "wifi" to listOf("/system/bin/svc", "wifi", "enable"),
            "bluetooth" to listOf("/system/bin/cmd", "bluetooth_manager", "enable"),
            "data" to listOf("/system/bin/svc", "data", "enable"),
            "airplane" to listOf("/system/bin/cmd", "connectivity", "airplane-mode", "enable"),
        )
        for ((operation, argv) in expected) {
            val command = MiniAppDeviceCatalog.rootCommand("device.root.$operation.set", mapOf("enabled" to true))!!
            assertEquals(argv, command.argv)
            val suArgv = command.suArgv()
            assertEquals(listOf("su", "-c"), suArgv.take(2))
            assertTrue(suArgv[2].startsWith("exec "))
            assertFalse(suArgv[2].contains(';'))
            assertFalse(suArgv[2].contains('$'))
        }
        assertEquals(listOf("/system/bin/am", "force-stop", "--user", "0", "com.example.notes"), MiniAppDeviceCatalog.rootCommand("device.root.stop_app", mapOf("packageName" to "com.example.notes"))!!.argv)
        for (name in listOf("com.example.notes;id", "com.example.$(id)", "--user", "com.example/foo", "com.example\nnotes")) {
            assertNotNull(MiniAppDeviceCatalog.validate("device.root.stop_app", mapOf("packageName" to name)))
            assertNull(MiniAppDeviceCatalog.rootCommand("device.root.stop_app", mapOf("packageName" to name)))
        }
        assertNull(MiniAppDeviceCatalog.rootCommand("device.screen.brightness.set", mapOf("value" to 80)))
        assertNull(MiniAppDeviceCatalog.rootCommand("device.root.exec", mapOf("command" to "id")))
    }
}

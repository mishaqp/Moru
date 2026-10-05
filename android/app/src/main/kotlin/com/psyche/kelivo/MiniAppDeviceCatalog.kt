package com.psyche.kelivo

/** Native limits are authoritative even when a manifest has a broader schema. */
object MiniAppDeviceCatalog {
    val groups = setOf("battery", "screen", "audio", "connectivity", "flashlight", "system")
    val streams = setOf("music", "ring", "notification", "alarm", "system", "voice_call")
    val settingsPages = setOf("battery", "power_save", "display", "sound", "wifi", "bluetooth", "mobile_data", "airplane", "write_settings", "dnd", "dnd_access", "app_details", "permissions")
    private val rootOperations = setOf("power_save", "wifi", "bluetooth", "data", "airplane")
    private val packagePattern = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")

    fun validate(handler: String, args: Map<String, Any?>): String? {
        fun only(vararg keys: String): Boolean = args.keys.all { it in keys }
        fun integer(key: String, min: Int, max: Int): Boolean {
            val value = args[key]
            return when (value) {
                is Byte, is Short, is Int, is Long -> (value as Number).toLong() in min.toLong()..max.toLong()
                is Float, is Double -> {
                    // JSON Schema integers may reach the channel as 80.0.
                    // Check the value before any conversion can truncate it.
                    val number = (value as Number).toDouble()
                    number.isFinite() && number in min.toDouble()..max.toDouble() && number % 1.0 == 0.0
                }
                else -> false
            }
        }
        val valid = when {
            handler in groups.map { "device.$it.get" } -> args.isEmpty()
            handler == "device.screen.brightness.set" -> only("value", "mode") && integer("value", 0, 255) && (!args.containsKey("mode") || args["mode"] in setOf("manual", "automatic"))
            handler == "device.screen.timeout.set" -> only("milliseconds") && integer("milliseconds", 15000, 1800000)
            handler == "device.audio.volume.set" -> only("stream", "value") && args["stream"] in streams && integer("value", 0, 100)
            handler == "device.audio.dnd.set" -> only("mode") && args["mode"] in setOf("all", "priority", "none", "alarms")
            handler == "device.settings.open" -> only("page", "packageName") && args["page"] in settingsPages && (!args.containsKey("packageName") || (args["page"] == "app_details" && validPackageName(args["packageName"])))
            handler == "device.flashlight.set" || handler in rootOperations.map { "device.root.$it.set" } -> only("enabled") && args["enabled"] is Boolean
            handler == "device.root.stop_app" -> only("packageName") && validPackageName(args["packageName"])
            else -> return "Unknown device handler."
        }
        return if (valid) null else "Arguments do not match the fixed Android device contract."
    }

    fun validPackageName(value: Any?): Boolean = value is String && value.length in 3..200 && packagePattern.matches(value)

    fun rootCommand(handler: String, args: Map<String, Any?>, userId: Int = 0): MiniAppRootCommand? {
        if (validate(handler, args) != null || userId !in 0..9999) return null
        val enabled = args["enabled"] == true
        val verb = if (enabled) "enable" else "disable"
        val argv = when (handler) {
            "device.root.power_save.set" -> listOf("/system/bin/cmd", "power", "set-mode", if (enabled) "1" else "0")
            "device.root.wifi.set" -> listOf("/system/bin/svc", "wifi", verb)
            "device.root.bluetooth.set" -> listOf("/system/bin/cmd", "bluetooth_manager", verb)
            "device.root.data.set" -> listOf("/system/bin/svc", "data", verb)
            "device.root.airplane.set" -> listOf("/system/bin/cmd", "connectivity", "airplane-mode", verb)
            "device.root.stop_app" -> listOf("/system/bin/am", "force-stop", "--user", userId.toString(), args["packageName"] as String)
            else -> return null
        }
        return MiniAppRootCommand(argv)
    }
}

/** Only the catalog constructs commands; no bridge accepts shell source/argv. */
class MiniAppRootCommand internal constructor(val argv: List<String>) {
    fun suArgv(): List<String> = listOf("su", "-c", "exec " + argv.joinToString(" ") { "'" + it.replace("'", "'\\''") + "'" })
}

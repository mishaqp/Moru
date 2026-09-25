package com.psyche.kelivo

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.util.concurrent.Executors

/**
 * Native backend for the AI assistant's device-local tools:
 * screen time (usage stats), calendar query/creation and one-shot location.
 *
 * All methods receive the tool arguments as a JSON string and return a JSON
 * string payload. Errors that the LLM should see (missing permission, bad
 * arguments) are returned as JSON payloads with an "error" field instead of
 * platform errors, so the model can relay them to the user.
 */
class DeviceLocalToolsHandler(private val context: Context) {
    private var attachedActivity: Activity? = context as? Activity
    private val activity: Activity get() = requireNotNull(attachedActivity) { "foreground_activity_required" }

    fun attachActivity(activity: Activity) { attachedActivity = activity }
    fun detachActivity(activity: Activity) {
        if (attachedActivity !== activity) return
        attachedActivity = null
        pendingCalendarPermissionCallback?.invoke(false)
        pendingCalendarPermissionCallback = null
        pendingLocationPermissionCallback?.invoke(false, false)
        pendingLocationPermissionCallback = null
    }

    companion object {
        const val CHANNEL_NAME = "app.device_tools"
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4201
        const val LOCATION_PERMISSION_REQUEST_CODE = 4202
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingCalendarPermissionCallback: ((Boolean) -> Unit)? = null
    private var pendingLocationPermissionCallback: ((Boolean, Boolean) -> Unit)? = null
    private val locationHandler = LocationToolHandler(context)

    fun configure(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            val argsJson = call.arguments as? String ?: "{}"
            when (call.method) {
                "phoneControlStatus" -> result.success(PhoneControlService.status(context))
                "phoneControl" -> PhoneControlService.execute(argsJson) { result.success(it) }
                "openAccessibilitySettings" -> {
                    try {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", e.message, null)
                    }
                }
                "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }
                "hasCalendarPermission" -> result.success(hasCalendarPermission())
                "requestCalendarPermission" -> requestCalendarPermission(result)
                "hasLocationPermission" -> result.success(locationHandler.hasPermission())
                "requestLocationPermission" -> requestLocationPermission { granted, permanentlyDenied ->
                    if (permanentlyDenied) {
                        result.error(
                            "LOCATION_PERMISSION_PERMANENTLY_DENIED",
                            "Allow location permission in system Settings.",
                            null,
                        )
                    } else {
                        result.success(granted)
                    }
                }
                "openAppSettings" -> {
                    try {
                        activity.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", context.packageName, null),
                            ),
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", e.message, null)
                    }
                }
                "getCurrentLocation" -> {
                    if (locationHandler.hasPermission()) {
                        locationHandler.getCurrentLocation(result)
                    } else {
                        requestLocationPermission { granted, _ ->
                            if (granted) {
                                locationHandler.getCurrentLocation(result)
                            } else {
                                result.success(
                                    errorPayload(
                                        "NO_PERMISSION",
                                        "Location permission is not granted. Please allow location " +
                                            "while using the app in system Settings and try again.",
                                    ),
                                )
                            }
                        }
                    }
                }
                "getScreenTime" -> handleScreenTime(argsJson, result)
                "queryCalendar" -> withCalendarPermission(
                    arrayOf(Manifest.permission.READ_CALENDAR),
                    result,
                ) { runAsync(result) { queryCalendar(JSONObject(argsJson)) } }
                "createCalendarEvent" -> withCalendarPermission(
                    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                    result,
                ) { runAsync(result) { createCalendarEvent(JSONObject(argsJson)) } }
                "updateCalendarEvent" -> withCalendarPermission(
                    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                    result,
                ) { runAsync(result) { updateCalendarEvent(JSONObject(argsJson)) } }
                "deleteCalendarEvent" -> withCalendarPermission(
                    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                    result,
                ) { runAsync(result) { deleteCalendarEvent(JSONObject(argsJson)) } }
                else -> result.notImplemented()
            }
        }
    }

    /** Forwarded from the Activity. Returns true when the request was ours. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val callback = pendingLocationPermissionCallback
            pendingLocationPermissionCallback = null
            // Approximate (coarse) permission alone is sufficient.
            val granted = locationHandler.hasPermission()
            // Check after a completed request: false before the first request
            // does not mean permanent denial. Empty results indicate cancellation.
            val permanentlyDenied = attachedActivity != null && !granted && grantResults.isNotEmpty() &&
                !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION) &&
                !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION)
            callback?.invoke(granted, permanentlyDenied)
            return true
        }
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) return false
        val callback = pendingCalendarPermissionCallback ?: return true
        pendingCalendarPermissionCallback = null
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        callback(granted)
        return true
    }

    fun dispose() {
        locationHandler.dispose()
        pendingLocationPermissionCallback?.invoke(false, false)
        pendingLocationPermissionCallback = null
    }

    // ---------------------------------------------------------------------
    // Permission helpers
    // ---------------------------------------------------------------------

    private fun requestLocationPermission(completion: (Boolean, Boolean) -> Unit) {
        if (locationHandler.hasPermission()) {
            completion(true, false)
            return
        }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) {
            completion(false, false)
            return
        }
        if (attachedActivity == null) {
            completion(false, false)
            return
        }
        pendingLocationPermissionCallback = completion
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun calendarPermissions(): Array<String> = arrayOf(
        Manifest.permission.READ_CALENDAR,
        Manifest.permission.WRITE_CALENDAR,
    )

    private fun hasCalendarPermission(): Boolean {
        return calendarPermissions().all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** Used by the assistant settings toggle — returns a boolean grant result. */
    private fun requestCalendarPermission(result: MethodChannel.Result) {
        val missing = calendarPermissions().filter {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) {
            result.success(false)
            return
        }
        if (attachedActivity == null) {
            result.success(false)
            return
        }
        pendingCalendarPermissionCallback = { granted -> result.success(granted) }
        ActivityCompat.requestPermissions(
            activity,
            missing.toTypedArray(),
            CALENDAR_PERMISSION_REQUEST_CODE,
        )
    }

    private fun withCalendarPermission(
        permissions: Array<String>,
        result: MethodChannel.Result,
        action: () -> Unit,
    ) {
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            action()
            return
        }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) {
            result.success(
                errorPayload(
                    "PERMISSION_REQUEST_IN_PROGRESS",
                    "Another permission request is already in progress. Please try again.",
                ),
            )
            return
        }
        if (attachedActivity == null) {
            result.success(errorPayload("FOREGROUND_REQUIRED", "Open Kelivo to grant calendar permission."))
            return
        }
        pendingCalendarPermissionCallback = { granted ->
            if (granted) {
                action()
            } else {
                result.success(
                    errorPayload(
                        "NO_PERMISSION",
                        "Calendar permission is not granted. Please ask the user to grant the " +
                            "calendar permission to this app and try again.",
                    ),
                )
            }
        }
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), CALENDAR_PERMISSION_REQUEST_CODE)
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_USAGE_ACCESS_SETTINGS,
                    Uri.fromParts("package", context.packageName, null),
                ),
            )
        } catch (_: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
            } catch (_: Exception) {
                // Settings page unavailable; the error payload still informs the model.
            }
        }
    }

    // ---------------------------------------------------------------------
    // Async plumbing
    // ---------------------------------------------------------------------

    private fun runAsync(result: MethodChannel.Result, block: () -> String) {
        executor.execute {
            val payload = try {
                block()
            } catch (e: Exception) {
                errorPayload("EXECUTION_ERROR", e.message ?: "Tool execution failed.")
            }
            mainHandler.post { result.success(payload) }
        }
    }

    private fun errorPayload(error: String, message: String): String {
        return JSONObject().put("error", error).put("message", message).toString()
    }

    // ---------------------------------------------------------------------
    // Screen time
    // ---------------------------------------------------------------------

    private fun handleScreenTime(argsJson: String, result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            openUsageAccessSettings()
            result.success(
                errorPayload(
                    "NO_PERMISSION",
                    "Usage access permission is not granted. The system settings page has been " +
                        "opened; please ask the user to enable 'Usage access' for this app and try again.",
                ),
            )
            return
        }
        runAsync(result) { computeScreenTime(JSONObject(argsJson)) }
    }

    private fun computeScreenTime(params: JSONObject): String {
        val top = params.optString("top").toIntOrNull()?.coerceIn(1, 50)
            ?: params.optInt("top", 10).coerceIn(1, 50)

        val now = ZonedDateTime.now()
        val zone = now.zone
        val beginRaw = params.optString("begin").takeIf { it.isNotBlank() }
        val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val rangePreset = params.optString("range").takeIf { it.isNotBlank() } ?: "today"

        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            endTime = endRaw?.let { parseTime(it, zone) } ?: now
            startTime = if (beginRaw != null) {
                parseTime(beginRaw, zone)
            } else when (rangePreset) {
                "week" -> now.minusDays(7)
                else -> now.toLocalDate().atStartOfDay(zone)
            }
        } catch (e: Exception) {
            return errorPayload("INVALID_TIME", e.message ?: "Invalid time format for begin/end.")
        }
        if (!startTime.isBefore(endTime)) {
            return errorPayload("INVALID_RANGE", "begin must be earlier than end.")
        }

        val isCustom = beginRaw != null || endRaw != null
        val startMs = startTime.toInstant().toEpochMilli()
        val endMs = endTime.toInstant().toEpochMilli()

        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = context.packageManager

        val launcherPackages = resolveLauncherPackages(pm)
        val foregroundMs = computeForegroundTime(usageStatsManager, startMs, endMs, launcherPackages)

        val sorted = foregroundMs.entries
            .filter { it.value > 0 }
            .sortedByDescending { it.value }
        val totalMs = sorted.sumOf { it.value }

        val apps = JSONArray()
        sorted.take(top).forEach { entry ->
            apps.put(
                JSONObject()
                    .put("package", entry.key)
                    .put("app_name", resolveAppName(pm, entry.key))
                    .put("total_ms", entry.value)
                    .put("total_minutes", entry.value / 60000),
            )
        }

        return JSONObject()
            .put("range", if (isCustom) "custom" else rangePreset)
            .put("start", startTime.withNano(0).toString())
            .put("end", endTime.withNano(0).toString())
            .put("total_ms", totalMs)
            .put("total_minutes", totalMs / 60000)
            .put("apps", apps)
            .toString()
    }

    // 计算屏幕时间时向前回看的窗口(12h), 用于还原区间开始时刻已在前台的 App.
    private val lookbackMs = 12L * 60 * 60 * 1000

    /**
     * 用"全局单一前台"模型计算 [startMs, endMs) 区间内每个 App 的前台时长(毫秒).
     * 任意时刻只有一个 App 计时: 新 App 进前台先结算上一个, 息屏停止计时;
     * 区间起点向前回看以补回"开始前已在前台"的使用段, 结算时裁剪回区间内.
     */
    @Suppress("DEPRECATION")
    private fun computeForegroundTime(
        usageStatsManager: UsageStatsManager,
        startMs: Long,
        endMs: Long,
        excludedPackages: Set<String>,
    ): Map<String, Long> {
        val foregroundMs = HashMap<String, Long>()
        val events = usageStatsManager.queryEvents(startMs - lookbackMs, endMs)
        val event = UsageEvents.Event()

        var currentPkg: String? = null
        var currentStart = 0L

        fun settle(until: Long) {
            val pkg = currentPkg
            currentPkg = null
            if (pkg == null || pkg in excludedPackages) return
            val from = maxOf(currentStart, startMs)
            val duration = until - from
            if (duration > 0) {
                foregroundMs[pkg] = (foregroundMs[pkg] ?: 0L) + duration
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (event.packageName != currentPkg) {
                        settle(event.timeStamp)
                        currentPkg = event.packageName
                        currentStart = event.timeStamp
                    }
                }

                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (event.packageName == currentPkg) {
                        settle(event.timeStamp)
                    }
                }

                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    settle(event.timeStamp)
                }
            }
        }
        settle(endMs)
        return foregroundMs
    }

    private fun resolveLauncherPackages(pm: PackageManager): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return runCatching {
            pm.queryIntentActivities(intent, 0)
                .mapNotNull { it.activityInfo?.packageName }
                .toSet()
        }.getOrDefault(emptySet())
    }

    private fun resolveAppName(pm: PackageManager, packageName: String): String {
        return runCatching {
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        }.getOrDefault(packageName)
    }

    // ---------------------------------------------------------------------
    // Calendar query
    // ---------------------------------------------------------------------

    private fun queryCalendar(params: JSONObject): String {
        val limit = params.optString("limit").toIntOrNull()?.coerceIn(1, 100)
            ?: params.optInt("limit", 20).coerceIn(1, 100)
        val query = params.optString("query").takeIf { it.isNotBlank() }
        val calendarFilter = optLong(params, "calendar_id")

        val now = ZonedDateTime.now()
        val zone = now.zone
        val beginRaw = params.optString("begin").takeIf { it.isNotBlank() }
        val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val rangePreset = params.optString("range").takeIf { it.isNotBlank() } ?: "today"

        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            startTime = if (beginRaw != null) {
                parseTime(beginRaw, zone)
            } else when (rangePreset) {
                "week" -> now.toLocalDate().atStartOfDay(zone).minusDays(now.dayOfWeek.value.toLong() - 1)
                "month" -> now.toLocalDate().withDayOfMonth(1).atStartOfDay(zone)
                else -> now.toLocalDate().atStartOfDay(zone)
            }
            endTime = if (endRaw != null) {
                parseTime(endRaw, zone)
            } else if (beginRaw != null) {
                // Custom interval: 'range' is ignored per the tool contract, and
                // the end defaults to now (matches iOS).
                now
            } else when (rangePreset) {
                "week" -> startTime.plusDays(7)
                "month" -> startTime.plusMonths(1)
                else -> now.toLocalDate().plusDays(1).atStartOfDay(zone)
            }
        } catch (e: Exception) {
            return errorPayload("INVALID_TIME", e.message ?: "Invalid time format for begin/end.")
        }
        if (!startTime.isBefore(endTime)) {
            return errorPayload("INVALID_RANGE", "begin must be earlier than end.")
        }

        val startMs = startTime.toInstant().toEpochMilli()
        val endMs = endTime.toInstant().toEpochMilli()

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.CALENDAR_ID,
        )
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        if (query != null) {
            // Escape LIKE wildcards so the keyword is matched literally as a
            // substring (e.g. searching "100%" must not act as a wildcard).
            clauses.add("${CalendarContract.Instances.TITLE} LIKE ? ESCAPE '\\'")
            val escaped = query
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_")
            args.add("%$escaped%")
        }
        if (calendarFilter != null) {
            clauses.add("${CalendarContract.Instances.CALENDAR_ID} = ?")
            args.add(calendarFilter.toString())
        }
        val selection = clauses.takeIf { it.isNotEmpty() }?.joinToString(" AND ")
        val selectionArgs = args.takeIf { it.isNotEmpty() }?.toTypedArray()

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(startMs.toString())
            .appendPath(endMs.toString())
            .build()

        val events = JSONArray()
        context.contentResolver.query(
            uri,
            projection,
            selection,
            selectionArgs,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { cursor ->
            var count = 0
            while (cursor.moveToNext() && count < limit) {
                val dtStart = cursor.getLong(4)
                val dtEnd = cursor.getLong(5)
                val allDay = cursor.getInt(6) == 1
                val obj = JSONObject()
                    .put("id", cursor.getLong(0))
                    .put("title", cursor.getString(1) ?: "")
                    .put("description", cursor.getString(2) ?: "")
                    .put("location", cursor.getString(3) ?: "")
                if (allDay) {
                    obj.put("start", Instant.ofEpochMilli(dtStart).atZone(ZoneOffset.UTC).toLocalDate().toString())
                    obj.put(
                        "end",
                        if (dtEnd > 0) Instant.ofEpochMilli(dtEnd).atZone(ZoneOffset.UTC).toLocalDate().toString() else "",
                    )
                } else {
                    obj.put("start", Instant.ofEpochMilli(dtStart).atZone(zone).withNano(0).toString())
                    obj.put(
                        "end",
                        if (dtEnd > 0) Instant.ofEpochMilli(dtEnd).atZone(zone).withNano(0).toString() else "",
                    )
                }
                obj.put("all_day", allDay)
                obj.put("calendar", cursor.getString(7) ?: "")
                obj.put("calendar_id", cursor.getLong(8))
                events.put(obj)
                count++
            }
        }

        val payload = JSONObject()
            .put("range_start", startTime.withNano(0).toString())
            .put("range_end", endTime.withNano(0).toString())
            .put("count", events.length())
            .put("events", events)
        if (params.optBoolean("include_calendars", false)) {
            payload.put("calendars", listCalendars())
        }
        return payload.toString()
    }

    private fun listCalendars(): JSONArray {
        val calendars = JSONArray()
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(
                CalendarContract.Calendars._ID,
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                CalendarContract.Calendars.ACCOUNT_NAME,
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                CalendarContract.Calendars.IS_PRIMARY,
                CalendarContract.Calendars.VISIBLE,
            ),
            null,
            null,
            "${CalendarContract.Calendars.IS_PRIMARY} DESC, ${CalendarContract.Calendars._ID} ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                calendars.put(
                    JSONObject()
                        .put("id", cursor.getLong(0))
                        .put("name", cursor.getString(1) ?: "")
                        .put("account", cursor.getString(2) ?: "")
                        .put("writable", cursor.getInt(3) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)
                        .put("primary", cursor.getInt(4) == 1)
                        .put("visible", cursor.getInt(5) == 1),
                )
            }
        }
        return calendars
    }

    /** A writable calendar with this id, or null. */
    private fun writableCalendarExists(calendarId: Long): Boolean {
        context.contentResolver.query(
            ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, calendarId),
            arrayOf(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            null,
            null,
            null,
        )?.use { cursor ->
            return cursor.moveToFirst() &&
                cursor.getInt(0) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
        }
        return false
    }

    /** Reads an integer id that the model may send as a number or a string. */
    private fun optLong(params: JSONObject, key: String): Long? {
        val raw = params.opt(key) ?: return null
        return when (raw) {
            is Number -> raw.toLong()
            is String -> raw.trim().toLongOrNull()
            else -> null
        }
    }

    // ---------------------------------------------------------------------
    // Calendar create
    // ---------------------------------------------------------------------

    private fun createCalendarEvent(params: JSONObject): String {
        val title = params.optString("title").takeIf { it.isNotBlank() }
        val startRaw = params.optString("start").takeIf { it.isNotBlank() }
        val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val allDay = params.optBoolean("all_day", false)

        if (title == null || startRaw == null) {
            return errorPayload("MISSING_REQUIRED", "Both 'title' and 'start' are required.")
        }

        val zone = ZoneId.systemDefault()
        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            startTime = parseTime(startRaw, zone)
            endTime = if (endRaw != null) {
                parseTime(endRaw, zone)
            } else if (allDay) {
                startTime.toLocalDate().plusDays(1).atStartOfDay(zone)
            } else {
                startTime.plusHours(1)
            }
        } catch (e: Exception) {
            return errorPayload("INVALID_TIME", e.message ?: "Invalid time format.")
        }
        val times = eventTimes(startTime, endTime, allDay, zone)
        if (times is EventTimes.Invalid) return errorPayload("INVALID_RANGE", times.message)
        times as EventTimes.Valid

        val description = params.optString("description")
        val location = params.optString("location")
        val reminderMinutes = parseReminderMinutes(params.opt("reminders"))

        val requestedCalendar = optLong(params, "calendar_id")
        val calendarId = if (requestedCalendar != null) {
            if (!writableCalendarExists(requestedCalendar)) {
                return errorPayload(
                    "INVALID_CALENDAR",
                    "Calendar $requestedCalendar does not exist or is read-only. " +
                        "Call calendar_query with include_calendars=true to see writable calendars.",
                )
            }
            requestedCalendar
        } else {
            getDefaultCalendarId()
                ?: return errorPayload(
                    "NO_CALENDAR",
                    "No calendar account found on this device. Please add a calendar account first.",
                )
        }

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.EVENT_LOCATION, location)
            put(CalendarContract.Events.DTSTART, times.startMillis)
            put(CalendarContract.Events.DTEND, times.endMillis)
            put(CalendarContract.Events.EVENT_TIMEZONE, times.timeZone)
            if (allDay) {
                put(CalendarContract.Events.ALL_DAY, 1)
            }
        }

        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: return errorPayload("INSERT_FAILED", "Failed to insert calendar event.")

        val eventId = ContentUris.parseId(uri)
        val savedReminders = insertReminders(eventId, reminderMinutes)
        if (savedReminders.isNotEmpty()) {
            // 只有提醒真的写进去了才置 HAS_ALARM, 否则事件行会谎称有闹钟.
            setHasAlarm(eventId, true)
        }

        val payload = JSONObject()
            .put("success", true)
            .put("event_id", eventId)
            .put("calendar_id", calendarId)
            .put("title", title)
            .put("start", startTime.withNano(0).toString())
            .put("end", endTime.withNano(0).toString())
            .put("all_day", allDay)
            .put("location", location)
            .put("reminders", JSONArray(savedReminders))
        putReminderWarning(payload, reminderMinutes, savedReminders)
        return payload.toString()
    }

    // ---------------------------------------------------------------------
    // Calendar update / delete
    // ---------------------------------------------------------------------

    private class StoredEvent(
        val title: String,
        val start: ZonedDateTime,
        val end: ZonedDateTime,
        val allDay: Boolean,
        val recurring: Boolean,
        val writable: Boolean,
    )

    private fun readEvent(eventId: Long, zone: ZoneId): StoredEvent? {
        context.contentResolver.query(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
            arrayOf(
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.RRULE,
                CalendarContract.Events.CALENDAR_ACCESS_LEVEL,
                CalendarContract.Events.DELETED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst() || cursor.getInt(6) == 1) return null
            val allDay = cursor.getInt(3) == 1
            fun time(millis: Long): ZonedDateTime = if (allDay) {
                // All-day rows are stored as UTC midnights.
                Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(zone)
            } else {
                Instant.ofEpochMilli(millis).atZone(zone)
            }
            val start = time(cursor.getLong(1))
            val end = if (cursor.isNull(2)) {
                if (allDay) start.plusDays(1) else start.plusHours(1)
            } else {
                time(cursor.getLong(2))
            }
            return StoredEvent(
                title = cursor.getString(0) ?: "",
                start = start,
                end = end,
                allDay = allDay,
                recurring = !cursor.getString(4).isNullOrBlank(),
                writable = cursor.getInt(5) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR,
            )
        }
        return null
    }

    private fun updateCalendarEvent(params: JSONObject): String {
        val eventId = optLong(params, "event_id")
            ?: return errorPayload("MISSING_REQUIRED", "'event_id' is required.")
        val zone = ZoneId.systemDefault()
        val event = readEvent(eventId, zone)
            ?: return errorPayload("NOT_FOUND", "Event $eventId was not found.")
        if (!event.writable) {
            return errorPayload("READ_ONLY", "Event $eventId is in a read-only calendar.")
        }

        val startRaw = params.optString("start").takeIf { it.isNotBlank() }
        val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val allDay = if (params.has("all_day")) params.optBoolean("all_day", event.allDay) else event.allDay
        val timeChanged = startRaw != null || endRaw != null || allDay != event.allDay
        if (timeChanged && event.recurring) {
            return errorPayload(
                "RECURRING_EVENT",
                "Event $eventId repeats. Only its title, description, location and reminders " +
                    "can be changed here; ask the user to move a repeating event in their calendar app.",
            )
        }

        val values = ContentValues()
        params.optString("title").takeIf { params.has("title") && it.isNotBlank() }?.let {
            values.put(CalendarContract.Events.TITLE, it)
        }
        if (params.has("description")) {
            values.put(CalendarContract.Events.DESCRIPTION, params.optString("description"))
        }
        if (params.has("location")) {
            values.put(CalendarContract.Events.EVENT_LOCATION, params.optString("location"))
        }

        var startTime = event.start
        var endTime = event.end
        if (timeChanged) {
            try {
                startTime = startRaw?.let { parseTime(it, zone) } ?: event.start
                endTime = when {
                    endRaw != null -> parseTime(endRaw, zone)
                    // Moving the start keeps the event's length.
                    startRaw != null -> startTime.plus(Duration.between(event.start, event.end))
                    else -> event.end
                }
                if (allDay && !event.allDay && endRaw == null) {
                    endTime = startTime.toLocalDate().plusDays(1).atStartOfDay(zone)
                }
            } catch (e: Exception) {
                return errorPayload("INVALID_TIME", e.message ?: "Invalid time format.")
            }
            val times = eventTimes(startTime, endTime, allDay, zone)
            if (times is EventTimes.Invalid) return errorPayload("INVALID_RANGE", times.message)
            times as EventTimes.Valid
            values.put(CalendarContract.Events.DTSTART, times.startMillis)
            values.put(CalendarContract.Events.DTEND, times.endMillis)
            values.put(CalendarContract.Events.EVENT_TIMEZONE, times.timeZone)
            values.put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
        }

        val replaceReminders = params.has("reminders")
        if (values.size() == 0 && !replaceReminders) {
            return errorPayload("NOTHING_TO_UPDATE", "Pass at least one field to change.")
        }
        val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
        if (values.size() > 0 && context.contentResolver.update(eventUri, values, null, null) == 0) {
            return errorPayload("UPDATE_FAILED", "The calendar did not accept the change.")
        }

        val payload = JSONObject()
            .put("success", true)
            .put("event_id", eventId)
            .put("title", values.getAsString(CalendarContract.Events.TITLE) ?: event.title)
            .put("start", startTime.withNano(0).toString())
            .put("end", endTime.withNano(0).toString())
            .put("all_day", allDay)
        if (replaceReminders) {
            val requested = parseReminderMinutes(params.opt("reminders"))
            context.contentResolver.delete(
                CalendarContract.Reminders.CONTENT_URI,
                "${CalendarContract.Reminders.EVENT_ID} = ?",
                arrayOf(eventId.toString()),
            )
            val saved = insertReminders(eventId, requested)
            setHasAlarm(eventId, saved.isNotEmpty())
            payload.put("reminders", JSONArray(saved))
            putReminderWarning(payload, requested, saved)
        }
        return payload.toString()
    }

    private fun deleteCalendarEvent(params: JSONObject): String {
        val eventId = optLong(params, "event_id")
            ?: return errorPayload("MISSING_REQUIRED", "'event_id' is required.")
        val event = readEvent(eventId, ZoneId.systemDefault())
            ?: return errorPayload("NOT_FOUND", "Event $eventId was not found.")
        if (!event.writable) {
            return errorPayload("READ_ONLY", "Event $eventId is in a read-only calendar.")
        }
        val deleted = context.contentResolver.delete(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
            null,
            null,
        )
        if (deleted == 0) {
            return errorPayload("DELETE_FAILED", "The calendar did not delete event $eventId.")
        }
        return JSONObject()
            .put("success", true)
            .put("event_id", eventId)
            .put("title", event.title)
            .put("was_recurring", event.recurring)
            .toString()
    }

    private sealed class EventTimes {
        class Valid(val startMillis: Long, val endMillis: Long, val timeZone: String) : EventTimes()
        class Invalid(val message: String) : EventTimes()
    }

    /** Timed events keep the device zone; all-day events are UTC midnights. */
    private fun eventTimes(
        startTime: ZonedDateTime,
        endTime: ZonedDateTime,
        allDay: Boolean,
        zone: ZoneId,
    ): EventTimes {
        if (!startTime.isBefore(endTime)) {
            return EventTimes.Invalid("end must be later than start.")
        }
        if (!allDay) {
            return EventTimes.Valid(
                startTime.toInstant().toEpochMilli(),
                endTime.toInstant().toEpochMilli(),
                zone.id,
            )
        }
        val startDate = startTime.toLocalDate()
        val endDate = endTime.toLocalDate()
        if (!startDate.isBefore(endDate)) {
            return EventTimes.Invalid("all-day event end date must be later than start date.")
        }
        return EventTimes.Valid(
            startDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            endDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            "UTC",
        )
    }

    private fun setHasAlarm(eventId: Long, hasAlarm: Boolean) {
        runCatching {
            context.contentResolver.update(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
                ContentValues().apply { put(CalendarContract.Events.HAS_ALARM, if (hasAlarm) 1 else 0) },
                null,
                null,
            )
        }
    }

    private fun putReminderWarning(payload: JSONObject, requested: List<Int>, saved: List<Int>) {
        if (saved.size >= requested.size) return
        // 事件已经保存了, 但部分/全部提醒被日历账户拒绝; 必须让模型看见,
        // 否则它会告诉用户提醒已设置.
        payload
            .put("reminders_requested", JSONArray(requested))
            .put(
                "warning",
                "The event was saved, but the calendar account rejected some reminders. " +
                    "Tell the user which reminders were actually saved.",
            )
    }

    /**
     * 提醒偏移(事件开始前多少分钟). 兼容数组、单个数字/字符串; 负值按绝对值处理,
     * 去重后最多保留 5 条.
     */
    private fun parseReminderMinutes(raw: Any?): List<Int> {
        if (raw == null || raw == JSONObject.NULL) return emptyList()
        val items: List<Any?> = when (raw) {
            is JSONArray -> (0 until raw.length()).map { raw.opt(it) }
            else -> listOf(raw)
        }
        val minutes = LinkedHashSet<Int>()
        for (item in items) {
            val value = when (item) {
                is Number -> item.toDouble()
                is String -> item.trim().toDoubleOrNull()
                else -> null
            } ?: continue
            if (value.isNaN() || value.isInfinite()) continue
            // 用 Double 中转: Math.abs(Int.MIN_VALUE) 仍是负数, 会被当成"事件开始之后"提醒.
            minutes.add(Math.abs(value).coerceAtMost(40320.0).toInt()) // 上限 4 周
            if (minutes.size == 5) break
        }
        return minutes.toList()
    }

    /** 写入提醒, 返回实际成功写入的偏移分钟数. */
    private fun insertReminders(eventId: Long, minutes: List<Int>): List<Int> {
        if (minutes.isEmpty()) return emptyList()
        val saved = mutableListOf<Int>()
        for (minute in minutes) {
            val values = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, minute)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            val inserted = runCatching {
                context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, values)
            }.getOrNull()
            if (inserted != null) saved.add(minute)
        }
        return saved
    }

    private fun getDefaultCalendarId(): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val writableSelection =
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ? AND ${CalendarContract.Calendars.SYNC_EVENTS} = 1"
        val writableArgs = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            "$writableSelection AND ${CalendarContract.Calendars.IS_PRIMARY} = 1",
            writableArgs,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            writableSelection,
            writableArgs,
            "${CalendarContract.Calendars.VISIBLE} DESC",
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        return null
    }

    // ---------------------------------------------------------------------
    // Time parsing
    // ---------------------------------------------------------------------

    /**
     * 依次尝试: epoch 毫秒 -> 带偏移日期时间 -> Instant -> 本地日期时间 -> 本地日期(当天 0 点).
     */
    private fun parseTime(raw: String, zone: ZoneId): ZonedDateTime {
        val text = raw.trim()
        text.toLongOrNull()?.let { return Instant.ofEpochMilli(it).atZone(zone) }
        runCatching { return OffsetDateTime.parse(text).atZoneSameInstant(zone) }
        runCatching { return Instant.parse(text).atZone(zone) }
        runCatching { return LocalDateTime.parse(text).atZone(zone) }
        runCatching { return LocalDate.parse(text).atStartOfDay(zone) }
        error("Invalid time format: '$text'. Use ISO-8601 date/date-time or epoch milliseconds.")
    }
}

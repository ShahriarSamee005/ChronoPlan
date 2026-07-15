package com.example.chronoplan

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val permissionChannel = "com.example.chronoplan/usage_permission"
    private val usageStatsChannel  = "com.example.chronoplan/usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUsageAccessGranted"   -> result.success(checkUsagePermission())
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usageStatsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "queryUsageEvents" -> {
                        val startMs = toLong(call.argument("startMs"))
                        val endMs   = toLong(call.argument("endMs"))
                        result.success(queryUsageEvents(startMs, endMs))
                    }
                    "queryUsageEventsDebug" -> {
                        val startMs = toLong(call.argument("startMs"))
                        val endMs   = toLong(call.argument("endMs"))
                        result.success(queryUsageEventsDebug(startMs, endMs))
                    }
                    "resolveAppInfo" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        result.success(resolveAppInfo(packages))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Production query.  Only the five event types the Dart session-reconstruction
     * algorithm needs are emitted; all others are silently dropped.
     *
     *  1  = MOVE_TO_FOREGROUND     → opens a foreground session for the package
     *  2  = MOVE_TO_BACKGROUND     → closes the session for that package
     *  16 = SCREEN_NON_INTERACTIVE → screen off; close whatever is currently open
     *  17 = KEYGUARD_SHOWN         → lock screen shown; close whatever is open
     *  26 = DEVICE_SHUTDOWN        → device reboot; close whatever is open
     *                                (API 30+; safe to match on older API — event won't fire)
     *
     * Events 16/17/26 carry no meaningful packageName; the Dart side treats them
     * as a global session-break signal and ignores the "p" field.
     *
     * The previous code hardcoded 22 as DEVICE_SHUTDOWN — that constant is actually
     * ROLLOVER_FOREGROUND_SERVICE and was never the right event.  26 is used here
     * directly to avoid a @RequiresApi guard while matching the Dart-side constant.
     */
    private fun queryUsageEvents(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val usm = getSystemService(UsageStatsManager::class.java) ?: return emptyList()
        val usageEvents = usm.queryEvents(startMs, endMs) ?: return emptyList()
        val events = mutableListOf<Map<String, Any>>()
        val event  = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            when (event.eventType) {
                1,   // MOVE_TO_FOREGROUND
                2,   // MOVE_TO_BACKGROUND
                16,  // SCREEN_NON_INTERACTIVE
                17,  // KEYGUARD_SHOWN
                26,  // DEVICE_SHUTDOWN
                -> events.add(mapOf(
                    "p"  to (event.packageName ?: ""),
                    "t"  to event.eventType,
                    "ts" to event.timeStamp,
                ))
                else -> { /* other event types not needed for session reconstruction */ }
            }
        }
        return events
    }

    /**
     * Debug query: emits every event type unfiltered with a human-readable
     * "tn" (type name) field alongside the standard "p"/"t"/"ts" keys,
     * so the diagnostic screen can display them directly.
     */
    private fun queryUsageEventsDebug(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val usm = getSystemService(UsageStatsManager::class.java) ?: return emptyList()
        val usageEvents = usm.queryEvents(startMs, endMs) ?: return emptyList()
        val events = mutableListOf<Map<String, Any>>()
        val event  = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            events.add(mapOf(
                "p"  to (event.packageName ?: ""),
                "t"  to event.eventType,
                "tn" to eventTypeName(event.eventType),
                "ts" to event.timeStamp,
            ))
        }
        return events.sortedBy { it["ts"] as Long }
    }

    private fun eventTypeName(type: Int): String = when (type) {
        1  -> "FOREGROUND"
        2  -> "BACKGROUND"
        5  -> "CONFIGURATION_CHANGE"
        6  -> "SYSTEM_INTERACTION"
        7  -> "USER_INTERACTION"
        15 -> "SCREEN_INTERACTIVE"
        16 -> "SCREEN_NON_INTERACTIVE"
        17 -> "KEYGUARD_SHOWN"
        18 -> "KEYGUARD_HIDDEN"
        26 -> "DEVICE_SHUTDOWN"
        else -> "TYPE_$type"
    }

    /**
     * Resolves the display label and user-facing flag for each package via
     * PackageManager.  A package is non-user-facing if it is a system app
     * (FLAG_SYSTEM) or is our own package.  Unresolvable packages (uninstalled)
     * fall back to the last dot-segment as label with userFacing=true (safe over-count).
     */
    private fun resolveAppInfo(packages: List<String>): Map<String, Map<String, Any>> {
        val pm     = packageManager
        val ownPkg = packageName
        val result = mutableMapOf<String, Map<String, Any>>()
        for (pkg in packages) {
            try {
                val info       = pm.getApplicationInfo(pkg, 0)
                val label      = pm.getApplicationLabel(info).toString()
                val isSystem   = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val userFacing = !isSystem && pkg != ownPkg
                result[pkg] = mapOf("label" to label, "userFacing" to userFacing)
            } catch (_: Exception) {
                result[pkg] = mapOf(
                    "label"      to (pkg.split(".").lastOrNull() ?: pkg),
                    "userFacing" to true,
                )
            }
        }
        return result
    }

    private fun checkUsagePermission(): Boolean {
        val appOps = getSystemService(AppOpsManager::class.java) ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun toLong(value: Any?): Long = when (value) {
        is Long -> value
        is Int  -> value.toLong()
        else    -> 0L
    }
}

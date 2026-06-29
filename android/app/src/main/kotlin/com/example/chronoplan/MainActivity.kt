package com.example.chronoplan

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Handles permission check + settings navigation (unchanged from Phase 1).
    private val permissionChannel = "com.example.chronoplan/usage_permission"

    // Handles raw usage-event queries for accurate per-hour session reconstruction.
    private val usageStatsChannel = "com.example.chronoplan/usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUsageAccessGranted" -> result.success(checkUsagePermission())
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
                        // Dart sends DateTime.millisecondsSinceEpoch (int).
                        // Flutter's standard codec encodes values > 2^31 as Long;
                        // handle both Int and Long defensively.
                        val startMs = toLong(call.argument("startMs"))
                        val endMs   = toLong(call.argument("endMs"))
                        result.success(queryUsageEvents(startMs, endMs))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Returns raw MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND (and DEVICE_SHUTDOWN)
     * events in [startMs, endMs] as a flat list of maps with short keys:
     *   "p"  – packageName
     *   "t"  – eventType  (1 = foreground, 2 = background, 22 = device shutdown)
     *   "ts" – timeStamp  (milliseconds since epoch)
     *
     * Events are returned in the order the OS provides them (chronological per doc).
     * Session reconstruction and per-hour slicing happen entirely in Dart.
     *
     * queryEvents only retains raw events for a limited recent window (typically
     * a few days on AOSP). Deep historical backfill is not possible via this path.
     */
    private fun queryUsageEvents(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val usm = getSystemService(UsageStatsManager::class.java) ?: return emptyList()
        val usageEvents = usm.queryEvents(startMs, endMs) ?: return emptyList()

        val events = mutableListOf<Map<String, Any>>()
        val event = UsageEvents.Event()

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,   // 1
                UsageEvents.Event.MOVE_TO_BACKGROUND,   // 2
                22,                                      // DEVICE_SHUTDOWN (API 28+)
                -> events.add(
                    mapOf(
                        "p"  to event.packageName,
                        "t"  to event.eventType,
                        "ts" to event.timeStamp,
                    )
                )
                else -> { /* ignore other event types */ }
            }
        }
        return events
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

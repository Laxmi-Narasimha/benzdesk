package com.benzpackaging.employee

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager worker that runs every 15 minutes (the Android minimum
 * for periodic work) and resuscitates the BackgroundService when it's
 * been killed.
 *
 * Why this exists: even with a sticky foreground service + battery
 * exemption, every aggressive OEM (Xiaomi MIUI, Vivo FuntouchOS, Oppo
 * ColorOS, Samsung's "deep sleep") will eventually kill our process
 * during a multi-hour field session. The OS will NOT restart a stuck
 * foreground service by itself — and that's why the user kept seeing
 * "after 2 hours unattended the app stops tracking".
 *
 * The fix is to register a JobScheduler entry that lives in *system*
 * state, not in our process. When the system fires it, the OS has to
 * start *some* process to run our Worker, which then re-starts the
 * BackgroundService for us. Even if the OS killed us 1h59m ago, we
 * come back within ~minutes.
 *
 * Trigger logic:
 *  - read the heartbeat timestamp the BG isolate writes to
 *    SharedPreferences (`flutter.tracking_last_gps_fix_at`) every fix
 *  - if it's missing OR older than 3 minutes, AND a session is active
 *    (`flutter.tracking_session_id` is set), restart the service
 *  - otherwise no-op (cheap tick)
 */
class TrackingWatchdogWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    companion object {
        private const val TAG = "TrackingWatchdog"
        // Flutter's SharedPreferences plugin namespaces every key under
        // this prefix on Android. Without it, getLong returns 0.
        private const val FLUTTER_PREFIX = "flutter."
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_LAST_FIX_MS = "${FLUTTER_PREFIX}tracking_last_gps_fix_at"
        private const val KEY_SESSION_ID = "${FLUTTER_PREFIX}tracking_session_id"
        private const val KEY_IS_TRACKING = "${FLUTTER_PREFIX}tracking_is_active"
        private const val STALE_THRESHOLD_MS = 3 * 60 * 1000L // 3 minutes
        // The BackgroundService class shipped by flutter_background_service.
        // We can't `import` it here because the AAR isn't on our classpath
        // at compile time, but Class.forName() resolves it at runtime.
        private const val BG_SERVICE_CLASS =
            "id.flutter.flutter_background_service.BackgroundService"
    }

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isTracking = prefs.getBoolean(KEY_IS_TRACKING, false)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)

        if (!isTracking || sessionId.isNullOrEmpty()) {
            Log.d(TAG, "No active session — nothing to babysit. Returning success.")
            return Result.success()
        }

        val lastFixMs = prefs.getLong(KEY_LAST_FIX_MS, 0L)
        val now = System.currentTimeMillis()
        val stale = lastFixMs == 0L || (now - lastFixMs) > STALE_THRESHOLD_MS

        if (!stale) {
            Log.d(TAG, "Heartbeat fresh (${(now - lastFixMs) / 1000}s old). All good.")
            return Result.success()
        }

        val ageSec = if (lastFixMs == 0L) -1 else (now - lastFixMs) / 1000
        Log.w(TAG, "Heartbeat STALE (${ageSec}s old) — restarting BackgroundService.")

        return try {
            val clazz = Class.forName(BG_SERVICE_CLASS)
            val intent = Intent(applicationContext, clazz)
            ContextCompat.startForegroundService(applicationContext, intent)
            Log.i(TAG, "startForegroundService dispatched.")
            // Also re-arm the AlarmManager backup since we now have proof
            // the OS killed us — it'll probably do it again.
            TrackingAlarmReceiver.scheduleNext(applicationContext)
            Result.success()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to restart BackgroundService: $t")
            // Retry on next periodic tick rather than failing the worker
            // permanently (Result.failure() would stop the work chain).
            Result.retry()
        }
    }
}

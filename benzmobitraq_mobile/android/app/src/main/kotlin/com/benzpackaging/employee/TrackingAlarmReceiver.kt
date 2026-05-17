package com.benzpackaging.employee

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Belt-and-suspenders for WorkManager. WorkManager's 15-minute minimum
 * period can stretch to 30+ minutes under Doze, which is too slow for
 * a "stop tracking and you've lost 30 minutes of distance" symptom.
 *
 * We schedule an EXACT alarm (USE_EXACT_ALARM permission already in the
 * manifest) for 5 minutes from now. When it fires, we do the same
 * heartbeat-staleness check as the worker, restart the service if
 * needed, then re-schedule ourselves for the next 5-minute window.
 *
 * Exact alarms are honoured even in Doze (they're the same mechanism
 * Clock alarms use). So this is the fastest backstop we have.
 */
class TrackingAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackingAlarm"
        private const val ACTION = "com.benzpackaging.employee.TRACKING_WATCHDOG_TICK"
        private const val REQUEST_CODE = 7702
        private const val INTERVAL_MS = 5 * 60 * 1000L
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_LAST_FIX_MS = "flutter.tracking_last_gps_fix_at"
        private const val KEY_SESSION_ID = "flutter.tracking_session_id"
        private const val KEY_IS_TRACKING = "flutter.tracking_is_active"
        private const val STALE_THRESHOLD_MS = 3 * 60 * 1000L
        private const val BG_SERVICE_CLASS =
            "id.flutter.flutter_background_service.BackgroundService"

        fun scheduleNext(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(ctx, TrackingAlarmReceiver::class.java).apply { action = ACTION }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val pi = PendingIntent.getBroadcast(ctx, REQUEST_CODE, intent, flags)
            val triggerAt = SystemClock.elapsedRealtime() + INTERVAL_MS

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !am.canScheduleExactAlarms()
                ) {
                    // User hasn't granted SCHEDULE_EXACT_ALARM — fall back
                    // to a normal (inexact) alarm. Still fires, just may
                    // be delayed by a few minutes under Doze.
                    am.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi,
                    )
                } else {
                    am.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi,
                    )
                }
                Log.d(TAG, "Scheduled next watchdog tick in 5 min.")
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to schedule alarm: $t")
            }
        }

        fun cancel(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(ctx, TrackingAlarmReceiver::class.java).apply { action = ACTION }
            val flags = PendingIntent.FLAG_NO_CREATE or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val pi = PendingIntent.getBroadcast(ctx, REQUEST_CODE, intent, flags)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
                Log.d(TAG, "Cancelled scheduled watchdog alarm.")
            }
        }
    }

    override fun onReceive(ctx: Context, intent: Intent?) {
        Log.d(TAG, "Tick received: action=${intent?.action}")
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isTracking = prefs.getBoolean(KEY_IS_TRACKING, false)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)

        if (!isTracking || sessionId.isNullOrEmpty()) {
            Log.d(TAG, "Not tracking — not re-scheduling.")
            return
        }

        val lastFixMs = prefs.getLong(KEY_LAST_FIX_MS, 0L)
        val now = System.currentTimeMillis()
        val stale = lastFixMs == 0L || (now - lastFixMs) > STALE_THRESHOLD_MS

        if (stale) {
            val ageSec = if (lastFixMs == 0L) -1 else (now - lastFixMs) / 1000
            Log.w(TAG, "Heartbeat STALE (${ageSec}s) — restarting BackgroundService.")
            try {
                val clazz = Class.forName(BG_SERVICE_CLASS)
                val serviceIntent = Intent(ctx, clazz)
                ContextCompat.startForegroundService(ctx, serviceIntent)
            } catch (t: Throwable) {
                Log.e(TAG, "Service restart failed: $t")
            }
        } else {
            Log.d(TAG, "Heartbeat fresh — no restart needed.")
        }

        // Always re-schedule so we keep ticking. Cancel() is the only
        // way to stop us (called from Dart when the session ends).
        scheduleNext(ctx)
    }
}

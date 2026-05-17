package com.benzpackaging.employee

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BOOT_COMPLETED handler that re-arms both watchdog mechanisms after a
 * device restart (or after our APK is upgraded via MY_PACKAGE_REPLACED).
 *
 * Android clears scheduled alarms and WorkManager work-requests across
 * reboot, so without this our watchdogs would silently stop ticking on
 * a phone that was rebooted mid-session — a real failure mode on cheap
 * Indian Android phones that auto-reboot to clear RAM.
 *
 * The flutter_background_service library's own BootReceiver restarts
 * the BackgroundService when autoStartOnBoot=true (it's set in
 * tracking_service.dart). That handles the FIRST tick; we handle every
 * tick after.
 *
 * Only re-arms if a session is actually in progress (tracking_is_active
 * is true in SharedPreferences). If the user wasn't tracking when the
 * phone rebooted, we stay quiet.
 */
class TrackingBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackingBoot"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_IS_TRACKING = "flutter.tracking_is_active"
    }

    override fun onReceive(ctx: Context, intent: Intent?) {
        Log.i(TAG, "Boot completed (action=${intent?.action}) — re-arming watchdogs.")

        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isTracking = prefs.getBoolean(KEY_IS_TRACKING, false)
        if (!isTracking) {
            Log.i(TAG, "No active session — staying quiet.")
            return
        }

        TrackingWatchdogScheduler.schedule(ctx)
        TrackingAlarmReceiver.scheduleNext(ctx)
    }
}

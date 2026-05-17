package com.benzpackaging.employee

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Single entry point used from MethodChannel to arm and disarm both
 * watchdog mechanisms together. Dart calls schedule() when a session
 * starts and cancel() when it ends.
 */
object TrackingWatchdogScheduler {
    private const val TAG = "WatchdogSched"
    private const val PERIODIC_WORK_NAME = "tracking_watchdog_periodic"

    fun schedule(ctx: Context) {
        Log.i(TAG, "Arming watchdog (WorkManager 15-min + AlarmManager 5-min).")

        // WorkManager periodic — survives Doze, app kill, OEM cleanup.
        // KEEP existing policy: if we're already scheduled, don't reset
        // the next-run timer (avoids "the watchdog keeps getting pushed
        // back" if the user starts+stops a session quickly).
        val constraints = Constraints.Builder().build()
        val periodicWork = PeriodicWorkRequestBuilder<TrackingWatchdogWorker>(
            15, TimeUnit.MINUTES,
            // Flex interval — Android may run us anywhere in the last
            // 5 min of the 15 min window, giving the scheduler room to
            // batch our wake-up with others' (better for battery).
            5, TimeUnit.MINUTES,
        )
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            periodicWork,
        )

        // AlarmManager exact — finer-grained backup (5 min).
        TrackingAlarmReceiver.scheduleNext(ctx)
    }

    fun cancel(ctx: Context) {
        Log.i(TAG, "Disarming watchdog.")
        WorkManager.getInstance(ctx).cancelUniqueWork(PERIODIC_WORK_NAME)
        TrackingAlarmReceiver.cancel(ctx)
    }
}

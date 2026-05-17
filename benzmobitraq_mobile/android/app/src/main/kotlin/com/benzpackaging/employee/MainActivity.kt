package com.benzpackaging.employee

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The autostart / battery / app-info screens we try to open are
 * device-specific. Stock Android exposes everything we need, but
 * Xiaomi (MIUI), Vivo (FuntouchOS), Oppo / Realme (ColorOS), Huawei
 * (EMUI), Samsung (OneUI) and a few others have private "autostart
 * manager" or "background battery" screens that the OS hides from
 * the standard Settings.ACTION_* intents. If we don't take the user
 * straight to those screens, they will *never* find them — and the
 * tracking service will be killed silently after every screen-off.
 *
 * Dart side calls into a MethodChannel ("benzmobitraq/oem"):
 *   - getManufacturer  -> "xiaomi" | "vivo" | "samsung" | ...
 *   - openAutoStart    -> tries OEM-specific intents in order, returns
 *                          true if at least one resolved
 *   - openBatterySaver -> opens the battery-optimisation screen
 *   - openAppInfo      -> always works, fallback for stock Android
 */
class MainActivity : FlutterActivity() {
    private val oemChannel = "benzmobitraq/oem"
    private val alarmChannel = "benzmobitraq/alarm"

    // Active ringtone instance — kept so we can stop() it later.
    private var activeRingtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()

        // Let our window appear over the lock screen and turn the
        // screen on when the system delivers a full-screen-intent
        // notification — same flags Clock-app alarms use.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            oemChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getManufacturer" -> result.success(Build.MANUFACTURER?.lowercase() ?: "")
                "openAutoStart" -> result.success(openAutoStart())
                "openBatterySaver" -> result.success(openBatterySaver())
                "openAppInfo" -> result.success(openAppInfo())
                else -> result.notImplemented()
            }
        }

        // Alarm channel: lets Dart play the system default alarm tone
        // through the alarm audio stream, in a loop, regardless of
        // ringer/silent mode. This is what makes the stationary
        // alarm actually RING like a clock-alarm instead of just
        // showing a silent notification.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            alarmChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    startAlarm()
                    result.success(true)
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAlarm() {
        // Always stop any previous ringtone before starting a new one.
        stopAlarm()
        try {
            // Prefer the user's default ALARM tone. Fall back to the
            // ringtone, then the notification sound, so we play
            // something audible no matter how the device is configured.
            var uri: Uri? =
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (uri == null) {
                uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }
            if (uri == null) {
                uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
            if (uri == null) return

            val rt = RingtoneManager.getRingtone(applicationContext, uri)
            // Route through the ALARM stream so the OS plays it at
            // alarm volume + ignores ringer-silent / DND settings (the
            // same way a Clock-app alarm does).
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            rt.audioAttributes = attrs
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                rt.isLooping = true
            }
            // Make sure the alarm volume isn't muted to zero — many
            // phones ship with alarm volume at 30% by default which
            // is fine, but if a user accidentally set it to 0 we
            // bump it up to ~60% so the alarm is actually audible.
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (am != null) {
                    val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    val curVol = am.getStreamVolume(AudioManager.STREAM_ALARM)
                    if (curVol < maxVol * 0.4f) {
                        am.setStreamVolume(
                            AudioManager.STREAM_ALARM,
                            (maxVol * 0.6f).toInt(),
                            0
                        )
                    }
                }
            } catch (_: Exception) {
            }
            rt.play()
            activeRingtone = rt
        } catch (_: Exception) {
            // Best effort — never crash because we couldn't ring.
        }
    }

    private fun stopAlarm() {
        try {
            activeRingtone?.stop()
        } catch (_: Exception) {
        }
        activeRingtone = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    /**
     * Returns true if any OEM-specific autostart intent could be resolved
     * and launched. We try the known component names for each vendor; we
     * never throw — falling back to the standard app-info screen is the
     * caller's job if every attempt here misses.
     */
    private fun openAutoStart(): Boolean {
        val candidates = listOf(
            // Xiaomi / MIUI / Redmi / POCO
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // Letv / LeEco
            ComponentName(
                "com.letv.android.letvsafe",
                "com.letv.android.letvsafe.AutobootManageActivity"
            ),
            // Huawei / Honor
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            // Oppo / Realme / ColorOS
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            // Vivo / FuntouchOS / iQOO
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            ComponentName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
            ),
            // Samsung / OneUI (battery-protection screen — closest analog)
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"
            ),
            // Asus ROG / ZenUI
            ComponentName(
                "com.asus.mobilemanager",
                "com.asus.mobilemanager.autostart.AutoStartActivity"
            ),
            // OnePlus / OxygenOS
            ComponentName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            )
        )

        // We deliberately do NOT use resolveActivity() here — on
        // Android 11+ it returns null for any component name we
        // didn't declare in <queries>, but we can't declare every
        // OEM component (the list is too long and changes). Just
        // try startActivity() optimistically; the OS throws
        // ActivityNotFoundException if the component doesn't exist
        // and we move on to the next candidate.
        for (component in candidates) {
            try {
                val intent = Intent().apply {
                    this.component = component
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next candidate
            }
        }
        return false
    }

    /**
     * Battery-optimisation exclusion screen.
     *
     * Tries 3 intents in order; first one that startActivity() accepts
     * wins. We deliberately do NOT use resolveActivity() as a guard
     * because on Android 11+ it returns null for any intent we didn't
     * declare in <queries> — even when the system can absolutely
     * handle the intent. resolveActivity is a permission check, not a
     * capability check. Better to optimistically startActivity and
     * catch the exception.
     *
     * Intent priority (user wants the Unrestricted/Smart-control screen,
     * NOT the bare "Allow background usage" Yes/No dialog):
     *   1. APPLICATION_DETAILS_SETTINGS — opens our app's info page.
     *      One tap from here is "Battery" → "Unrestricted / Optimized /
     *      Restricted" radio buttons on Android 12+. On Samsung/Xiaomi
     *      this is also where you remove the app from Smart Control /
     *      auto-managed battery. This is the screen the user actually
     *      needs to mark this app Unrestricted.
     *   2. IGNORE_BATTERY_OPTIMIZATION_SETTINGS — full list fallback,
     *      user finds our app and toggles it.
     *   3. REQUEST_IGNORE_BATTERY_OPTIMIZATIONS with package URI —
     *      last-resort Allow/Deny dialog. Avoid as primary because
     *      OEMs (Xiaomi/Vivo/Oppo) silently lie about its success
     *      while keeping the app under Smart Control, AND it does
     *      not surface the Unrestricted radio button at all.
     */
    private fun openBatterySaver(): Boolean {
        // 1. App details — the Battery sub-screen has the Unrestricted radio.
        try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:$packageName")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {
            // fall through
        }
        // 2. The full battery-optimization list.
        try {
            val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {
            // fall through
        }
        // 3. Last-resort Allow/Deny dialog.
        try {
            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = android.net.Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private fun openAppInfo(): Boolean {
        return try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:$packageName")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val trackingChannel = NotificationChannel(
                "benzmobitraq_tracking",
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when location tracking is active"
                setShowBadge(false)
            }

            val alertChannel = NotificationChannel(
                "high_importance_channel",
                "Alerts & Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Important alerts and push notifications"
            }

            val trackingAlertChannel = NotificationChannel(
                "benzmobitraq_tracking_alerts",
                "Tracking Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical alerts when GPS or tracking is not working correctly"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200, 150, 200, 150, 200)
                setShowBadge(true)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(trackingChannel)
            notificationManager.createNotificationChannel(alertChannel)
            notificationManager.createNotificationChannel(trackingAlertChannel)
        }
    }
}

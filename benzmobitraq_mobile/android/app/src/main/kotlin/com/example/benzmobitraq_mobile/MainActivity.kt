package com.example.benzmobitraq_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Tracking notification channel (for foreground service)
            val trackingChannel = NotificationChannel(
                "benzmobitraq_tracking",
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when location tracking is active"
                setShowBadge(false)
            }

            // High importance channel (for alerts)
            val alertChannel = NotificationChannel(
                "high_importance_channel",
                "Alerts & Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Important alerts and push notifications"
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(trackingChannel)
            notificationManager.createNotificationChannel(alertChannel)
        }
    }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart';

import 'package:benzmobitraq_mobile/core/constants/app_constants.dart';
import 'package:benzmobitraq_mobile/core/di/injection.dart';
import 'package:benzmobitraq_mobile/core/router/app_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background message handler — MUST be a top-level function (not a closure).
/// This runs in a SEPARATE isolate when the app is killed/backgrounded.
/// It must re-initialize any plugins it needs (Firebase + local_notifications).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Re-initialize Firebase in the background isolate
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Show a local notification so the user sees it even when app is closed.
  // We must initialize the plugin fresh in this isolate.
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  final title = message.notification?.title
      ?? message.data['title'] as String?
      ?? 'BenzMobiTraq';
  final body = message.notification?.body
      ?? message.data['body'] as String?
      ?? message.data['message'] as String?
      ?? '';

  if (body.isEmpty) return; // Nothing to show

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'benzmobitraq_notifications',
        'BenzMobiTraq Notifications',
        channelDescription: 'Notifications for BenzMobiTraq app',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

/// Service for handling push notifications via FCM
/// This service is OPTIONAL - the app works without Firebase
class NotificationService {
  // Make these lazy - only accessed when initialize() is called
  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();

  bool _initialized = false;
  bool _firebaseAvailable = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'benzmobitraq_notifications',
    'BenzMobiTraq Notifications',
    description: 'Notifications for BenzMobiTraq app',
    importance: Importance.high,
    playSound: true,
  );

  static const AndroidNotificationChannel _trackingChannel =
      AndroidNotificationChannel(
    'benzmobitraq_tracking',
    'Location Tracking',
    description: 'Background location tracking notification',
    importance: Importance.defaultImportance, // Higher to prevent dismissal
    playSound: false,
    showBadge: false,
  );

  /// Critical tracking alert channel - used when tracking stalls or GPS is bad.
  /// Uses MAX importance + vibration to grab the user's attention immediately.
  static const AndroidNotificationChannel _alertChannel =
      AndroidNotificationChannel(
    'benzmobitraq_tracking_alerts',
    'Tracking Alerts',
    description: 'Critical alerts when GPS or tracking is not working correctly',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  /// Persistent "no internet" channel. Stays in the tray until the device
  /// reconnects — so the user can never miss the fact that submissions
  /// are being queued locally instead of going to the server.
  static const AndroidNotificationChannel _offlineChannel =
      AndroidNotificationChannel(
    'benzmobitraq_offline',
    'Offline Status',
    description: 'Persistent reminder when the device has no internet',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
    showBadge: true,
  );

  /// Fixed notification id for the persistent offline reminder.
  static const int _offlineNotificationId = 90100;

  /// Stationary alarm channel. Uses `category: alarm` + `fullScreenIntent`
  /// so on Android 14+ it surfaces OVER the lock screen with the
  /// platform alarm sound — same behavior as Clock-app alarms. The
  /// user can configure / silence in OS Settings → Apps → Benz
  /// Packaging → Notifications → Stationary Alarm.
  static const AndroidNotificationChannel _alarmChannel =
      AndroidNotificationChannel(
    'benzmobitraq_stationary_alarm',
    'Session Alarm',
    description:
        'Sounds when your session has been stationary or paused too long. Behaves like an alarm clock so you do not miss it.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Fixed notification id for the stationary / pause-expired alarm
  /// so re-firing replaces the previous notification cleanly.
  static const int alarmNotificationId = 90200;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Try to get Firebase Messaging - this will fail if Firebase isn't initialized
      try {
        _messaging = FirebaseMessaging.instance;
        _firebaseAvailable = true;
        _logger.i('Firebase Messaging available');
      } catch (e) {
        _logger.w('Firebase not available, push notifications disabled: $e');
        _firebaseAvailable = false;
      }

      // Initialize local notifications first (always works)
      await _initLocalNotifications();

      // Only set up Firebase if available
      if (_firebaseAvailable && _messaging != null) {
        // Request permission
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        _logger.i('Notification permission: ${settings.authorizationStatus}');

        // Set up background handler
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle notification taps when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // Check if app was opened from a notification
        final initialMessage = await _messaging!.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }
      }

      _initialized = true;
      _logger.i('Notification service initialized (Firebase: $_firebaseAvailable)');
    } catch (e) {
      _logger.e('Error initializing notification service: $e');
      // Mark as initialized anyway to prevent repeated failures
      _initialized = true;
    }
  }

  /// Initialize local notifications plugin
  Future<void> _initLocalNotifications() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create notification channels
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      await android.createNotificationChannel(_channel);
      await android.createNotificationChannel(_trackingChannel);
      await android.createNotificationChannel(_alertChannel);
      await android.createNotificationChannel(_offlineChannel);
      await android.createNotificationChannel(_alarmChannel);
    }
  }

  /// Fire the stationary / pause-expired alarm. Behaves like a Clock-
  /// app alarm: full-screen intent over the lock screen, plays the
  /// system alarm sound (whatever the user has set as their default),
  /// vibrates with an alarm-style pattern.
  ///
  /// Tap → opens the app to the alarm dialog (handled by router).
  Future<void> showSessionAlarm({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // THREE LONG vibrations at maximum amplitude. Pattern format is
    // [wait, vibrate, wait, vibrate, ...]. 900ms ON pulses with 250ms
    // gaps land much harder than the old quick pulses — the user
    // physically can't ignore this when their phone is in a pocket.
    final pattern =
        Int64List.fromList([0, 900, 250, 900, 250, 900]);
    final android = AndroidNotificationDetails(
      _alarmChannel.id,
      _alarmChannel.name,
      channelDescription: _alarmChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFE65100),
      enableVibration: true,
      vibrationPattern: pattern,
      playSound: true,
      // null = the device's default ALARM sound (not notification
      // sound). Honours the user's "preferred alarm tone" system
      // setting, which is the closest thing Android has to "use my
      // ringtone" without us shipping a custom audio file.
      sound: null,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      ticker: title,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    try {
      await _localNotifications.show(
        alarmNotificationId,
        title,
        body,
        NotificationDetails(android: android, iOS: ios),
        payload: data == null ? null : jsonEncode({...data, 'kind': 'session_alarm'}),
      );
    } catch (e) {
      _logger.e('Failed to show session alarm: $e');
    }
    // Manual vibration as a hard guarantee — some OEMs ignore the
    // channel pattern under Do Not Disturb.
    try {
      final has = await Vibration.hasVibrator();
      if (has) {
        // Same long-pulse pattern as the notification, with
        // maximum amplitude where supported.
        await Vibration.vibrate(
          pattern: [0, 900, 250, 900, 250, 900],
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
    } catch (_) {}
  }

  Future<void> cancelSessionAlarm() async {
    try {
      await _localNotifications.cancel(alarmNotificationId);
    } catch (_) {}
  }

  /// Fixed id for the pause-countdown notification (separate from the
  /// alarm itself — this one is the soft "you're paused, 1m 45s left"
  /// reminder that ticks down).
  static const int pauseCountdownNotificationId = 90201;

  /// Show or update the pause countdown banner. Idempotent — calling
  /// repeatedly just refreshes the text on the same notification, so
  /// the user sees a live countdown instead of a stack of duplicates.
  Future<void> showPauseCountdown({
    required Duration remaining,
    required Duration originalDuration,
  }) async {
    String fmt(Duration d) {
      if (d.isNegative) d = Duration.zero;
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      if (m > 0) return '${m}m ${s}s';
      return '${s}s';
    }

    final body = remaining.isNegative || remaining == Duration.zero
        ? 'Pause time is up. Tap to resume, extend, or end the session.'
        : 'Pause: ${fmt(remaining)} remaining. Tap to manage.';
    final androidDetails = AndroidNotificationDetails(
      _trackingChannel.id,
      _trackingChannel.name,
      channelDescription: _trackingChannel.description,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      // showWhen + when + usesChronometer would render a native
      // count-up timer, but flutter_local_notifications' Android
      // chronometer is count-up only and not reliably supported on
      // every OEM. Rolling our own text-update every 10s is more
      // portable.
      category: AndroidNotificationCategory.status,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEA580C),
      styleInformation: BigTextStyleInformation(body),
    );
    try {
      await _localNotifications.show(
        pauseCountdownNotificationId,
        'Session paused',
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      _logger.w('Failed to show pause-countdown notification: $e');
    }
  }

  Future<void> cancelPauseCountdown() async {
    try {
      await _localNotifications.cancel(pauseCountdownNotificationId);
    } catch (_) {}
  }

  /// Show the sticky "no internet" notification. Safe to call repeatedly —
  /// flutter_local_notifications replaces by id.
  Future<void> showPersistentOfflineNotification({
    bool sessionActive = false,
  }) async {
    final body = sessionActive
        ? 'Tracking your session offline. Distance is being saved locally and any expenses you log will be reconciled with Google Maps when internet returns.'
        : 'You are offline. Anything you submit will be queued and synced automatically once internet returns.';

    final androidDetails = AndroidNotificationDetails(
      _offlineChannel.id,
      _offlineChannel.name,
      channelDescription: _offlineChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // Sticky — user cannot swipe it away
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.status,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEA580C),
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
    );

    try {
      await _localNotifications.show(
        _offlineNotificationId,
        'No internet — working offline',
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      _logger.e('Failed to show offline notification: $e');
    }
  }

  /// Remove the sticky offline notification (call on reconnect).
  Future<void> cancelOfflineNotification() async {
    try {
      await _localNotifications.cancel(_offlineNotificationId);
    } catch (e) {
      _logger.w('Failed to cancel offline notification: $e');
    }
  }

  /// Best-effort: dismiss the sticky "Location is OFF" notification and
  /// any of our recent tracking-alert notifications. Called when the
  /// BG isolate reports location services have just been turned back
  /// on — the user shouldn't have to manually swipe these away.
  Future<void> cancelAllStaleAlerts() async {
    // 90010 is the persistent "Location is OFF" notification (ongoing).
    // 90001/90002 are GPS stuck / recovery notifications.
    const ids = [90010, 90001, 90002];
    for (final id in ids) {
      try {
        await _localNotifications.cancel(id);
      } catch (_) {}
    }
  }

  /// Handle foreground message
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Received foreground message: ${message.messageId}');

    final notification = message.notification;
    if (notification == null) return;

    // Show local notification
    await showLocalNotification(
      title: notification.title ?? AppConstants.appName,
      body: notification.body ?? '',
      payload: jsonEncode(message.data),
    );
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    _logger.i('Notification tapped: ${message.messageId}');
    
    // Handle navigation based on notification type
    final data = message.data;
    _handleBackgroundNavigation(data);
  }

  /// Handle local notification tap
  void _onLocalNotificationTap(NotificationResponse response) {
    _logger.i('Local notification tapped: id=${response.id} payload=${response.payload}');

    final payload = response.payload;
    if (payload == null) {
      // Notifications without an explicit payload, but coming from the
      // BG isolate session-alarm channel (ids 90200, 90201, 10002).
      // Bring the user straight to the home screen so they see the
      // pause/resume/stop card.
      _navigateToHome();
      return;
    }

    // BG isolate uses bare string payloads like 'auto_resumed',
    // 'stationary_alarm', 'paused_too_long'. These all want the
    // home screen (where the Pause/Stop buttons live).
    const sessionAlarmPayloads = {
      'auto_resumed',
      'stationary_alarm',
      'paused_too_long',
      'session_alarm',
    };
    if (sessionAlarmPayloads.contains(payload)) {
      _navigateToHome();
      return;
    }

    // Legacy JSON payload path (expense/chat/etc).
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      // Session-alarm carried as JSON also routes home.
      if (data['kind'] == 'session_alarm' ||
          sessionAlarmPayloads.contains(data['kind'])) {
        _navigateToHome();
        return;
      }
      _handleBackgroundNavigation(data);
    } catch (e) {
      _logger.w('Notification payload not JSON (treating as session-alarm): $e');
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    final context = getIt<GlobalKey<NavigatorState>>().currentContext;
    if (context == null) {
      _logger.w('Navigator context null — cannot route alarm tap to home');
      return;
    }
    try {
      // popUntil first in case a dialog/sheet is open over the home
      // screen; then push-and-clear so the back button doesn't bounce
      // the user back to the notification's launcher screen.
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRouter.home,
        (r) => false,
      );
    } catch (e) {
      _logger.e('Failed to navigate to home on alarm tap: $e');
    }
  }

  void _handleBackgroundNavigation(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final requestId = data['request_id'] as String?;
    final claimId = data['claim_id'] as String? ?? requestId;

    final context = getIt<GlobalKey<NavigatorState>>().currentContext;
    if (context == null) {
      _logger.w('NavigatorState context is null, cannot route notification');
      return;
    }

    // Expense / request related: status changes, approvals, rejections
    final expenseTypes = {
      'expense_submitted',
      'expense_approved',
      'expense_rejected',
      'request_status_changed',
      'query_closed',
      'admin_message',
    };
    if (claimId != null && expenseTypes.contains(type)) {
      Navigator.pushNamed(
        context,
        AppRouter.expenseDetail,
        arguments: ExpenseDetailArguments(claimId: claimId),
      );
      return;
    }

    // Chat / message notifications
    if (type == 'chat_message' || type == 'new_message' || type == 'follow_up') {
      Navigator.pushNamed(context, AppRouter.notifications);
      return;
    }

    // Session notifications
    if (type == 'session_started' || type == 'session_ended') {
      Navigator.pushNamed(context, AppRouter.myTimeline);
      return;
    }

    // Default: notifications list
    Navigator.pushNamed(context, AppRouter.notifications);
  }

  /// Get FCM token
  Future<String?> getToken() async {
    if (!_firebaseAvailable || _messaging == null) {
      return null;
    }
    try {
      return await _messaging!.getToken();
    } catch (e) {
      _logger.e('Error getting FCM token: $e');
      return null;
    }
  }

  /// Show a local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    final notificationId = id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  /// Show tracking notification (for foreground service)
  Future<void> showTrackingNotification({
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _trackingChannel.id,
      _trackingChannel.name,
      channelDescription: _trackingChannel.description,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.service,
      usesChronometer: true,
      when: DateTime.now().millisecondsSinceEpoch,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotifications.show(
      AppConstants.trackingNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Update tracking notification
  Future<void> updateTrackingNotification({
    required String body,
  }) async {
    await showTrackingNotification(
      title: 'Tracking Active',
      body: body,
    );
  }

  /// Cancel tracking notification
  Future<void> cancelTrackingNotification() async {
    await _localNotifications.cancel(AppConstants.trackingNotificationId);
  }

  /// Show a critical tracking alert with 3x vibration pattern.
  /// Used when GPS is failing, tracking has stalled, or accuracy is bad.
  ///
  /// Vibration pattern: three short pulses (BookMyShow-style):
  /// wait 0ms, vibrate 200ms, pause 150ms, vibrate 200ms, pause 150ms, vibrate 200ms.
  Future<void> showCriticalTrackingAlert({
    required String title,
    required String body,
    int? id,
  }) async {
    final notificationId = id ?? 90000 + (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000;

    // Pattern lives on the notification channel (Android < 12 honors this)
    // AND we trigger vibration manually as a guaranteed fallback - some
    // devices/ROMs ignore notification vibrationPattern when DND/silent.
    final pattern = Int64List.fromList([0, 200, 150, 200, 150, 200]);

    final androidDetails = AndroidNotificationDetails(
      _alertChannel.id,
      _alertChannel.name,
      channelDescription: _alertChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEF4444),
      enableVibration: true,
      vibrationPattern: pattern,
      playSound: true,
      ticker: title,
      visibility: NotificationVisibility.public,
      fullScreenIntent: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    try {
      await _localNotifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      _logger.e('Failed to show critical alert notification: $e');
    }

    // Trigger 3x vibration manually as a guaranteed fallback.
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(pattern: [0, 200, 150, 200, 150, 200]);
      }
    } catch (e) {
      _logger.w('Manual vibration failed: $e');
    }
  }

  /// Subscribe to topic (for broadcast notifications)
  Future<void> subscribeToTopic(String topic) async {
    if (!_firebaseAvailable || _messaging == null) return;
    try {
      await _messaging!.subscribeToTopic(topic);
      _logger.i('Subscribed to topic: $topic');
    } catch (e) {
      _logger.e('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_firebaseAvailable || _messaging == null) return;
    try {
      await _messaging!.unsubscribeFromTopic(topic);
      _logger.i('Unsubscribed from topic: $topic');
    } catch (e) {
      _logger.e('Error unsubscribing from topic: $e');
    }
  }

  // ============================================================
  // SUPABASE REALTIME FALLBACK (Foreground push when FCM fails)
  // ============================================================

  /// Start listening to Supabase Realtime for new notifications.
  /// This acts as a fallback when FCM push notifications are not working.
  void startRealtimeListener(String employeeId) {
    _logger.i('Starting Supabase Realtime notification listener for $employeeId');

    try {
      Supabase.instance.client
          .channel('notifications_$employeeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: employeeId,
            ),
            callback: (payload) async {
              final newRecord = payload.newRecord;
              final title = newRecord['title'] as String? ?? 'BenzMobiTraq';
              final body = newRecord['body'] as String? ?? '';
              final type = newRecord['type'] as String? ?? 'general';

              _logger.i('Realtime notification received: $type - $title');

              // Show local notification immediately (works in foreground)
              await showLocalNotification(
                title: title,
                body: body,
                payload: jsonEncode({
                  'type': type,
                  'notification_id': newRecord['id'],
                  'related_employee_id': newRecord['related_employee_id'],
                  'related_session_id': newRecord['related_session_id'],
                }),
                id: 20000 + (newRecord['id'].hashCode % 1000).abs(),
              );
            },
          )
          .subscribe();
    } catch (e) {
      _logger.e('Failed to start Realtime listener: $e');
    }
  }
}

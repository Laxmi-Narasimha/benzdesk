import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import '../core/constants/app_constants.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase not configured, ignore
  }
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
    importance: Importance.low,
    playSound: false,
    showBadge: false,
  );

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
    final type = data['type'] as String?;

    switch (type) {
      case 'stuck_alert':
        // Navigate to employee details (for admin)
        break;
      case 'expense_submitted':
        // Navigate to expense approval
        break;
      case 'expense_approved':
      case 'expense_rejected':
        // Navigate to expense details
        break;
      default:
        // Navigate to notifications screen
        break;
    }
  }

  /// Handle local notification tap
  void _onLocalNotificationTap(NotificationResponse response) {
    _logger.i('Local notification tapped: ${response.id}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        // Handle navigation based on payload
      } catch (e) {
        _logger.e('Error parsing notification payload: $e');
      }
    }
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
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
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
}

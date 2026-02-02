import 'dart:async';

import 'package:logger/logger.dart';

import 'notification_service.dart';
import '../data/models/notification_settings.dart';

/// Handles scheduled notifications during active tracking sessions
/// 
/// Monitors both:
/// - Time-based intervals (e.g., every 10 minutes)
/// - Distance-based thresholds (e.g., every 1 km)
/// 
/// Industry-grade implementation with:
/// - Configurable intervals from user settings
/// - Persistent notifications that can't be dismissed
/// - Summary notification when session ends
class NotificationScheduler {
  static final Logger _logger = Logger();
  
  // Timer for periodic checks
  Timer? _periodicTimer;
  
  // Notification service reference
  final NotificationService _notificationService;
  
  // Current settings
  NotificationSettings? _settings;
  
  // Tracking state
  DateTime _sessionStartTime = DateTime.now();
  DateTime _lastTimeNotification = DateTime.now();
  double _lastDistanceNotifiedKm = 0;
  bool _isActive = false;
  
  NotificationScheduler(this._notificationService);
  
  /// Start monitoring with user's preferred notification settings
  /// 
  /// Called when a session starts
  void startMonitoring(NotificationSettings settings) {
    _settings = settings;
    _sessionStartTime = DateTime.now();
    _lastTimeNotification = DateTime.now();
    _lastDistanceNotifiedKm = 0;
    _isActive = true;
    
    _logger.i('NotificationScheduler started: '
        'time=${settings.timeMinutes}min, '
        'distance=${settings.distanceKm}km');
    
    // Show persistent tracking notification
    _showOngoingNotification(0, Duration.zero);
    
    // Start periodic timer (check every 30 seconds for both time and distance)
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkNotificationTriggers(),
    );
  }
  
  /// Called on every location update from TrackingService
  /// 
  /// Checks if distance threshold is met
  void onLocationUpdate(double totalDistanceKm, Duration elapsed) {
    if (!_isActive || _settings == null) return;
    
    // Check distance-based notification
    final distanceSinceLastNotification = totalDistanceKm - _lastDistanceNotifiedKm;
    
    if (distanceSinceLastNotification >= _settings!.distanceKm) {
      _triggerDistanceNotification(totalDistanceKm, elapsed);
      _lastDistanceNotifiedKm = totalDistanceKm;
    }
    
    // Always update the ongoing notification with current stats
    _showOngoingNotification(totalDistanceKm, elapsed);
  }
  
  /// Check if time-based notification should trigger
  void _checkNotificationTriggers() {
    if (!_isActive || _settings == null) return;
    
    final now = DateTime.now();
    final timeSinceLastNotification = now.difference(_lastTimeNotification);
    final timeThreshold = Duration(minutes: _settings!.timeMinutes);
    
    if (timeSinceLastNotification >= timeThreshold) {
      final elapsed = now.difference(_sessionStartTime);
      _triggerTimeNotification(elapsed);
      _lastTimeNotification = now;
    }
  }
  
  /// Show distance-based notification
  void _triggerDistanceNotification(double totalKm, Duration elapsed) {
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    
    _notificationService.showLocalNotification(
      title: '📍 Distance Update',
      body: 'You\'ve traveled ${totalKm.toStringAsFixed(2)} km in ${hours}h ${minutes}m',
    );
    
    _logger.i('Distance notification triggered: ${totalKm}km');
  }
  
  /// Show time-based notification
  void _triggerTimeNotification(Duration elapsed) {
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    
    _notificationService.showLocalNotification(
      title: '⏱️ Time Update',
      body: 'Session running for ${hours}h ${minutes}m',
    );
    
    _logger.i('Time notification triggered: ${elapsed.inMinutes}min');
  }
  
  /// Update the persistent ongoing notification
  void _showOngoingNotification(double totalKm, Duration elapsed) {
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    
    _notificationService.updateTrackingNotification(
      body: '${totalKm.toStringAsFixed(2)} km • ${hours}h ${minutes}m elapsed',
    );
  }
  
  /// Stop monitoring and show session summary
  /// 
  /// Called when session ends
  Future<void> stopMonitoring({
    required double totalKm,
    required Duration totalDuration,
  }) async {
    _isActive = false;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    
    // Cancel the ongoing tracking notification
    await _notificationService.cancelTrackingNotification();
    
    // Show session summary notification
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    
    await _notificationService.showLocalNotification(
      title: '✅ Session Complete',
      body: 'Total: ${totalKm.toStringAsFixed(2)} km in ${hours}h ${minutes}m',
    );
    
    _logger.i('NotificationScheduler stopped. Summary: ${totalKm}km, ${totalDuration.inMinutes}min');
  }
  
  /// Dispose resources
  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isActive = false;
  }
}

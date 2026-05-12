import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:benzmobitraq_mobile/core/constants/app_constants.dart';

/// Location update from the background service
class LocationUpdate {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final double? altitude;
  final double? heading;
  final DateTime timestamp;
  final String? sessionId;
  final double totalDistance;
  final bool isMoving;
  final bool countsForDistance;
  final double distanceDeltaM;

  LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    this.altitude,
    this.heading,
    required this.timestamp,
    this.sessionId,
    required this.totalDistance,
    required this.isMoving,
    this.countsForDistance = false,
    this.distanceDeltaM = 0,
  });

  factory LocationUpdate.fromMap(Map<String, dynamic> map) {
    return LocationUpdate(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0,
      altitude: (map['altitude'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      sessionId: map['sessionId'] as String?,
      totalDistance: (map['totalDistance'] as num?)?.toDouble() ?? 0,
      isMoving: map['isMoving'] as bool? ?? true,
      countsForDistance: map['countsForDistance'] as bool? ?? false,
      distanceDeltaM: (map['distanceDeltaM'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speed': speed,
        'altitude': altitude,
        'heading': heading,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'sessionId': sessionId,
        'totalDistance': totalDistance,
        'isMoving': isMoving,
        'countsForDistance': countsForDistance,
        'distanceDeltaM': distanceDeltaM,
      };
}

/// Robust background location tracking service
///
/// This service handles:
/// - Foreground service for reliable background execution
/// - Motion-aware GPS polling to save battery
/// - Anti-jitter and anti-teleport filtering
/// - Graceful error recovery
///
/// IMPORTANT: This uses flutter_background_service which creates a
/// foreground service on Android with a persistent notification.
/// This is the most reliable way to track location in background.
class TrackingService {
  static final Logger _logger = Logger();
  // LAZY INSTANTIATION: Prevents usage in background isolate
  static FlutterBackgroundService get _service => FlutterBackgroundService();

  // Callbacks for the main isolate
  static Function(LocationUpdate)? onLocationUpdate;
  static Function(String)? onError;
  static Function(bool)? onTrackingStateChanged;
  static Function(Map<String, dynamic>)? onAutoPaused;
  static Function(Map<String, dynamic>)? onAutoResumed;
  static Function(Map<String, dynamic>)? onStationarySpotDetected;

  // HANDSHAKE: Wait for background service to be ready
  static Completer<void>? _serviceReadyCompleter;

  // Storage keys for persisting state across restarts
  static const String _keySessionId = 'tracking_session_id';
  static const String _keyTotalDistance = 'tracking_total_distance';
  static const String _keyLastLat = 'tracking_last_lat';
  static const String _keyLastLon = 'tracking_last_lon';
  static const String _keyIsTracking = 'tracking_is_active';
  static const String _keySessionStartTime = 'session_start_time';
  static const String _keyIsPaused = 'tracking_is_paused';
  static const String _keyPausedDistance = 'tracking_paused_distance';
  static const String _keyAutoPauseAt = 'tracking_auto_pause_at';
  static const String _keySessionDay = 'tracking_session_day';
  static const String _keyLastSpeedKmh = 'tracking_last_speed_kmh';
  static const String _keyLastPositionTime = 'tracking_last_pos_time';

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize the background service
  ///
  /// Must be called once at app startup (in main.dart).
  static Future<void> initialize() async {
    try {
      // Check if already running to avoid crash on re-configure
      final isRunning = await _service.isRunning().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.w('Timeout checking if service is running');
          return false;
        },
      );

      if (isRunning) {
        _logger.i('Tracking service already running, skipping configuration');
        // Re-attach listeners even if running
        _attachListeners();
        return;
      }

      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onServiceStart,
          autoStart: false,
          autoStartOnBoot: true, // CRITICAL: Resume after reboot
          isForegroundMode: true,
          notificationChannelId: 'benzmobitraq_tracking',
          initialNotificationTitle: 'BenzMobiTraq',
          initialNotificationContent: 'Location tracking ready',
          foregroundServiceNotificationId: AppConstants.trackingNotificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onServiceStart,
          onBackground: _onIosBackground,
        ),
      );

      _attachListeners();
      _logger.i('Tracking service initialized');
    } catch (e) {
      _logger.e('Failed to initialize tracking service: $e');
    }
  }

  static void _attachListeners() {
    _service.on('locationUpdate').listen((event) {
      if (event != null) {
        final update = LocationUpdate.fromMap(event);
        onLocationUpdate?.call(update);
      }
    });

    _service.on('error').listen((event) {
      onError?.call(event?['message'] ?? 'Unknown error');
    });

    _service.on('trackingStateChanged').listen((event) {
      onTrackingStateChanged?.call(event?['isTracking'] ?? false);
    });

    _service.on('autoPaused').listen((event) {
      if (event != null) {
        onAutoPaused?.call(Map<String, dynamic>.from(event));
      }
    });

    _service.on('autoResumed').listen((event) {
      if (event != null) {
        onAutoResumed?.call(Map<String, dynamic>.from(event));
      }
    });

    _service.on('stationarySpotDetected').listen((event) {
      if (event != null) {
        onStationarySpotDetected?.call(Map<String, dynamic>.from(event));
      }
    });

    _service.on('serviceReady').listen((event) {
      _logger.i('Handshake: Background service is ready');
      if (_serviceReadyCompleter != null &&
          !_serviceReadyCompleter!.isCompleted) {
        _serviceReadyCompleter!.complete();
      }
    });
  }

  // ============================================================
  // START/STOP TRACKING
  // ============================================================

  /// Start location tracking for a session
  ///
  /// This starts the foreground service and begins GPS updates.
  /// The service will continue running even if the app is killed.
  static Future<bool> startTracking(String sessionId,
      {bool isResume = false}) async {
    try {
      // Verify permissions first
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _logger.e('Cannot start tracking: permission denied');
        onError?.call('Location permission is required');
        return false;
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _logger.e('Cannot start tracking: location services disabled');
        onError?.call('Please enable location services');
        return false;
      }

      // Store session ID for persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySessionId, sessionId);
      await prefs.setBool(_keyIsTracking, true);
      await prefs.setBool(_keyIsPaused, false);
      await prefs.remove(_keyAutoPauseAt);
      await prefs.setString(
          _keySessionDay, DateTime.now().toIso8601String().substring(0, 10));

      // Start the background service if not running
      if (!await _service.isRunning()) {
        await _service.startService();
      }

      // RETRY LOGIC: Send startSession command and wait for ACK
      // This handles race conditions where service is starting or restarting
      bool ackReceived = false;
      int attempts = 0;

      // Setup temporary listener for ACK
      final ackCompleter = Completer<void>();
      final sub = _service.on('sessionStarted').listen((event) {
        if (event?['sessionId'] == sessionId) {
          if (!ackCompleter.isCompleted) ackCompleter.complete();
        }
      });

      try {
        while (!ackReceived && attempts < 5) {
          attempts++;
          _logger.i('Sending startSession command (Attempt $attempts)...');

          _service.invoke('startSession', {
            'sessionId': sessionId,
            'isResume': isResume,
          });

          try {
            await ackCompleter.future
                .timeout(const Duration(milliseconds: 2000));
            ackReceived = true;
            _logger
                .i('ACK received: Session started successfully in background');
          } catch (e) {
            _logger.w('No ACK received within 2s, retrying...');
          }
        }
      } finally {
        await sub.cancel();
      }

      if (!ackReceived) {
        _logger.e('Failed to start session in background after 5 attempts');
        // We still return true because local session is valid, but logging error
        onError?.call('Background tracking failed to acknowledge start');
      }

      _logger.i('Tracking started for session: $sessionId');
      return true;
    } catch (e) {
      _logger.e('Error starting tracking: $e');
      onError?.call('Failed to start tracking: $e');
      return false;
    }
  }

  /// Stop location tracking
  ///
  /// Stops GPS updates and the foreground service.
  /// Returns the final total distance.
  static Future<double> stopTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final totalDistance = prefs.getDouble(_keyTotalDistance) ?? 0;

      // Clear tracking state
      await prefs.remove(_keySessionId);
      await prefs.remove(_keyTotalDistance);
      await prefs.remove(_keyLastLat);
      await prefs.remove(_keyLastLon);
      await prefs.remove(_keyLastPositionTime);
      await prefs.setBool(_keyIsTracking, false);
      await prefs.setBool(_keyIsPaused, false);
      await prefs.remove(_keyPausedDistance);
      await prefs.remove(_keyAutoPauseAt);
      await prefs.remove(_keySessionDay);

      // Stop the service
      _service.invoke('stopSession');

      final isRunning = await _service.isRunning();
      if (isRunning) {
        _service.invoke('stopService');
      }

      _logger.i('Tracking stopped. Total distance: $totalDistance m');
      return totalDistance;
    } catch (e) {
      _logger.e('Error stopping tracking: $e');
      return 0;
    }
  }

  /// Pause tracking (distance stops accumulating, but GPS continues)
  static Future<bool> pauseTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentDistance = prefs.getDouble(_keyTotalDistance) ?? 0;
      await prefs.setBool(_keyIsPaused, true);
      await prefs.setDouble(_keyPausedDistance, currentDistance);
      _service.invoke('pauseSession');
      _logger.i('Tracking paused at ${currentDistance}m');
      return true;
    } catch (e) {
      _logger.e('Error pausing tracking: $e');
      return false;
    }
  }

  /// Resume tracking after pause
  static Future<bool> resumeTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsPaused, false);
      await prefs.remove(_keyAutoPauseAt);
      _service.invoke('resumeSession');
      _logger.i('Tracking resumed');
      return true;
    } catch (e) {
      _logger.e('Error resuming tracking: $e');
      return false;
    }
  }

  /// Check if tracking is currently active
  static Future<bool> isTracking() async {
    try {
      final isRunning = await _service.isRunning();
      if (!isRunning) return false;

      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyIsTracking) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Resume tracking if it was active before app restart
  ///
  /// Call this in main.dart to handle app restarts.
  static Future<void> resumeIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasTracking = prefs.getBool(_keyIsTracking) ?? false;
      final sessionId = prefs.getString(_keySessionId);

      if (wasTracking && sessionId != null) {
        _logger.i('Resuming tracking for session: $sessionId');

        final isRunning = await _service.isRunning();
        if (!isRunning) {
          await startTracking(sessionId, isResume: true);
        }
      }
    } catch (e) {
      _logger.e('Error checking tracking state: $e');
    }
  }

  /// Get current location (one-shot)
  static Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      _logger.e('Error getting current location: $e');
      return null;
    }
  }

  /// Request battery optimization exemption (Android only)
  ///
  /// CRITICAL for background tracking - prevents system from killing the service
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      _logger.i('Requesting battery optimization exemption...');

      // For now, we'll show a dialog to the user to do this manually
      // In future, we can use platform channels to request this programmatically

      // Note: Most modern location tracking apps request this permission
      // to ensure reliable background location tracking
    } catch (e) {
      _logger.e('Error requesting battery exemption: $e');
    }
  }
}

// ============================================================
// BACKGROUND SERVICE ENTRY POINT (runs in separate isolate)
// ============================================================

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final Logger logger = Logger();
  logger.i(
      'DIAGNOSTIC: _onServiceStart EXECUTION STARTED. Service: ${service.hashCode}');

  // State
  String? currentSessionId;
  StreamSubscription<Position>? positionSubscription;
  Timer? stationaryHeartbeatTimer;
  Timer? pausedResumeMonitorTimer;
  Position? lastPosition;
  DateTime? lastPositionTime;
  double totalDistance = 0;
  bool isMoving = true;
  int stationaryCount = 0;
  DateTime?
      firstStationaryAt; // Timestamp when current stationary streak began (for accurate auto-pause)
  DateTime sessionStartTime =
      DateTime.now(); // Will be overwritten when session starts
  bool isPaused = false;
  double calculatedSpeedKmh =
      0; // computed from deltas, never trust position.speed
  String? sessionStartDay; // YYYY-MM-DD for cross-day detection
  double? autoPauseAnchorLat; // lat where auto-pause occurred
  double? autoPauseAnchorLng; // lng where auto-pause occurred
  bool autoPauseNotified = false; // track if we sent auto-pause notification

  // Stationary spot detection (for nearby companies feature)
  double stationarySpotSeconds = 0;
  double? stationarySpotAnchorLat;
  double? stationarySpotAnchorLng;
  bool stationarySpotNotified = false;
  int movementCandidateCount = 0;
  int movementCandidateProgressCount = 0;
  DateTime? movementCandidateStartedAt;
  double movementCandidateLastAnchorDistance = 0;

  // Background Notification Scheduler State
  Timer? backgroundNotifTimer;
  double lastDistanceNotifiedKm = 0;
  DateTime lastTimeNotification = DateTime.now();
  Map<String, dynamic>? notifSettingsMap;

  // Initialize Local Notifications for Background Use
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  late SharedPreferences prefs;
  Future<void> Function()? startLocationUpdatesRef;

  void resetMovementCandidate() {
    movementCandidateCount = 0;
    movementCandidateProgressCount = 0;
    movementCandidateStartedAt = null;
    movementCandidateLastAnchorDistance = 0;
  }

  Future<void> stopLocationUpdates({bool notifyState = true}) async {
    positionSubscription?.cancel();
    positionSubscription = null;
    stationaryHeartbeatTimer?.cancel();
    stationaryHeartbeatTimer = null;
    backgroundNotifTimer?.cancel();
    backgroundNotifTimer = null;

    // Persist state
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);

    if (notifyState) {
      try {
        service.invoke('trackingStateChanged', {'isTracking': false});
      } catch (e) {
        logger.e('Failed to invoke trackingStateChanged: $e');
      }
    }
    logger.i('Location updates stopped');
  }

  Future<void> resumeActiveTracking({String reason = 'manual'}) async {
    if (!isPaused && positionSubscription != null) {
      logger.i('Resume ignored; tracking is already active');
      return;
    }
    final now = DateTime.now();
    pausedResumeMonitorTimer?.cancel();
    pausedResumeMonitorTimer = null;
    isPaused = false;
    stationaryCount = 0;
    firstStationaryAt = null;
    autoPauseAnchorLat = null;
    autoPauseAnchorLng = null;
    autoPauseNotified = false;
    resetMovementCandidate();
    await prefs.setBool(TrackingService._keyIsPaused, false);
    await prefs.remove(TrackingService._keyAutoPauseAt);

    // Re-anchor at current position so distance travelled during pause is not counted.
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      lastPosition = p;
      lastPositionTime = now;
      await prefs.setDouble(TrackingService._keyLastLat, p.latitude);
      await prefs.setDouble(TrackingService._keyLastLon, p.longitude);
    } catch (e) {
      logger.w('Could not re-anchor on resume: $e');
      lastPosition = null;
      lastPositionTime = null;
    }

    final starter = startLocationUpdatesRef;
    if (starter != null) {
      await starter();
    } else {
      logger.w('Resume requested before location starter was ready');
    }

    if (service is AndroidServiceInstance) {
      try {
        service.setForegroundNotificationInfo(
          title: 'Tracking Active - Resumed',
          content:
              'Continuing from ${(totalDistance / 1000).toStringAsFixed(2)} km',
        );
      } catch (e) {
        logger.e('Failed to update notification: $e');
      }
    }

    logger.i('Session resumed by $reason: $currentSessionId');
  }

  void startPausedResumeMonitor() {
    pausedResumeMonitorTimer?.cancel();
    pausedResumeMonitorTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!isPaused || currentSessionId == null) return;
      if (autoPauseAnchorLat == null || autoPauseAnchorLng == null) return;

      try {
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        if (p.accuracy > AppConstants.maxAccuracyThreshold) return;

        final movedM = Geolocator.distanceBetween(
          autoPauseAnchorLat!,
          autoPauseAnchorLng!,
          p.latitude,
          p.longitude,
        );

        if (movedM >= 100.0) {
          service.invoke('autoResumed', {
            'resumedAt': DateTime.now().millisecondsSinceEpoch,
            'distanceFromAnchor': movedM,
          });
          await resumeActiveTracking(reason: 'movement');
        }
      } catch (e) {
        logger.w('Paused movement monitor failed: $e');
      }
    });
  }

  Future<void> enterPausedMode(Position anchor,
      {required String reason}) async {
    if (isPaused) return;
    final now = DateTime.now();
    logger.i('AUTO-PAUSE: $reason - pausing session');
    isPaused = true;
    isMoving = false;
    stationaryCount = 0;
    autoPauseAnchorLat = anchor.latitude;
    autoPauseAnchorLng = anchor.longitude;
    lastPosition = anchor;
    lastPositionTime = now;
    resetMovementCandidate();
    await prefs.setBool(TrackingService._keyIsPaused, true);
    await prefs.setDouble(TrackingService._keyPausedDistance, totalDistance);
    await prefs.setString(
        TrackingService._keyAutoPauseAt, now.toIso8601String());

    service.invoke('autoPaused', {
      'pausedAt': now.millisecondsSinceEpoch,
      'distanceAtPause': totalDistance,
      'anchorLat': anchor.latitude,
      'anchorLng': anchor.longitude,
    });

    if (!autoPauseNotified) {
      autoPauseNotified = true;
      try {
        await flutterLocalNotificationsPlugin.show(
          10001,
          'Session Auto-Paused',
          'No movement for 5 min. Tracking and active time are paused. Move 100m or tap Resume.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'benzmobitraq_auto_pause',
              'Auto-Pause Notifications',
              channelDescription:
                  'Notifications when session auto-pauses after inactivity',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      } catch (e) {
        logger.e('Failed to show auto-pause notification: $e');
      }
    }

    if (service is AndroidServiceInstance) {
      try {
        service.setForegroundNotificationInfo(
          title: 'Session Paused',
          content:
              'Inactive. ${(totalDistance / 1000).toStringAsFixed(2)} km counted. Move 100m or tap Resume.',
        );
      } catch (e) {
        logger.e('Failed to update notification: $e');
      }
    }

    await stopLocationUpdates(notifyState: false);
    startPausedResumeMonitor();
  }

  try {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false);
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    logger.e('Failed to initialize background notifications: $e');
  }

  // Load persisted state
  prefs = await SharedPreferences.getInstance();
  totalDistance = prefs.getDouble(TrackingService._keyTotalDistance) ?? 0;
  final savedLastLat = prefs.getDouble(TrackingService._keyLastLat);
  final savedLastLon = prefs.getDouble(TrackingService._keyLastLon);
  final savedLastTimeMs = prefs.getInt(TrackingService._keyLastPositionTime);

  // CRITICAL FIX: Reconstruct lastPosition AND lastPositionTime from saved state.
  // Without this, after an OS-kill + restart the first location update
  // is treated as "first ever" and the gap distance is lost because
  // timeSinceLastSec becomes 0, skipping the recovery distance calculation.
  if (savedLastLat != null && savedLastLon != null) {
    lastPositionTime = savedLastTimeMs != null
        ? DateTime.fromMillisecondsSinceEpoch(savedLastTimeMs)
        : DateTime.now().subtract(const Duration(seconds: 5));
    logger.i(
        'RECOVERY: Restoring last position from persisted state: $savedLastLat, $savedLastLon @ ${lastPositionTime!.toIso8601String()}');
  }

  // Load session start time for elapsed time calculation
  final startTimeMs = prefs.getInt(TrackingService._keySessionStartTime);
  if (startTimeMs != null) {
    sessionStartTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
  }

  // Load pause state for cross-session survival
  isPaused = prefs.getBool(TrackingService._keyIsPaused) ?? false;
  sessionStartDay = prefs.getString(TrackingService._keySessionDay);
  calculatedSpeedKmh = prefs.getDouble(TrackingService._keyLastSpeedKmh) ?? 0;

  // ============================================================
  // LOCATION TRACKING
  // ============================================================

  // Persisted anchor for gap recovery (set from prefs, cleared once used)
  double? recoveryLat = savedLastLat;
  double? recoveryLon = savedLastLon;

  void onPositionReceived(Position position, {bool forceRecord = false}) async {
    final now = DateTime.now();

    // ============================================================
    // CROSS-DAY DETECTION
    // Session continues past midnight - just note the transition
    // ============================================================
    final currentDay = now.toIso8601String().substring(0, 10);
    if (sessionStartDay != null && sessionStartDay != currentDay) {
      logger
          .i('CROSS-DAY: Session crossed from $sessionStartDay to $currentDay');
      // Update session day but keep everything running
      sessionStartDay = currentDay;
      await prefs.setString(TrackingService._keySessionDay, currentDay);
      // Notify main isolate of day change (handled as regular update)
    }

    // ============================================================
    // ANTI-JITTER FILTER
    // ============================================================

    // Reject low-accuracy readings
    if (position.accuracy > AppConstants.maxAccuracyThreshold) {
      logger.d('Rejected: accuracy ${position.accuracy}m > threshold');
      return;
    }

    double distanceDelta = 0;
    bool shouldRecord = true;
    double segmentSpeedKmh = 0;
    bool countsForDistance = false;
    double acceptedDistanceDeltaM = 0;

    if (lastPosition != null && lastPositionTime != null) {
      // Calculate distance
      distanceDelta = Geolocator.distanceBetween(
        lastPosition!.latitude,
        lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Calculate time delta
      final timeDeltaSec = now.difference(lastPositionTime!).inSeconds;

      // ============================================================
      // CALCULATED SPEED (never trust position.speed)
      // ============================================================
      if (timeDeltaSec > 0) {
        segmentSpeedKmh = (distanceDelta / timeDeltaSec) * 3.6;
      }

      // ============================================================
      // ANTI-TELEPORT FILTER (mode-aware from calculated speed)
      // ============================================================
      if (timeDeltaSec > 0) {
        // Determine speed limit from recent calculated speed
        // CRITICAL FIX: When calculatedSpeedKmh is 0 (after restart), use generous limit
        // to avoid rejecting legitimate movement. The limit tightens as we establish speed.
        double speedLimitKmh;
        if (calculatedSpeedKmh == 0) {
          // After restart: be generous until we establish movement pattern
          speedLimitKmh = 200.0; // Allow any realistic vehicle speed initially
        } else if (calculatedSpeedKmh < 15) {
          speedLimitKmh =
              40.0; // walking/bike: allow up to 40 km/h (was 12 - too strict!)
        } else if (calculatedSpeedKmh < 70) {
          speedLimitKmh = 100.0; // cycling/scooter: allow up to 100 km/h
        } else if (calculatedSpeedKmh < 130) {
          speedLimitKmh = 160.0; // city driving: allow up to 160 km/h
        } else {
          speedLimitKmh = 250.0; // highway: allow up to 250 km/h
        }

        if (segmentSpeedKmh > speedLimitKmh) {
          logger.d(
              'Rejected: teleport detected (${segmentSpeedKmh.toStringAsFixed(1)} km/h > limit ${speedLimitKmh.toStringAsFixed(0)})');
          // Update anchor so we don't accumulate a massive delta after teleport resolves
          lastPosition = position;
          lastPositionTime = now;
          return;
        }
      }

      // ============================================================
      // TIME GATE (prevent burst sampling)
      // Only reject if the time between points is too short.
      // We no longer gate on distance because slow-moving vehicles
      // (bikes, city traffic) were losing legitimate distance.
      // ============================================================
      if (timeDeltaSec < AppConstants.minTimeBetweenUpdates && !forceRecord) {
        logger.d(
            'Rejected: too soon (${timeDeltaSec}s < ${AppConstants.minTimeBetweenUpdates}s)');
        return;
      }

      // ============================================================
      // ACCURACY-WEIGHTED JITTER FILTER
      // Uses max(worst_accuracy * 2.5, 20m) per DistanceEngine spec
      // ============================================================
      final lastAccuracy =
          lastPosition!.accuracy >= 0 ? lastPosition!.accuracy : 50.0;
      final maxAccuracy =
          position.accuracy > lastAccuracy ? position.accuracy : lastAccuracy;
      final jitterThreshold = (maxAccuracy * 2.5).clamp(20.0, 100.0);

      // Adaptive threshold based on inferred mode - BALANCED for production
      final modeThreshold = calculatedSpeedKmh > 100
          ? 80.0 // Highway: allow up to 80m
          : calculatedSpeedKmh > 40
              ? 40.0 // Car: allow up to 40m
              : 25.0; // Walking/bike: 25m (reduced from 50m for better accuracy)

      final distanceThreshold =
          jitterThreshold > modeThreshold ? jitterThreshold : modeThreshold;

      // ============================================================
      // ANTI-DRIFT: When already stationary, require moderate movement
      // to break out. Prevents GPS jitter (5-15m jumps) while allowing
      // real movement to be detected quickly.
      // ============================================================
      final bool alreadyStationary = stationaryCount >= 3;
      final effectiveThreshold = alreadyStationary
          ? (distanceThreshold > 30.0
              ? distanceThreshold
              : 30.0) // Reduced from 150m to 30m for production
          : distanceThreshold;
      final wasStationary =
          alreadyStationary || firstStationaryAt != null || !isMoving;

      if (distanceDelta < effectiveThreshold) {
        stationaryCount++;
        resetMovementCandidate();
        // Mark when this stationary streak started for accurate time-based auto-pause
        firstStationaryAt ??= now;

        // After several stationary readings, mark as not moving
        if (stationaryCount >= 3) {
          isMoving = false;

          // Still send occasional update for "still here" confirmation
          if (stationaryCount % 10 != 0) {
            shouldRecord = false;
          }
        }

        // ============================================================
        // STATIONARY SPOT DETECTION (for nearby companies feature)
        // Accumulate stationary time; trigger after 2 min at same spot
        // ============================================================
        final isAccurate =
            position.accuracy <= AppConstants.stationarySpotMaxAccuracy;
        final isSlow =
            segmentSpeedKmh <= (AppConstants.stationarySpotSpeedMps * 3.6);
        if (stationarySpotAnchorLat == null ||
            stationarySpotAnchorLng == null) {
          stationarySpotAnchorLat = position.latitude;
          stationarySpotAnchorLng = position.longitude;
        }
        final distanceFromSpotAnchor = Geolocator.distanceBetween(
          stationarySpotAnchorLat!,
          stationarySpotAnchorLng!,
          position.latitude,
          position.longitude,
        );
        final isClose =
            distanceFromSpotAnchor <= AppConstants.stationarySpotDistanceM;

        if (isAccurate && isSlow && isClose && !isPaused) {
          stationarySpotSeconds += timeDeltaSec;
        } else {
          stationarySpotSeconds = 0;
          stationarySpotAnchorLat = position.latitude;
          stationarySpotAnchorLng = position.longitude;
          stationarySpotNotified = false;
        }

        if (stationarySpotSeconds >= AppConstants.stationarySpotThresholdSec &&
            !stationarySpotNotified) {
          stationarySpotNotified = true;
          logger.i(
              'STATIONARY SPOT: ${stationarySpotSeconds.toStringAsFixed(0)}s at same spot - notifying main isolate');

          service.invoke('stationarySpotDetected', {
            'lat': position.latitude,
            'lng': position.longitude,
            'accuracy': position.accuracy,
            'durationSec': stationarySpotSeconds.round(),
            'timestamp': now.millisecondsSinceEpoch,
          });

          // Show notification prompting user to check nearby companies
          try {
            await flutterLocalNotificationsPlugin.show(
              AppConstants.stationarySpotNotificationId,
              'Stopped near factories?',
              'You have been stationary for 2 min. Tap to see nearby companies & products to pitch.',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'benzmobitraq_stationary_spot',
                  'Stationary Spot Suggestions',
                  channelDescription:
                      'Notifications when stationary near potential client sites',
                  importance: Importance.high,
                  priority: Priority.high,
                  icon: '@mipmap/ic_launcher',
                  actions: <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      'dismiss_stationary',
                      'Dismiss',
                      cancelNotification: true,
                      showsUserInterface: false,
                    ),
                  ],
                ),
              ),
              payload:
                  'stationary_spot|${position.latitude}|${position.longitude}',
            );
          } catch (e) {
            logger.e('Failed to show stationary spot notification: $e');
          }
        }
        // DO NOT update lastPosition - let distance build from anchor
      } else {
        final requiresConfirmation =
            wasStationary || movementCandidateCount > 0;
        bool didCommit = false;

        if (requiresConfirmation) {
          movementCandidateStartedAt ??= now;
          movementCandidateCount++;
          if (distanceDelta >= movementCandidateLastAnchorDistance + 8.0) {
            movementCandidateProgressCount++;
          }
          movementCandidateLastAnchorDistance = distanceDelta;

          final candidateElapsedSec =
              now.difference(movementCandidateStartedAt!).inSeconds;
          final candidateSpeedMps = candidateElapsedSec > 0
              ? distanceDelta / candidateElapsedSec
              : 0.0;
          final highQualityFix = position.accuracy <= 35.0;
          final confirmedMovement = distanceDelta >= 120.0 ||
              (highQualityFix &&
                  candidateElapsedSec >= 8 &&
                  distanceDelta >= 70.0 &&
                  movementCandidateCount >= 2 &&
                  movementCandidateProgressCount >= 1) ||
              (highQualityFix &&
                  candidateElapsedSec >= 12 &&
                  distanceDelta >= 50.0 &&
                  candidateSpeedMps >= 0.8 &&
                  movementCandidateCount >= 3 &&
                  movementCandidateProgressCount >= 2);

          if (!confirmedMovement) {
            shouldRecord = false;
            isMoving = false;
            logger.d(
              'Movement CANDIDATE ignored for distance: '
              '${distanceDelta.toStringAsFixed(1)}m from anchor, '
              'count=$movementCandidateCount, '
              'progress=$movementCandidateProgressCount, '
              'elapsed=${candidateElapsedSec}s, '
              'accuracy=${position.accuracy.toStringAsFixed(1)}m',
            );
          } else {
            logger.i(
              'Movement CONFIRMED from stationary anchor: '
              '${distanceDelta.toStringAsFixed(1)}m after '
              '${candidateElapsedSec}s',
            );
            resetMovementCandidate();
          }
        }

        if (shouldRecord &&
            isPaused &&
            autoPauseAnchorLat != null &&
            autoPauseAnchorLng != null) {
          final distanceFromPauseAnchor = Geolocator.distanceBetween(
            autoPauseAnchorLat!,
            autoPauseAnchorLng!,
            position.latitude,
            position.longitude,
          );
          if (distanceFromPauseAnchor > 100.0) {
            logger.i(
                'AUTO-RESUME: Movement detected ${distanceFromPauseAnchor.toStringAsFixed(0)}m from pause anchor - resuming session');
            isPaused = false;
            await prefs.setBool(TrackingService._keyIsPaused, false);
            await prefs.remove(TrackingService._keyAutoPauseAt);
            autoPauseAnchorLat = null;
            autoPauseAnchorLng = null;
            autoPauseNotified = false;

            service.invoke('autoResumed', {
              'resumedAt': now.millisecondsSinceEpoch,
              'distanceFromAnchor': distanceFromPauseAnchor,
            });
          }
        }

        if (!isPaused && shouldRecord && distanceDelta >= effectiveThreshold) {
          // Movement is confirmed; commit this segment as payable/session
          // distance. Raw stationary points can still exist, but they must not
          // contribute to distance rollups.
          totalDistance += distanceDelta;
          acceptedDistanceDeltaM = distanceDelta;
          countsForDistance = true;
          didCommit = true;
          stationaryCount = 0;
          isMoving = true;
          stationarySpotSeconds = 0;
          stationarySpotAnchorLat = null;
          stationarySpotAnchorLng = null;
          stationarySpotNotified = false;
          logger.d(
            'Distance ACCEPTED: +${distanceDelta.toStringAsFixed(1)}m, '
            'total=${totalDistance.toStringAsFixed(1)}m, '
            'threshold=${effectiveThreshold.toStringAsFixed(1)}m',
          );
        } else if (!isPaused && distanceDelta > 0 && shouldRecord) {
          logger.d(
              'Distance REJECTED (jitter/drift): ${distanceDelta.toStringAsFixed(1)}m < threshold ${effectiveThreshold.toStringAsFixed(1)}m, stationaryCount=$stationaryCount');
        }

        // Update calculated speed with EMA
        if (segmentSpeedKmh > 0) {
          calculatedSpeedKmh = calculatedSpeedKmh == 0
              ? segmentSpeedKmh
              : (calculatedSpeedKmh * 0.7 + segmentSpeedKmh * 0.3);
        }

        if (didCommit) {
          lastPosition = position;
          lastPositionTime = now;
          // Real movement confirmed - reset stationary timer
          firstStationaryAt = null;
        }
      }

      // ============================================================
      // AUTO-PAUSE DETECTION (TIME-BASED)
      // Uses real wall-clock time since first stationary reading.
      // ============================================================
      final stationaryDurationMin = firstStationaryAt != null
          ? now.difference(firstStationaryAt!).inMinutes
          : 0;
      if (stationaryDurationMin >= 5 && !isPaused) {
        await enterPausedMode(position,
            reason: '${stationaryDurationMin}min inactive detected');
        return;
      }
    } else {
      // ============================================================
      // FIRST POSITION (or after restart)
      // ============================================================
      if (recoveryLat != null && recoveryLon != null) {
        final recoveryDistance = Geolocator.distanceBetween(
          recoveryLat!,
          recoveryLon!,
          position.latitude,
          position.longitude,
        );
        final timeSinceLastMs = now.millisecondsSinceEpoch -
            (lastPositionTime?.millisecondsSinceEpoch ??
                now.millisecondsSinceEpoch);
        final timeSinceLastSec = timeSinceLastMs.abs() ~/ 1000;

        if (timeSinceLastSec > 0) {
          final recoverySpeedKmh = (recoveryDistance / timeSinceLastSec) * 3.6;

          // Time-bounded interpolation: accept up to 12h gap
          if (timeSinceLastSec <= 43200 && recoverySpeedKmh <= 200.0) {
            if (!isPaused) {
              totalDistance += recoveryDistance;
              acceptedDistanceDeltaM = recoveryDistance;
              countsForDistance = recoveryDistance > 0;
            }
            logger.i(
                'RECOVERY: Gap ${timeSinceLastSec}s, +${recoveryDistance.toStringAsFixed(1)}m @ ${recoverySpeedKmh.toStringAsFixed(1)} km/h');
          } else if (recoverySpeedKmh > 200.0) {
            // Interpolate at walking speed instead
            final gapHours = timeSinceLastSec / 3600.0;
            final interpolatedM = 5.0 * gapHours * 1000.0; // 5 km/h
            if (!isPaused) {
              totalDistance += interpolatedM;
              acceptedDistanceDeltaM = interpolatedM;
              countsForDistance = interpolatedM > 0;
            }
            logger.i(
                'RECOVERY: Interpolated ${interpolatedM.toStringAsFixed(1)}m for ${gapHours.toStringAsFixed(2)}h gap');
          } else {
            logger.w('RECOVERY: Rejected gap > 12h (${timeSinceLastSec}s)');
          }
        }

        recoveryLat = null;
        recoveryLon = null;
      }

      lastPosition = position;
      lastPositionTime = now;
    }

    // Persist for recovery (CRITICAL: lastPositionTime too!)
    if (lastPosition != null) {
      await prefs.setDouble(
          TrackingService._keyLastLat, lastPosition!.latitude);
      await prefs.setDouble(
          TrackingService._keyLastLon, lastPosition!.longitude);
    }
    if (lastPositionTime != null) {
      await prefs.setInt(TrackingService._keyLastPositionTime,
          lastPositionTime!.millisecondsSinceEpoch);
    }
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);
    await prefs.setDouble(TrackingService._keyLastSpeedKmh, calculatedSpeedKmh);

    // Persist rolling point buffer for chain-of-custody (last 20 points)
    _persistPointBufferTopLevel(prefs, {
      'lat': position.latitude,
      'lng': position.longitude,
      'acc': position.accuracy,
      'ts': now.millisecondsSinceEpoch,
      'moving': isMoving,
      'paused': isPaused,
    });

    if (!shouldRecord && !forceRecord) return;

    // ============================================================
    // SEND UPDATE TO MAIN ISOLATE
    // ============================================================
    logger.i(
        'RAW LOC: ${position.latitude}, ${position.longitude} | Acc: ${position.accuracy} | Paused: $isPaused');

    final update = LocationUpdate(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: calculatedSpeedKmh / 3.6, // Send calculated speed in m/s
      altitude: position.altitude,
      heading: position.heading,
      timestamp: now,
      sessionId: currentSessionId,
      totalDistance: totalDistance,
      isMoving: isMoving && !isPaused,
      countsForDistance: countsForDistance,
      distanceDeltaM: acceptedDistanceDeltaM,
    );

    try {
      service.invoke('locationUpdate', update.toMap());
    } catch (e) {
      logger.e('FAILED TO INVOKE locationUpdate: $e');
    }

    // Update notification
    if (service is AndroidServiceInstance) {
      final distanceKm = (totalDistance / 1000).toStringAsFixed(2);
      final status =
          isPaused ? 'On Break' : (isMoving ? 'Moving' : 'Stationary');

      final elapsed = DateTime.now().difference(sessionStartTime);
      final hours = elapsed.inHours;
      final minutes = elapsed.inMinutes % 60;
      final seconds = elapsed.inSeconds % 60;
      final timeStr =
          '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      try {
        service.setForegroundNotificationInfo(
          title: isPaused ? 'Session Paused' : 'Tracking Active - $status',
          content: isPaused
              ? 'On break • $distanceKm km • $timeStr elapsed'
              : '$timeStr elapsed • $distanceKm km',
        );
      } catch (e) {
        logger.e('Failed to update notification: $e');
      }
    }

    logger.i(
        'DIAGNOSTIC: Location generated: ${position.latitude}, ${position.longitude}. Acc: ${position.accuracy}. Paused: $isPaused');
  }

  Future<void> startLocationUpdates() async {
    positionSubscription?.cancel();

    // CRITICAL FIX: Use smaller distance filter for more frequent updates
    // distance filter is configured inline below in LocationSettings

    // CRITICAL FIX: Use bestForNavigation for highest accuracy
    // NOTE: Removed timeLimit as it causes TimeoutException on real devices
    // when GPS takes time to get initial fix (especially indoors)
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy
            .bestForNavigation, // Highest accuracy for navigation/tracking
        distanceFilter: 5, // Lowered from 10: captures early-session movement sooner
      ),
    ).listen(
      (p) => onPositionReceived(p, forceRecord: false),
      onError: (error) {
        logger.e('Location stream error: $error');
        service.invoke('error', {'message': 'Location error: $error'});
      },
      cancelOnError: false,
    );

    // Stationary heartbeat: force a point even when the device doesn't move.
    // REDUCED from 120s → 60s to minimize map gaps when OS throttles GPS stream.
    // This is required for strict "5 minutes within radius" stop detection
    // AND to ensure route continuity on the admin map.
    // FIX: 20s heartbeat (was 60s). Combined with the force-record initial
    // anchor, this guarantees a fast-stopped session captures at least 2
    // points and a non-zero distance. Also keeps the route on the admin
    // map dense enough during long stationary periods.
    stationaryHeartbeatTimer?.cancel();
    stationaryHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) async {
        if (currentSessionId == null) return;
        try {
          final p = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          onPositionReceived(p, forceRecord: true);
        } catch (e) {
          logger.w('Stationary heartbeat location failed: $e');
        }
      },
    );

    // ============================================================
    // BACKGROUND NOTIFICATION SCHEDULER
    // ============================================================
    // Replaces the frontend NotificationScheduler so it works when app is killed
    backgroundNotifTimer?.cancel();

    // Refresh settings
    final jsonStr = prefs.getString(AppConstants.keyNotificationSettings);
    if (jsonStr != null) {
      try {
        notifSettingsMap = jsonDecode(jsonStr);
      } catch (e) {
        logger.w('Failed to parse notification settings: $e');
      }
    }

    if (notifSettingsMap != null) {
      final double targetDistanceKm =
          (notifSettingsMap?['distanceKm'] as num?)?.toDouble() ?? 1.0;
      final int targetTimeMinutes =
          (notifSettingsMap?['timeMinutes'] as int?) ?? 10;

      backgroundNotifTimer =
          Timer.periodic(const Duration(seconds: 30), (_) async {
        if (currentSessionId == null) return;

        final now = DateTime.now();
        final currentDistanceKm = totalDistance / 1000.0;

        bool showDistance = false;
        bool showTime = false;

        // Check distance
        if (currentDistanceKm - lastDistanceNotifiedKm >= targetDistanceKm) {
          showDistance = true;
          lastDistanceNotifiedKm = currentDistanceKm;
        }

        // Check time
        if (now.difference(lastTimeNotification).inMinutes >=
            targetTimeMinutes) {
          showTime = true;
          lastTimeNotification = now;
        }

        if (showDistance || showTime) {
          final elapsed = now.difference(sessionStartTime);
          final hours = elapsed.inHours;
          final minutes = elapsed.inMinutes % 60;

          try {
            const AndroidNotificationDetails androidPlatformChannelSpecifics =
                AndroidNotificationDetails(
              'benzmobitraq_updates',
              'Session Updates',
              channelDescription: 'Time and distance updates',
              importance: Importance.high,
              priority: Priority.high,
            );
            const NotificationDetails platformChannelSpecifics =
                NotificationDetails(android: androidPlatformChannelSpecifics);

            if (showDistance) {
              await flutterLocalNotificationsPlugin.show(
                DateTime.now().millisecond + 100,
                '📍 Distance Update',
                'You\'ve traveled ${currentDistanceKm.toStringAsFixed(2)} km in ${hours}h ${minutes}m',
                platformChannelSpecifics,
              );
            }
            if (showTime) {
              await flutterLocalNotificationsPlugin.show(
                DateTime.now().millisecond + 200,
                '⏱️ Time Update',
                'Session running for ${hours}h ${minutes}m',
                platformChannelSpecifics,
              );
            }
          } catch (e) {
            logger.e('Background notification failed: $e');
          }
        }
      });
    }

    try {
      service.invoke('trackingStateChanged', {'isTracking': true});
    } catch (e) {
      logger.e('Failed to invoke trackingStateChanged: $e');
    }
    logger.i(
        'Location updates started (10m filter, high accuracy, 60s heartbeat)');
  }

  startLocationUpdatesRef = startLocationUpdates;

  // ============================================================
  // COMMAND HANDLERS
  // ============================================================

  service.on('startSession').listen((event) async {
    currentSessionId = event?['sessionId'] as String?;
    final isResume = event?['isResume'] as bool? ?? false;

    logger.i('Session started: $currentSessionId (Resuming: $isResume)');

    if (!isResume) {
      // Only reset for new sessions
      lastDistanceNotifiedKm = 0;
      lastTimeNotification = DateTime.now();
      totalDistance = 0;
      lastPosition = null;
      stationaryCount = 0;
      isPaused = false;
      calculatedSpeedKmh = 0;
      stationarySpotSeconds = 0;
      stationarySpotAnchorLat = null;
      stationarySpotAnchorLng = null;
      stationarySpotNotified = false;
      pausedResumeMonitorTimer?.cancel();
      pausedResumeMonitorTimer = null;
      resetMovementCandidate();
      sessionStartTime = DateTime.now();
      sessionStartDay = sessionStartTime.toIso8601String().substring(0, 10);

      // Persist start time and day
      await prefs.setInt(TrackingService._keySessionStartTime,
          sessionStartTime.millisecondsSinceEpoch);
      await prefs.setString(TrackingService._keySessionDay, sessionStartDay!);
      await prefs.setBool(TrackingService._keyIsPaused, false);
      await prefs.remove(TrackingService._keyPausedDistance);
      await prefs.remove(TrackingService._keyAutoPauseAt);
    } else {
      // For resume, load persisted state
      if (totalDistance == 0) {
        totalDistance = prefs.getDouble(TrackingService._keyTotalDistance) ?? 0;
      }
      isPaused = prefs.getBool(TrackingService._keyIsPaused) ?? false;
      calculatedSpeedKmh =
          prefs.getDouble(TrackingService._keyLastSpeedKmh) ?? 0;
      sessionStartDay = prefs.getString(TrackingService._keySessionDay);
    }

    if (isPaused) {
      autoPauseAnchorLat ??= prefs.getDouble(TrackingService._keyLastLat);
      autoPauseAnchorLng ??= prefs.getDouble(TrackingService._keyLastLon);
      await stopLocationUpdates(notifyState: false);
      startPausedResumeMonitor();
      logger.i(
          'Session restored in paused mode; continuous tracking remains stopped');
    } else {
      await startLocationUpdates();

      // CRITICAL FIX: Force-record an initial position immediately so the
      // anchor (lastPosition) is set right away. Without this, the very
      // first GPS fix from the stream just becomes the anchor and zero
      // distance is recorded - leading to 'started, stopped quickly, 0 km'
      // bug for short sessions.
      if (!isResume) {
        unawaited(() async {
          try {
            final p = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.bestForNavigation,
            ).timeout(const Duration(seconds: 8));
            await prefs.setDouble(TrackingService._keyLastLat, p.latitude);
            await prefs.setDouble(TrackingService._keyLastLon, p.longitude);
            lastPosition = p;
            lastPositionTime = DateTime.now();
            logger.i(
                'INITIAL ANCHOR set: ${p.latitude}, ${p.longitude} (acc ${p.accuracy}m)');
            onPositionReceived(p, forceRecord: true);
          } catch (e) {
            logger.w('Could not capture initial anchor position: $e');
          }
        }());
      }
    }

    // Send ACK to main isolate
    service.invoke('sessionStarted', {'sessionId': currentSessionId});
  });

  service.on('pauseSession').listen((event) async {
    if (currentSessionId == null) {
      logger.w('pauseSession called but no active session, ignoring');
      return;
    }
    logger.i('Session paused: $currentSessionId');
    Position? anchor = lastPosition;
    if (anchor == null) {
      try {
        anchor = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        logger.w('Manual pause anchor lookup failed: $e');
      }
    }
    if (anchor != null) {
      await enterPausedMode(anchor, reason: 'manual pause');
    }
  });

  service.on('resumeSession').listen((event) async {
    if (currentSessionId == null) {
      logger.w('resumeSession called but no active session, ignoring');
      return;
    }
    await resumeActiveTracking(reason: 'manual');
  });

  service.on('stopSession').listen((event) async {
    // CRITICAL FIX: Only stop if we have an active session
    if (currentSessionId == null) {
      logger.w('stopSession called but no active session, ignoring');
      return;
    }

    logger.i('Session stopped: $currentSessionId');
    await stopLocationUpdates();
    pausedResumeMonitorTimer?.cancel();
    pausedResumeMonitorTimer = null;
    currentSessionId = null;
    // Clear stationary spot state
    stationarySpotSeconds = 0;
    stationarySpotAnchorLat = null;
    stationarySpotAnchorLng = null;
    stationarySpotNotified = false;
    resetMovementCandidate();
  });

  service.on('stopService').listen((event) async {
    logger.i('Service stop requested');
    await stopLocationUpdates();
    service.stopSelf();
  });

  // SIGNAL READY TO MAIN ISOLATE
  // This prevents the race condition where Main sends startSession before we are listening
  service.invoke('serviceReady');
  logger.i('DIAGNOSTIC: Background Service Ready & Listening');
}

/// Top-level helper to persist a rolling point buffer to SharedPreferences
/// Used inside the background isolate for chain-of-custody.
@pragma('vm:entry-point')
Future<void> _persistPointBufferTopLevel(
    SharedPreferences prefs, Map<String, dynamic> point) async {
  try {
    const bufferKey = 'tracking_point_buffer';
    final existing = prefs.getStringList(bufferKey) ?? [];
    final jsonStr = jsonEncode(point);
    final updated = [...existing, jsonStr];
    final trimmed =
        updated.length > 30 ? updated.sublist(updated.length - 30) : updated;
    await prefs.setStringList(bufferKey, trimmed);
  } catch (e) {
    // Logger is not available in top-level; silently ignore
  }
}

/// iOS background mode handler
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

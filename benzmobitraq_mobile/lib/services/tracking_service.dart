import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:benzmobitraq_mobile/core/constants/app_constants.dart';
import 'package:benzmobitraq_mobile/core/kalman_position_filter.dart';

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

/// Tiny holder for the cluster-stationary detector's ring buffer.
class _FixCoord {
  final double lat;
  final double lng;
  const _FixCoord(this.lat, this.lng);
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
  static bool _listenersAttached = false;

  // Callbacks for the main isolate
  static Function(LocationUpdate)? onLocationUpdate;
  static Function(String)? onError;
  static Function(bool)? onTrackingStateChanged;
  static Function(Map<String, dynamic>)? onAutoPaused;
  static Function(Map<String, dynamic>)? onAutoResumed;
  static Function(Map<String, dynamic>)? onStationarySpotDetected;

  /// Fires whenever the BG isolate observes a change in location-services
  /// state. The payload is `{enabled: bool}`. The main isolate uses this
  /// to immediately clear the "Location is OFF" banner (and the GPS-stalled
  /// watchdog grace window) the moment the user turns location back on.
  static Function(bool)? onServiceStatusChanged;

  /// Fires when the bg isolate has detected the user has been stationary
  /// during an active session for >= 10 minutes. Payload:
  ///   { durationMin: int, lat: double, lng: double, at: ms-epoch }
  /// Main isolate shows the alarm dialog + plays the alarm sound.
  static Function(Map<String, dynamic>)? onStationaryAlarm;

  /// Fires when the bg isolate has auto-resumed tracking because the
  /// user started moving (>= 100 m, >= 5 km/h) during a paused
  /// session. Payload: { movedM: double, speedKmh: double, lat, lng,
  /// at }. Main isolate shows a confirmation dialog with Stop /
  /// Continue Tracking buttons — the resume has already happened, so
  /// the dialog is informational, not gating.
  static Function(Map<String, dynamic>)? onMovementAutoResumed;

  /// Fired by BG isolate after a resume; main isolate should silence
  /// the watchdog for the supplied number of seconds so a freshly
  /// re-subscribed position stream isn't penalised as a stall.
  static Function(Map<String, dynamic>)? onWatchdogGrace;

  /// Fires when the bg isolate sees a large gap between two
  /// consecutive GPS fixes (>= 60 seconds + >= 200 m straight-line).
  /// Payload: { fromLat, fromLng, toLat, toLng, haversineM, gapSec }.
  /// Main isolate calls Google Maps Directions for the real driving
  /// distance and adds (mapsKm - haversineKm) to the session total
  /// so the user is not under-counted for a tunnel / location-off
  /// stretch.
  static Function(Map<String, dynamic>)? onMapsGapRecovery;

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
    // Guard: prevent duplicate stream subscriptions when initialize()
    // is called multiple times (e.g. hot restart, app resume).
    // Without this, each call creates NEW listeners on the same events,
    // causing _onLocationUpdate to fire 2x, 3x, 4x per GPS fix.
    if (_listenersAttached) return;
    _listenersAttached = true;

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

    _service.on('serviceStatus').listen((event) {
      if (event != null) {
        onServiceStatusChanged?.call(event['enabled'] as bool? ?? true);
      }
    });

    _service.on('stationaryAlarm').listen((event) {
      if (event != null) {
        onStationaryAlarm?.call(Map<String, dynamic>.from(event));
      }
    });

    _service.on('movementAutoResumed').listen((event) {
      if (event != null) {
        onMovementAutoResumed?.call(Map<String, dynamic>.from(event));
      }
    });

    _service.on('mapsGapRecovery').listen((event) {
      if (event != null) {
        onMapsGapRecovery?.call(Map<String, dynamic>.from(event));
      }
    });

    // BG isolate is signalling that the watchdog should give the
    // freshly-resubscribed position stream a grace period before
    // crying "GPS stalled" or "Distance not counting". Fired on every
    // manual resume and every auto-resume.
    _service.on('watchdogGrace').listen((event) {
      if (event != null) {
        onWatchdogGrace?.call(Map<String, dynamic>.from(event));
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

      // Start the background service if not running.
      // CRITICAL: A previous Work Done → Present sequence may have
      // sent stopService just milliseconds ago. The bg-isolate's
      // `service.stopSelf()` is asynchronous — `isRunning()` can
      // briefly return TRUE while the isolate is winding down, in
      // which case we'd skip startService and then send startSession
      // commands into a dying isolate that's no longer listening.
      // That's the "session 3 has 0 km because GPS never started"
      // bug after a fast Work Done → Present.
      //
      // Defense: if the service claims it's running, wait one beat
      // and re-check. If a teardown completes in that window, we
      // start it ourselves.
      bool running = await _service.isRunning();
      if (running && !isResume) {
        // Only enforce the settle-wait on FRESH session starts. On
        // isResume we trust the existing running service.
        await Future.delayed(const Duration(milliseconds: 250));
        running = await _service.isRunning();
      }
      if (!running) {
        await _service.startService();
        // Give the new isolate a moment to register its 'startSession'
        // listener BEFORE we start invoking it — saves an unnecessary
        // ACK retry round trip.
        await Future.delayed(const Duration(milliseconds: 350));
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
      // CRITICAL: Reload from disk to pick up background isolate's latest writes
      await prefs.reload();
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

      // Stop the session in the bg isolate first (clears its in-memory
      // state). Then stop the service itself if it's still running.
      _service.invoke('stopSession');

      // Give the bg isolate a moment to process stopSession + clear
      // its variables before we yank the service out from under it.
      // Without this pause, a fast Work Done → Present can race and
      // leave half-cleared state, which is what causes the next
      // session to not record any distance.
      await Future.delayed(const Duration(milliseconds: 250));

      final isRunning = await _service.isRunning();
      if (isRunning) {
        _service.invoke('stopService');
        // Brief wait for the service to actually wind down. Required
        // so the subsequent `isRunning()` check inside startTracking
        // returns the truth, not the in-flight state.
        await Future.delayed(const Duration(milliseconds: 400));
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
      await prefs.reload();
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
      await prefs.reload();
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

  /// True once the 30-minute stationary alarm has been emitted for the
  /// current stationary streak. Reset to false the moment the user
  /// resumes movement (firstStationaryAt is cleared elsewhere when
  /// movement is confirmed) so the alarm can fire again on the next
  /// stationary streak.
  bool stationaryAlarmFired = false;

  /// True once the 30-minute "paused too long" alarm has been emitted
  /// for the current manual-pause. Reset to false when the user
  /// resumes or stops the session. This alarm fires from the BG
  /// isolate so it works even when the app is killed (the original
  /// pause-expired Dart Timer in SessionManager only worked when the
  /// main isolate was alive — that was the bug).
  bool pausedAlarmFired = false;

  /// Consecutive GPS fixes (while paused) showing ≥6 km/h driving.
  /// Used together with distance-from-pause-anchor to confirm the user
  /// has actually resumed driving rather than walking out of a parking
  /// lot or GPS drifting. Reset whenever we leave paused mode OR when
  /// a single fix breaks the streak.
  int autoResumeFastFixHits = 0;
  const int autoResumeFastFixThreshold = 3;
  const double autoResumeSpeedKmh = 6.0;
  const double autoResumeDistanceM = 100.0;

  // ============================================================
  // CLUSTER-BASED STATIONARY DETECTOR
  // ============================================================
  //
  // The single most reliable stationary-detection signal: track the
  // last N GPS fixes' coordinates. Compute their centroid. If the
  // MAX distance from any fix to the centroid is < clusterRadiusM,
  // the rep hasn't actually moved — every coordinate is just GPS
  // jitter oscillating around one true position.
  //
  // Works regardless of what the GPS chip reports for speed (which
  // is unreliable when stationary — Android can hallucinate 1-5 km/h
  // from coordinate jitter). Works regardless of EMA-smoothed speed
  // (which is sticky after a real drive ends). Pure geometry.
  //
  // Tuned for: phone on desk with mediocre indoor GPS lock should
  // produce 5-15m amplitude jitter, well below the 35m clusterRadius.
  // A user walking 5 km/h covers 7m/sec → 7 fixes at 5s interval =
  // 245m displacement, easily breaks the cluster.
  final List<_FixCoord> _recentFixes = [];
  const int clusterWindowSize = 12;
  const double clusterRadiusM = 35.0;
  const int clusterMinFixesToDecide = 6;

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
    stationaryAlarmFired = false;
    pausedAlarmFired = false;
    autoResumeFastFixHits = 0;
    autoPauseAnchorLat = null;
    autoPauseAnchorLng = null;
    autoPauseNotified = false;
    _recentFixes.clear();
    resetMovementCandidate();
    await prefs.setBool(TrackingService._keyIsPaused, false);
    await prefs.remove(TrackingService._keyAutoPauseAt);
    // Dismiss any pending pause alarm UI now that we're resuming.
    try {
      await flutterLocalNotificationsPlugin.cancel(90201);
    } catch (_) {}
    // Tell the main isolate to suppress watchdog "GPS stalled" alerts
    // for the next 90 seconds — the freshly-resubscribed position
    // stream needs a moment to deliver its first fix after resume.
    try {
      service.invoke('watchdogGrace', {
        'durationSec': 90,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}

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

        // Auto-resume rule (per product decision):
        //   - movement >= 100m from the pause anchor, AND
        //   - segment speed >= 5 km/h
        // When both hold, we IMMEDIATELY resume the session (no dialog
        // gate) and then send a `movement_auto_resumed` event so the
        // main isolate can show a non-blocking alert with Stop /
        // Continue Tracking buttons. The user is never silently
        // resumed-and-not-told.
        // Speed = max(reported position.speed, computed-from-anchor).
        final reportedSpeedKmh =
            (p.speed.isFinite && p.speed > 0) ? p.speed * 3.6 : 0.0;
        // We do NOT have a reliable elapsed-time from the pause
        // anchor here, so use the reported speed alone for the
        // threshold check. movedM still has to clear 100m to qualify.
        if (movedM >= 100.0 && reportedSpeedKmh >= 5.0) {
          logger.i(
              'PAUSE-MOVE: auto-resuming after ${movedM.toStringAsFixed(0)}m '
              'at ${reportedSpeedKmh.toStringAsFixed(1)} km/h');

          // Tell the main isolate the auto-resume happened and let it
          // show the screen alert + the foreground notification.
          try {
            service.invoke('movementAutoResumed', {
              'movedM': movedM,
              'speedKmh': reportedSpeedKmh,
              'lat': p.latitude,
              'lng': p.longitude,
              'at': DateTime.now().millisecondsSinceEpoch,
            });
          } catch (_) {}
          // Legacy event consumers (older bloc handlers) still get fed.
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
    pausedAlarmFired = false; // fresh pause → re-arm the 30-min alarm
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

    // (The legacy "Session Auto-Paused. No movement for 30 min."
    // notification used to fire here. It was misleading on a manual
    // pause and was the root cause of the "I got a 30-min message
    // when I asked for 2 minutes" report. The new pause-countdown
    // notification — set up by the main isolate's pauseSession —
    // replaces it with a live "Pause: 1m 45s remaining" timer.)
    autoPauseNotified = true;

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

    // IMPORTANT: do NOT call stopLocationUpdates() here.
    // We need the position stream to keep flowing while paused so the
    // in-handler auto-resume path (onPositionReceived → distanceFromPauseAnchor
    // check) can fire the moment the rep starts moving. Distance
    // accumulation is already guarded by `if (!isPaused)` further down,
    // so leaving the stream alive does NOT inflate the session km.
    // The 30-second `startPausedResumeMonitor` polling is kept as a
    // belt-and-suspenders backup for the rare case where the stream
    // is throttled by the OS while the screen is off.
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
  // SELF-RECOVERY: AUTO-RESUME AFTER OS KILL
  // ============================================================
  // When Android kills the app process (swipe from recents, low memory),
  // the service restarts because stopWithTask=false. But the main isolate
  // is dead, so no one sends 'startSession'. We detect this situation
  // and resume tracking automatically from persisted state.
  //
  // Without this fix, tracking silently stops for up to 15 minutes
  // (until WorkManager watchdog fires).
  final recoveredSessionId = prefs.getString(TrackingService._keySessionId);
  final wasTracking = prefs.getBool(TrackingService._keyIsTracking) ?? false;

  // We use this flag to decide later whether to show a "Tracking
  // Resumed" notification. The notification ONLY makes sense if the
  // OS killed us — NOT if the main isolate just kicked us off as part
  // of a fresh user-initiated Present tap. That's why we DEFER the
  // notification: if a 'startSession' command arrives within a few
  // seconds we cancel it, because that proves the main isolate is
  // alive and intentionally driving the start.
  bool deferredRecoveryNotificationCancelled = false;
  if (wasTracking && recoveredSessionId != null) {
    logger.i(
        'SERVICE SELF-RECOVERY: Detected killed session $recoveredSessionId, auto-resuming...');
    currentSessionId = recoveredSessionId;

    // Schedule the recovery notification for ~6 seconds later. Plenty
    // of time for an in-flight `service.invoke('startSession', ...)`
    // from the main isolate to arrive and toggle the cancel flag.
    Timer(const Duration(seconds: 6), () async {
      if (deferredRecoveryNotificationCancelled) {
        logger.i(
            'SERVICE SELF-RECOVERY: notification suppressed (main isolate present)');
        return;
      }
      try {
        await flutterLocalNotificationsPlugin.show(
          90002,
          'Tracking Resumed',
          'Tracking was interrupted and has been automatically resumed.',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'benzmobitraq_tracking_alerts',
              'Tracking Alerts',
              channelDescription:
                  'Critical alerts when GPS or tracking is not working correctly',
              importance: Importance.max,
              priority: Priority.max,
              icon: '@mipmap/ic_launcher',
              enableVibration: true,
              vibrationPattern:
                  Int64List.fromList([0, 200, 150, 200, 150, 200]),
            ),
          ),
        );
      } catch (e) {
        logger.w('Failed to show recovery notification: $e');
      }
    });
  }

  // ============================================================
  // BACKGROUND GPS HEALTH MONITOR
  // ============================================================
  // Runs every 60 seconds in the background isolate. If GPS hasn't
  // produced a valid fix in 2+ minutes during an active, non-paused
  // session, it fires a local notification with 3x vibration.
  // This works even when the main isolate is dead (app killed).
  DateTime? lastSuccessfulGpsTime;
  Timer? backgroundHealthTimer;
  bool hasEmittedLocationUpdate = false;

  // Tracks the last time we forced a stream rebuild so we don't tight-loop
  // when satellites genuinely take a while to lock.
  DateTime? lastStreamRebuildAt;
  int consecutiveRebuilds = 0;

  backgroundHealthTimer =
      Timer.periodic(const Duration(seconds: 30), (_) async {
    if (currentSessionId == null) return;
    // Even while paused we keep the stream alive (auto-resume needs it);
    // the watchdog must still verify the stream is delivering fixes.

    final now = DateTime.now();
    final sinceLastGps = lastSuccessfulGpsTime == null
        ? 99999
        : now.difference(lastSuccessfulGpsTime!).inSeconds;

    // ---- Tier 1 (60s stale): silently rebuild the position stream. -----
    // This is the common case after a recents-swipe / doze: the
    // subscription is technically alive but the OS stopped pushing fixes
    // to it. Cancelling and re-subscribing kicks it.
    if (sinceLastGps >= 60) {
      final canRebuild = lastStreamRebuildAt == null ||
          now.difference(lastStreamRebuildAt!).inSeconds >= 30;
      if (canRebuild) {
        consecutiveRebuilds++;
        lastStreamRebuildAt = now;
        logger.w(
            'BG HEALTH: no GPS for ${sinceLastGps}s — forcing stream rebuild '
            '(consecutive=$consecutiveRebuilds)');
        try {
          await positionSubscription?.cancel();
        } catch (_) {}
        positionSubscription = null;
        try {
          await (startLocationUpdatesRef ?? () async {})();
          // Mark a fresh "last seen" stamp so the watchdog gives the new
          // subscription a grace window before considering another rebuild.
          lastSuccessfulGpsTime = DateTime.now();
        } catch (e) {
          logger.e('BG HEALTH: stream rebuild failed: $e');
        }
      }
    } else {
      // Healthy tick — reset the consecutive counter so the next stall
      // gets its first rebuild fast.
      consecutiveRebuilds = 0;
    }

    // ---- Tier 2 (120s stale AND 3+ failed rebuilds): notify user. -----
    // At this point the chip is genuinely dead or location services are
    // off — we've already tried to fix it three times in a row.
    if (sinceLastGps >= 120 && consecutiveRebuilds >= 3 && !isPaused) {
      try {
        await flutterLocalNotificationsPlugin.show(
          90001,
          '⚠️ GPS not responding',
          'Tracking has been trying to restart for '
              '${(sinceLastGps / 60).toStringAsFixed(0)} min. '
              'Check that location is on and the app is set Unrestricted in battery settings.',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'benzmobitraq_tracking_alerts',
              'Tracking Alerts',
              channelDescription:
                  'Critical alerts when GPS or tracking is not working correctly',
              importance: Importance.max,
              priority: Priority.max,
              icon: '@mipmap/ic_launcher',
              enableVibration: true,
              vibrationPattern:
                  Int64List.fromList([0, 200, 150, 200, 150, 200]),
            ),
          ),
        );
      } catch (e) {
        logger.w('BG HEALTH: Failed to show GPS alert: $e');
      }
    }
  });

  // ---- Tier 3: preventive periodic rebuild every 10 minutes. ----------
  // Even when fixes ARE coming in, Android's FusedLocationProvider
  // sometimes silently degrades quality during long sessions (the user's
  // "after 2 hours unattended tracking dies" symptom). A scheduled
  // re-subscribe forces a fresh underlying request, which clears any
  // accumulated throttling.
  Timer.periodic(const Duration(minutes: 10), (_) async {
    if (currentSessionId == null) return;
    logger.i('BG HEALTH: scheduled 10-min preventive stream rebuild');
    try {
      await positionSubscription?.cancel();
    } catch (_) {}
    positionSubscription = null;
    try {
      await (startLocationUpdatesRef ?? () async {})();
    } catch (e) {
      logger.w('Preventive stream rebuild failed: $e');
    }
  });

  // ============================================================
  // LOCATION TRACKING
  // ============================================================

  // Persisted anchor for gap recovery (set from prefs, cleared once used)
  double? recoveryLat = savedLastLat;
  double? recoveryLon = savedLastLon;

  // Kalman-style 2-D position smoother. Only kicks in for low-accuracy
  // fixes (>15m reported accuracy) so it doesn't degrade the pristine
  // fixes that already work well. Maintains its own state per BG-isolate
  // lifetime — reset on session start.
  final kalman = KalmanPositionFilter();

  void onPositionReceived(Position rawPosition,
      {bool forceRecord = false}) async {
    final now = DateTime.now();

    // Run the raw fix through the Kalman position filter before any
    // distance logic touches it. For high-accuracy fixes this is a
    // pass-through; for noisy fixes it blends with the running estimate
    // weighted by accuracy.
    final smoothed = kalman.process(
      latitude: rawPosition.latitude,
      longitude: rawPosition.longitude,
      accuracyMeters: rawPosition.accuracy,
      timestampMs: now.millisecondsSinceEpoch,
    );

    final Position position = smoothed.wasSmoothed
        ? Position(
            latitude: smoothed.latitude,
            longitude: smoothed.longitude,
            accuracy: smoothed.accuracyMeters,
            altitude: rawPosition.altitude,
            altitudeAccuracy: rawPosition.altitudeAccuracy,
            speed: rawPosition.speed,
            speedAccuracy: rawPosition.speedAccuracy,
            heading: rawPosition.heading,
            headingAccuracy: rawPosition.headingAccuracy,
            timestamp: rawPosition.timestamp,
            isMocked: rawPosition.isMocked,
          )
        : rawPosition;

    // Stamp GPS health monitor — any valid fix means GPS is alive
    lastSuccessfulGpsTime = now;

    // Persist to disk so the main-isolate watchdog can see freshness
    // even when the bg → main event channel is throttled (screen off).
    try {
      await prefs.setInt(
          'tracking_last_gps_fix_at', now.millisecondsSinceEpoch);
    } catch (_) {}

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
      // CLUSTER STATIONARY GATE — ZERO false positives on phone-on-desk.
      // ============================================================
      // Maintain a ring buffer of the last N coordinates. If ALL of
      // them fall within `clusterRadiusM` of their centroid, the rep
      // hasn't actually moved — every fix is just GPS jitter
      // oscillating around one real position.
      //
      // This runs FIRST because it's the most reliable signal we have.
      // It ignores the GPS chip's `speed` field (unreliable when
      // stationary), it ignores our EMA-smoothed `calculatedSpeedKmh`
      // (sticky after a real drive ends), and it ignores accuracy.
      // Pure geometry: did the coordinates move, or are they drifting
      // around one point?
      //
      // Also resets the EMA-smoothed speed to 0 the moment we detect
      // a cluster — kills the sticky-speed problem.
      _recentFixes.add(_FixCoord(position.latitude, position.longitude));
      while (_recentFixes.length > clusterWindowSize) {
        _recentFixes.removeAt(0);
      }
      bool clusterSaysStill = false;
      bool hardStationaryFix = false;
      double clusterMaxDistFromCentroid = 0;
      if (_recentFixes.length >= clusterMinFixesToDecide) {
        final n = _recentFixes.length;
        double sumLat = 0, sumLng = 0;
        for (final f in _recentFixes) {
          sumLat += f.lat;
          sumLng += f.lng;
        }
        final centroidLat = sumLat / n;
        final centroidLng = sumLng / n;
        for (final f in _recentFixes) {
          final d = Geolocator.distanceBetween(
              centroidLat, centroidLng, f.lat, f.lng);
          if (d > clusterMaxDistFromCentroid) {
            clusterMaxDistFromCentroid = d;
          }
        }
        clusterSaysStill = clusterMaxDistFromCentroid < clusterRadiusM;
      }
      if (clusterSaysStill) {
        logger.i(
            'CLUSTER-GATE: rejecting fix, ${_recentFixes.length} recent positions '
            'within ${clusterMaxDistFromCentroid.toStringAsFixed(1)}m of centroid '
            '(threshold ${clusterRadiusM.toStringAsFixed(0)}m) — user is stationary');
        // Kill the EMA stickiness so subsequent legitimate movement
        // doesn't have to fight a leftover speed memory.
        calculatedSpeedKmh = 0;
        stationaryCount++;
        firstStationaryAt ??= now;
        resetMovementCandidate();
        if (stationaryCount >= 3) {
          isMoving = false;
        }
        hardStationaryFix = true;
        shouldRecord = forceRecord || !hasEmittedLocationUpdate;
        lastPosition = position;
        lastPositionTime = now;
      }

      // ============================================================
      // SPEED STATIONARY GATE — covers the warmup window where the
      // cluster buffer isn't full yet.
      // ============================================================
      final reportedSpeedKmh = position.speed.isFinite && position.speed > 0
          ? position.speed * 3.6
          : 0.0;
      final smoothSpeedKmh = calculatedSpeedKmh;
      // Loosened from 1.5 → 3 km/h: Android FusedLocation can
      // hallucinate up to ~2-3 km/h "speed" from coordinate jitter
      // even when fully stationary. 3 km/h is still well below any
      // real driving / bike / brisk-walk pace.
      final speedSaysStill = reportedSpeedKmh < 3.0 && smoothSpeedKmh < 3.0;
      final allowForcedAnchorRecord =
          forceRecord && timeDeltaSec <= 2 && distanceDelta < 1.0;

      // ============================================================
      // ACCURACY-WEIGHTED JITTER FILTER
      // ============================================================
      //
      // The "right" threshold has to clear the LARGEST realistic GPS
      // jitter amplitude. Real-world measurement: a phone sitting on
      // a desk with a clear sky view drifts up to 12m between fixes.
      // Indoor / urban canyon drift can hit 20m. Bumping the floor
      // back to 15m kills phone-on-desk drift while still passing
      // slow-bike / pedestrian movement (which produces 15-25m
      // deltas per 5s tick).
      //
      // Tradeoff: someone walking very slowly (~3 km/h) produces ~4m
      // deltas per 5s tick — those get rejected. But walkers don't
      // file fuel-expense bills, so the loss is acceptable. Drivers
      // and bike riders, who DO bill, all clear the 15m floor easily.
      final lastAccuracy =
          lastPosition!.accuracy >= 0 ? lastPosition!.accuracy : 50.0;
      final maxAccuracy =
          position.accuracy > lastAccuracy ? position.accuracy : lastAccuracy;
      final jitterThreshold = (maxAccuracy * 1.5).clamp(15.0, 60.0);

      // Mode-adaptive on top of the jitter floor.
      final modeThreshold = calculatedSpeedKmh > 100
          ? 60.0 // Highway
          : calculatedSpeedKmh > 40
              ? 25.0 // Car in city
              : 15.0; // Slow / bike / walking — matches the jitter floor

      final distanceThreshold =
          jitterThreshold > modeThreshold ? jitterThreshold : modeThreshold;

      // When already stationary, raise the bar so GPS drift can't
      // fake departure from a stop.
      final bool alreadyStationary = stationaryCount >= 3;
      final effectiveThreshold = alreadyStationary
          ? (distanceThreshold > 25.0 ? distanceThreshold : 25.0)
          : distanceThreshold;
      final wasStationary =
          alreadyStationary || firstStationaryAt != null || !isMoving;

      // The hard stationary gate runs BEFORE the distance threshold
      // check so a 15m noise spike with reported speed = 0 is rejected
      // even though it would clear the threshold numerically.
      if (!hardStationaryFix && speedSaysStill && !allowForcedAnchorRecord) {
        logger.d(
            'STATIONARY-GATE: rejecting delta=${distanceDelta.toStringAsFixed(1)}m, '
            'reportedKmh=${reportedSpeedKmh.toStringAsFixed(1)}, '
            'smoothKmh=${smoothSpeedKmh.toStringAsFixed(1)}');
        stationaryCount++;
        firstStationaryAt ??= now;
        resetMovementCandidate();
        if (stationaryCount >= 3) {
          isMoving = false;
        }
        hardStationaryFix = true;
        shouldRecord = forceRecord || !hasEmittedLocationUpdate;
        lastPosition = position;
        lastPositionTime = now;
      }

      if (hardStationaryFix || distanceDelta < effectiveThreshold) {
        stationaryCount++;
        resetMovementCandidate();
        // Mark when this stationary streak started for accurate time-based auto-pause
        firstStationaryAt ??= now;

        // After several stationary readings, mark as not moving
        if (stationaryCount >= 3) {
          isMoving = false;

          // Still send occasional update for "still here" confirmation
          if (!hardStationaryFix && stationaryCount % 10 != 0) {
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
        // ====================================================================
        // GAP-RECOVERY FAST PATH
        //
        // When `forceRecord` is true AND the time gap is large (>= 30s),
        // this is a fix that was deliberately captured to recover from a
        // tracking interruption (e.g. user toggled location services off
        // and back on, screen woke from deep sleep, etc.). The standard
        // "movement candidate" gate is designed to reject GPS jitter while
        // stationary — it does NOT make sense here, because the user
        // genuinely was moving during the gap. Without this bypass, the
        // first restored fix gets rejected as "not enough confirmation"
        // and the entire gap distance (often 0.5–2 km) is silently lost.
        // That's the "drove 3.3 km but app shows 2.7 km" complaint.
        //
        // We still keep the teleport-speed check (above) and the accuracy
        // check (above) so we don't accept obviously broken fixes.
        // ====================================================================
        final isLongGapRecovery = forceRecord &&
            timeDeltaSec >= 30 &&
            distanceDelta >= 120.0 &&
            segmentSpeedKmh >= 5.0 &&
            position.accuracy <= AppConstants.maxAccuracyThreshold;

        // When the gap is BIG (≥ 60s straight-line and ≥ 200m), we
        // emit an event so the main isolate can hit Google Maps
        // Directions for the actual driving distance — straight-line
        // haversine massively under-counts a winding road trip the
        // user actually drove while location was off. The main
        // isolate compares Maps distance vs straight-line and
        // applies the delta to totalDistance via a callback.
        // Lower thresholds (was 60s + 200m → now 25s + 80m) so even
        // brief location-off gaps trigger a Maps Directions lookup.
        // The previous values left typical ~30-second toggles
        // ("just turned location off at the toll gate") completely
        // un-credited, so 5+ km of real road got reported as the
        // straight-line haversine which under-counts winding routes.
        if (forceRecord &&
            timeDeltaSec >= 25 &&
            distanceDelta >= 80.0 &&
            segmentSpeedKmh >= 5.0 &&
            lastPosition != null) {
          try {
            service.invoke('mapsGapRecovery', {
              'fromLat': lastPosition!.latitude,
              'fromLng': lastPosition!.longitude,
              'toLat': position.latitude,
              'toLng': position.longitude,
              'haversineM': distanceDelta,
              'gapSec': timeDeltaSec,
            });
          } catch (_) {}
        }

        final requiresConfirmation =
            !isLongGapRecovery && (wasStationary || movementCandidateCount > 0);
        bool didCommit = false;

        if (isLongGapRecovery) {
          logger.i(
              'GAP-RECOVERY: forced fresh fix after ${timeDeltaSec}s gap — '
              'crediting ${distanceDelta.toStringAsFixed(1)}m '
              '(speed ${segmentSpeedKmh.toStringAsFixed(1)} km/h, acc ${position.accuracy.toStringAsFixed(0)}m)');
          resetMovementCandidate();
          stationaryCount = 0;
          firstStationaryAt = null;
          stationaryAlarmFired = false;
        }

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
          final candidateSpeedKmh = candidateSpeedMps * 3.6;
          final highQualityFix = position.accuracy <= 35.0;
          final hasDepartureSpeed =
              candidateSpeedKmh >= 4.0 || reportedSpeedKmh >= 4.0;
          final confirmedMovement = (distanceDelta >= 350.0 &&
                  hasDepartureSpeed &&
                  movementCandidateCount >= 3 &&
                  movementCandidateProgressCount >= 2) ||
              (highQualityFix &&
                  candidateElapsedSec >= 20 &&
                  candidateElapsedSec <= 120 &&
                  distanceDelta >= 220.0 &&
                  hasDepartureSpeed &&
                  movementCandidateCount >= 4 &&
                  movementCandidateProgressCount >= 3);

          if (!confirmedMovement) {
            shouldRecord = false;
            isMoving = false;
            logger.d(
              'Movement CANDIDATE ignored for distance: '
              '${distanceDelta.toStringAsFixed(1)}m from anchor, '
              'count=$movementCandidateCount, '
              'progress=$movementCandidateProgressCount, '
              'elapsed=${candidateElapsedSec}s, '
              'candidateKmh=${candidateSpeedKmh.toStringAsFixed(1)}, '
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

          // Track sustained driving speed across fixes. We use the EMA-
          // smoothed calculatedSpeedKmh (computed below in the same tick)
          // so a single noisy GPS fix can't trip us. If a fix falls
          // BELOW the threshold the counter resets — we need a
          // continuous run.
          final speedKmh = segmentSpeedKmh > 0
              ? segmentSpeedKmh
              : (position.speed.isFinite ? position.speed * 3.6 : 0);
          if (speedKmh >= autoResumeSpeedKmh) {
            autoResumeFastFixHits++;
          } else {
            autoResumeFastFixHits = 0;
          }

          final distanceOk = distanceFromPauseAnchor >= autoResumeDistanceM;
          final speedOk = autoResumeFastFixHits >= autoResumeFastFixThreshold;

          if (distanceOk && speedOk) {
            logger.i(
                'AUTO-RESUME: ${distanceFromPauseAnchor.toStringAsFixed(0)}m from anchor + '
                '$autoResumeFastFixHits fast fixes (>=${autoResumeSpeedKmh}km/h) - resuming');
            isPaused = false;
            stationaryCount = 0;
            firstStationaryAt = null;
            stationaryAlarmFired = false;
            pausedAlarmFired = false;
            autoResumeFastFixHits = 0;
            resetMovementCandidate();
            await prefs.setBool(TrackingService._keyIsPaused, false);
            await prefs.remove(TrackingService._keyAutoPauseAt);
            try {
              await flutterLocalNotificationsPlugin.cancel(90201);
            } catch (_) {}
            autoPauseAnchorLat = null;
            autoPauseAnchorLng = null;
            autoPauseNotified = false;

            // Full-screen-intent alarm so it wakes the screen even if
            // the app is closed. Payload 'auto_resumed' tells the main
            // isolate's tap handler to navigate to the home screen
            // with the Pause/Stop card visible.
            try {
              await flutterLocalNotificationsPlugin.show(
                10002,
                'Tracking resumed automatically',
                'Movement detected (${distanceFromPauseAnchor.toStringAsFixed(0)}m, '
                    '${speedKmh.toStringAsFixed(0)} km/h). '
                    'Tap to open the app and confirm.',
                NotificationDetails(
                  android: AndroidNotificationDetails(
                    'benzmobitraq_stationary_alarm',
                    'Session Alarm',
                    channelDescription:
                        'Sounds when your session has been stationary, paused too long, or resumed automatically.',
                    importance: Importance.max,
                    priority: Priority.max,
                    category: AndroidNotificationCategory.alarm,
                    fullScreenIntent: true,
                    icon: '@mipmap/ic_launcher',
                    enableVibration: true,
                    vibrationPattern:
                        Int64List.fromList([0, 400, 150, 400, 150, 400]),
                    playSound: true,
                    visibility: NotificationVisibility.public,
                  ),
                  iOS: const DarwinNotificationDetails(
                    presentAlert: true,
                    presentSound: true,
                    interruptionLevel: InterruptionLevel.timeSensitive,
                  ),
                ),
                payload: 'auto_resumed',
              );
            } catch (e) {
              logger.w('Failed to show auto-resume alarm: $e');
            }

            service.invoke('autoResumed', {
              'resumedAt': now.millisecondsSinceEpoch,
              'distanceFromAnchor': distanceFromPauseAnchor,
              'speedKmh': speedKmh,
            });
          }
        } else if (!isPaused) {
          // Not paused → keep the counter clean so a future pause
          // starts from zero.
          autoResumeFastFixHits = 0;
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
          stationaryAlarmFired = false;
        }
      }

      // ============================================================
      // AUTO-PAUSE DETECTION (DISABLED BY PRODUCT DECISION)
      //
      // The product requirement is: a session keeps tracking until the
      // user explicitly taps Work Done. No silent auto-pause after 30
      // minutes stationary. Field staff doing long meetings or waiting
      // at a customer site should not have their session pause behind
      // their back — that was the #1 source of "the app stopped
      // tracking me" complaints. The auto-resume path is still wired
      // for the case where a user manually pauses and then walks away,
      // but the BG isolate will never enter paused mode on its own.
      //
      // PAUSED-TOO-LONG ALARM — fire once when the session has been
      // manually paused for ≥ 30 minutes. This used to be a Dart Timer
      // running in the main isolate, which silently died when the app
      // was killed (the #1 reason "the pause alarm never fires when I
      // don't open the app" — exactly the user-reported bug). Now we
      // schedule it from the BG isolate using the same direct
      // flutter_local_notifications path as the stationary alarm, so
      // it works regardless of app foreground state.
      if (isPaused && !pausedAlarmFired) {
        final pausedAtIso = prefs.getString(TrackingService._keyAutoPauseAt);
        if (pausedAtIso != null) {
          final pausedAt = DateTime.tryParse(pausedAtIso);
          if (pausedAt != null) {
            final pausedMin = now.difference(pausedAt).inMinutes;
            if (pausedMin >= 30) {
              pausedAlarmFired = true;
              logger.i('PAUSED-ALARM: fired after ${pausedMin}min paused');
              try {
                await flutterLocalNotificationsPlugin.show(
                  90201, // distinct id from stationary alarm
                  'Session paused for $pausedMin minutes',
                  'Tap to resume tracking or end the session.',
                  NotificationDetails(
                    android: AndroidNotificationDetails(
                      'benzmobitraq_stationary_alarm',
                      'Session Alarm',
                      channelDescription:
                          'Sounds when your session has been stationary or paused too long.',
                      importance: Importance.max,
                      priority: Priority.max,
                      category: AndroidNotificationCategory.alarm,
                      fullScreenIntent: true,
                      icon: '@mipmap/ic_launcher',
                      enableVibration: true,
                      vibrationPattern:
                          Int64List.fromList([0, 900, 250, 900, 250, 900]),
                      playSound: true,
                      ongoing: true,
                      autoCancel: false,
                      visibility: NotificationVisibility.public,
                    ),
                    iOS: const DarwinNotificationDetails(
                      presentAlert: true,
                      presentSound: true,
                      interruptionLevel: InterruptionLevel.timeSensitive,
                    ),
                  ),
                  payload: 'paused_too_long',
                );
              } catch (e) {
                logger.w('BG-PAUSED-ALARM: notification failed: $e');
              }
              try {
                service.invoke('pauseExpired', {
                  'durationMin': pausedMin,
                  'at': now.millisecondsSinceEpoch,
                });
              } catch (_) {}
            }
          }
        }
      }

      // STATIONARY ALARM — fire once when the user has been stationary
      // for ≥ 30 minutes during an active (not paused) session. The
      // threshold was raised from 10 → 30 min after field staff reported
      // false positives during normal customer meetings. The alarm is
      // gated by `stationaryAlarmFired` so the user is not bombarded;
      // it resets the moment they resume movement. We do NOT auto-pause
      // — the alarm just nudges the user to confirm they're still
      // working.
      final stationaryDurationMin = firstStationaryAt != null
          ? now.difference(firstStationaryAt!).inMinutes
          : 0;
      if (stationaryDurationMin >= 30 && !isPaused && !stationaryAlarmFired) {
        stationaryAlarmFired = true;
        logger.i(
            'STATIONARY-ALARM: fired after ${stationaryDurationMin}min stationary');
        // Fire the OS-level alarm notification DIRECTLY from the background
        // isolate. This is the primary alarm path: it works even when the
        // main isolate is suspended (app backgrounded or killed). The
        // service.invoke below is a secondary path for in-app dialog when
        // the main isolate happens to be alive.
        try {
          await flutterLocalNotificationsPlugin.show(
            90200, // matches NotificationService.alarmNotificationId
            'Stopped for $stationaryDurationMin minutes',
            'Your session is still running. Open the app to pause, continue tracking, or end the session.',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'benzmobitraq_stationary_alarm',
                'Session Alarm',
                channelDescription:
                    'Sounds when your session has been stationary or paused too long.',
                importance: Importance.max,
                priority: Priority.max,
                category: AndroidNotificationCategory.alarm,
                fullScreenIntent: true,
                icon: '@mipmap/ic_launcher',
                enableVibration: true,
                vibrationPattern:
                    Int64List.fromList([0, 900, 250, 900, 250, 900]),
                playSound: true,
                ongoing: true,
                autoCancel: false,
                visibility: NotificationVisibility.public,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentSound: true,
                interruptionLevel: InterruptionLevel.timeSensitive,
              ),
            ),
            payload: 'stationary_alarm',
          );
        } catch (e) {
          logger.w('BG-ALARM: Failed to show alarm notification: $e');
        }
        try {
          service.invoke('stationaryAlarm', {
            'durationMin': stationaryDurationMin,
            'lat': position.latitude,
            'lng': position.longitude,
            'at': now.millisecondsSinceEpoch,
          });
        } catch (_) {}
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

          final hasRealRecoveryMovement =
              (recoveryDistance >= 120.0 && recoverySpeedKmh >= 5.0) ||
                  (recoveryDistance >= 300.0 && recoverySpeedKmh >= 2.0);

          // Time-bounded recovery: only credit a restart gap when the
          // displacement and implied speed look like real travel. A phone
          // sitting on a desk can drift tens of meters after GPS warm-up.
          if (timeSinceLastSec <= 43200 &&
              recoverySpeedKmh <= 200.0 &&
              hasRealRecoveryMovement) {
            if (!isPaused) {
              totalDistance += recoveryDistance;
              acceptedDistanceDeltaM = recoveryDistance;
              countsForDistance = recoveryDistance > 0;
            }
            logger.i(
                'RECOVERY: Gap ${timeSinceLastSec}s, +${recoveryDistance.toStringAsFixed(1)}m @ ${recoverySpeedKmh.toStringAsFixed(1)} km/h');
          } else if (timeSinceLastSec <= 43200 && !hasRealRecoveryMovement) {
            logger.i(
                'RECOVERY: rejected stationary restart drift ${recoveryDistance.toStringAsFixed(1)}m @ ${recoverySpeedKmh.toStringAsFixed(1)} km/h');
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
      hasEmittedLocationUpdate = true;
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
        distanceFilter:
            5, // Lowered from 10: captures early-session movement sooner
      ),
    ).listen(
      (p) => onPositionReceived(p, forceRecord: false),
      onError: (error) async {
        // The old handler just logged and left the subscription in a
        // half-dead state — the user's "remove from recents → GPS never
        // recovers" symptom. Now we tear down and rebuild the stream
        // explicitly, with a short backoff so we don't tight-loop if
        // permissions were just revoked.
        logger.e('Location stream error — auto-restarting in 2s: $error');
        service.invoke('error', {'message': 'GPS stream error, restarting…'});
        try {
          await positionSubscription?.cancel();
        } catch (_) {}
        positionSubscription = null;
        await Future.delayed(const Duration(seconds: 2));
        if (currentSessionId != null) {
          try {
            await (startLocationUpdatesRef ?? () async {})();
            logger.i('Location stream restarted after error');
          } catch (e) {
            logger.e('Auto-restart of location stream failed: $e');
          }
        }
      },
      cancelOnError: false,
    );

    // Stationary heartbeat: force a point even when the device doesn't move.
    // REDUCED from 120s → 60s to minimize map gaps when OS throttles GPS stream.
    // This is required for strict "30 minutes within radius" stop detection
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
    // Suppress the deferred SELF-RECOVERY notification — if the main
    // isolate is telling us to start a session, this is NOT an
    // OS-kill recovery, it's a user-initiated start.
    deferredRecoveryNotificationCancelled = true;
    try {
      await flutterLocalNotificationsPlugin.cancel(90002);
    } catch (_) {}

    currentSessionId = event?['sessionId'] as String?;
    final isResume = event?['isResume'] as bool? ?? false;

    logger.i('Session started: $currentSessionId (Resuming: $isResume)');

    if (!isResume) {
      // ================================================================
      // FULL BG-ISOLATE STATE RESET FOR NEW SESSION
      //
      // Why this is gnarly: when a user is stationary for hours (e.g.
      // sitting at a customer site, forgot to end the previous session),
      // bg-isolate variables like `firstStationaryAt`, `isMoving`,
      // `lastPositionTime`, the persistent recoveryLat/Lon prefs, and
      // the kalman filter all hold values that describe "stuck in a
      // 3-hour stationary streak at point X". On Work Done + Present
      // these variables MUST go back to a pristine boot state — if any
      // one of them leaks, the new session interprets the first
      // movement as "still stationary at X" and silently rejects
      // distance for the first several minutes. That's the
      // "kilometres not being tracked in the new session" bug.
      //
      // EVERY in-memory variable that influences the distance-filter
      // pipeline is reset here. Persistent prefs that mirror these
      // variables are wiped too, so a hot-restart of the isolate
      // (rare but possible during the start sequence) does not pick
      // up stale state.
      // ================================================================
      lastDistanceNotifiedKm = 0;
      lastTimeNotification = DateTime.now();
      totalDistance = 0;
      lastPosition = null;
      lastPositionTime = null;
      stationaryCount = 0;
      firstStationaryAt = null;
      stationaryAlarmFired = false; // ← was leaking across sessions
      isMoving = true; // ← was leaking false across sessions
      hasEmittedLocationUpdate = false;
      isPaused = false;
      calculatedSpeedKmh = 0;
      autoPauseAnchorLat = null;
      autoPauseAnchorLng = null;
      autoPauseNotified = false;
      stationarySpotSeconds = 0;
      stationarySpotAnchorLat = null;
      stationarySpotAnchorLng = null;
      stationarySpotNotified = false;
      pausedResumeMonitorTimer?.cancel();
      pausedResumeMonitorTimer = null;
      resetMovementCandidate();
      kalman.reset();
      // Drop the persistent recovery anchor so the brand-new session
      // does not interpolate distance from where the previous session
      // ended hours ago.
      recoveryLat = null;
      recoveryLon = null;
      try {
        await prefs.remove(TrackingService._keyLastLat);
        await prefs.remove(TrackingService._keyLastLon);
        await prefs.remove(TrackingService._keyLastPositionTime);
        await prefs.remove(TrackingService._keyTotalDistance);
        await prefs.setDouble('session_distance_meters', 0);
      } catch (_) {}
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
      // Keep the position stream running even while paused so the
      // in-handler auto-resume check (distance-from-pause-anchor) can
      // fire on the first real movement. Distance accumulation stays
      // gated by `if (!isPaused)`, so this does NOT inflate km.
      await startLocationUpdates();
      startPausedResumeMonitor();
      logger.i(
          'Session restored in paused mode; stream live for auto-resume detection');
    } else {
      await startLocationUpdates();

      // ================================================================
      // GPS COLD-START WAKE-UP with retries
      //
      // If the user was stationary for hours (e.g. parked at a customer
      // site) the GPS chip is in deep sleep. A single 8-second
      // getCurrentPosition almost always times out in that state — it
      // takes 30-90 seconds for the chip to re-acquire satellites from
      // cold. Without an anchor, the first new GPS fix from the stream
      // can land much later (when the user is already 1+ km away), and
      // the early distance gets silently lost.
      //
      // Strategy: try up to 4 times with escalating timeouts. First two
      // attempts use bestForNavigation (most accurate but slowest to
      // fix). If still nothing after 30s, fall back to high accuracy
      // which is faster. We also use getLastKnownPosition() as a same-
      // moment seed so even if the chip is dead, the next position
      // delta is correct.
      // ================================================================
      if (!isResume) {
        unawaited(() async {
          // Seed with last-known so subsequent fixes have *some* anchor
          // to compare against, preventing the first real fix from being
          // treated as "first ever after restart" (which can apply a
          // recovery interpolation).
          try {
            final lk = await Geolocator.getLastKnownPosition();
            if (lk != null) {
              lastPosition = lk;
              lastPositionTime = DateTime.now();
              logger.i(
                  'GPS WAKEUP: seeded with last-known ${lk.latitude}, ${lk.longitude} (acc ${lk.accuracy}m)');
            }
          } catch (_) {}

          Position? p;
          final attempts = <(LocationAccuracy, int)>[
            (LocationAccuracy.bestForNavigation, 12),
            (LocationAccuracy.bestForNavigation, 20),
            (LocationAccuracy.high, 25),
            (LocationAccuracy.high, 30),
          ];
          for (var i = 0; i < attempts.length; i++) {
            final (acc, secs) = attempts[i];
            try {
              p = await Geolocator.getCurrentPosition(
                desiredAccuracy: acc,
              ).timeout(Duration(seconds: secs));
              logger.i(
                  'GPS WAKEUP attempt ${i + 1} OK: ${p.latitude}, ${p.longitude} (acc ${p.accuracy}m)');
              break;
            } catch (e) {
              logger.w(
                  'GPS WAKEUP attempt ${i + 1} (acc=$acc, ${secs}s) failed: $e');
              // brief backoff before next try
              await Future.delayed(const Duration(seconds: 2));
            }
          }
          if (p != null) {
            await prefs.setDouble(TrackingService._keyLastLat, p.latitude);
            await prefs.setDouble(TrackingService._keyLastLon, p.longitude);
            lastPosition = p;
            lastPositionTime = DateTime.now();
            onPositionReceived(p, forceRecord: true);
          } else {
            // Final fallback: surface to the user. The position stream
            // may still recover on its own, but we want them to know.
            logger.e('GPS WAKEUP: all attempts failed — chip may be dead');
            try {
              service.invoke('error', {
                'message':
                    'GPS could not get a fix at session start. Move outdoors or check location settings.',
                'code': 'gps_warmup_failed',
              });
            } catch (_) {}
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
    backgroundHealthTimer?.cancel();
    backgroundHealthTimer = null;
    currentSessionId = null;

    // Full state wipe — same set of variables the new-session reset
    // touches. This way, even if the user opens the app and waits an
    // hour before tapping Present, the bg-isolate is already in a
    // pristine state and we don't depend on the next startSession to
    // clean up correctly. Belt-and-suspenders against the "kilometres
    // not tracked in new session" bug.
    lastPosition = null;
    lastPositionTime = null;
    stationaryCount = 0;
    firstStationaryAt = null;
    stationaryAlarmFired = false;
    pausedAlarmFired = false;
    autoResumeFastFixHits = 0;
    _recentFixes.clear();
    try {
      await flutterLocalNotificationsPlugin.cancel(90201);
    } catch (_) {}
    isMoving = true;
    isPaused = false;
    calculatedSpeedKmh = 0;
    autoPauseAnchorLat = null;
    autoPauseAnchorLng = null;
    autoPauseNotified = false;
    stationarySpotSeconds = 0;
    stationarySpotAnchorLat = null;
    stationarySpotAnchorLng = null;
    stationarySpotNotified = false;
    recoveryLat = null;
    recoveryLon = null;
    resetMovementCandidate();
    kalman.reset();
  });

  service.on('stopService').listen((event) async {
    logger.i('Service stop requested');
    await stopLocationUpdates();
    backgroundHealthTimer?.cancel();
    backgroundHealthTimer = null;
    service.stopSelf();
  });

  // ============================================================
  // SELF-RECOVERY: AUTO-START GPS AFTER OS KILL
  // ============================================================
  // If we detected a killed session during init (currentSessionId was set
  // from persisted prefs), now that startLocationUpdates is defined we
  // can kick off GPS tracking.
  if (currentSessionId != null && wasTracking) {
    logger.i(
        'SELF-RECOVERY: Kicking off GPS tracking for recovered session $currentSessionId');
    if (isPaused) {
      autoPauseAnchorLat ??= prefs.getDouble(TrackingService._keyLastLat);
      autoPauseAnchorLng ??= prefs.getDouble(TrackingService._keyLastLon);
      // Even when paused, keep the position stream alive so movement-based
      // auto-resume can fire after an OS-kill recovery.
      await startLocationUpdates();
      startPausedResumeMonitor();
      logger.i(
          'SELF-RECOVERY: Session is paused; stream live for auto-resume detection');
    } else {
      await startLocationUpdates();
      logger.i('SELF-RECOVERY: GPS tracking restarted successfully');
    }

    // Update foreground notification. We do NOT tag with "(Recovered)"
    // anymore — that was firing on every fresh user-initiated start
    // too (since the bg-isolate's _onServiceStart runs before the
    // main isolate's startSession command lands), confusing the user
    // who just tapped Present into thinking their session was being
    // "resumed" instead of "started".
    if (service is AndroidServiceInstance) {
      try {
        service.setForegroundNotificationInfo(
          title: 'Tracking Active',
          content: '${(totalDistance / 1000).toStringAsFixed(2)} km tracked',
        );
      } catch (e) {
        logger.w('Failed to update foreground notification: $e');
      }
    }
  }

  // ============================================================
  // LOCATION-SERVICE STATUS STREAM
  // ============================================================
  // When the user toggles location off then on (Quick Settings tile,
  // airplane mode, Settings → Location), the active position stream
  // dies silently and never recovers. Geolocator exposes a service-
  // status stream — we listen to it and re-subscribe the position
  // stream the moment GPS comes back. This is what fixes the
  // "Acquiring GPS forever" bug field users keep hitting.
  // Note: this subscription intentionally lives for the lifetime of the
  // background isolate and is implicitly cancelled when the isolate
  // exits via stopService. We assign through a setter to suppress the
  // 'unused' analyzer hint without losing the typing.
  bool lastKnownServiceEnabled = true;
  try {
    lastKnownServiceEnabled = await Geolocator.isLocationServiceEnabled();
  } catch (_) {}

  // ignore: cancel_subscriptions, unused_local_variable
  final StreamSubscription<ServiceStatus> serviceStatusSubscription =
      Geolocator.getServiceStatusStream().listen(
    (status) async {
      final enabled = status == ServiceStatus.enabled;
      logger.i(
          'SERVICE-STATUS: location services -> ${enabled ? "ENABLED" : "DISABLED"}');

      if (!enabled && lastKnownServiceEnabled) {
        // User just turned location OFF. Cancel the dead position stream
        // so we are ready to attach a fresh one when it comes back.
        positionSubscription?.cancel();
        positionSubscription = null;

        // Inform the main isolate so the UI can warn the user. We send
        // BOTH an error (for backward-compat) and an explicit typed
        // serviceStatus event so the main isolate can update its
        // internal state (warning banner + watchdog grace period) in
        // a way it can later cleanly UNDO when location comes back.
        try {
          service.invoke('error', {
            'message':
                'Location services were turned off. Tracking is paused until GPS is re-enabled.',
            'code': 'location_services_disabled',
          });
          service.invoke('serviceStatus', {'enabled': false});
        } catch (_) {}

        // Persistent OS alert so the user sees this even when the app
        // is in the background.
        try {
          await flutterLocalNotificationsPlugin.show(
            90010,
            'Location is OFF',
            'Turn location back on — tracking is paused until you do.',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'benzmobitraq_tracking_alerts',
                'Tracking Alerts',
                channelDescription:
                    'Critical alerts when GPS or tracking is not working correctly',
                importance: Importance.max,
                priority: Priority.max,
                icon: '@mipmap/ic_launcher',
                enableVibration: true,
                ongoing: true,
                autoCancel: false,
                vibrationPattern:
                    Int64List.fromList([0, 200, 150, 200, 150, 200]),
              ),
            ),
          );
        } catch (e) {
          logger.w('Failed to show location-off notification: $e');
        }
      } else if (enabled && !lastKnownServiceEnabled) {
        // User just turned location ON again. Clear the persistent
        // warning, re-attach the position stream, and most importantly
        // force-deliver a fresh fix to the main isolate IMMEDIATELY so
        // the UI's "Acquiring GPS..." chip clears and the watchdog
        // resets its "stalled" clock. Without this last step, the user
        // sees "GPS acquiring" for 30+ seconds while the new stream
        // waits for its first event, and the watchdog falsely fires
        // "GPS stalled" notifications during that gap.
        try {
          await flutterLocalNotificationsPlugin.cancel(90010);
        } catch (_) {}

        // Tell main isolate first so it can immediately clear its
        // 'location services disabled' warning and grant the new
        // stream a grace window before re-arming the watchdog.
        try {
          service.invoke('serviceStatus', {'enabled': true});
        } catch (_) {}

        if (currentSessionId != null && !isPaused) {
          logger.i(
              'SERVICE-STATUS: GPS came back online — re-subscribing position stream');
          try {
            await startLocationUpdates();
            // Reset the GPS health stamp so the no-fix watchdog gives
            // the new stream a fair window before complaining.
            lastSuccessfulGpsTime = DateTime.now();
            try {
              service.invoke('trackingStateChanged', {'isTracking': true});
            } catch (_) {}

            // CRITICAL: do a one-shot getCurrentPosition right now so
            // the main isolate receives at least one fresh location
            // update within ~1-2 seconds (vs waiting 30+ seconds for
            // the next stream tick). This also feeds the gap into the
            // distance engine — if the user moved while location was
            // off, the existing `recoveryLat / recoveryLon` mechanism
            // (or a fresh delta from `lastPosition`) accounts for it.
            unawaited(() async {
              try {
                final p = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.bestForNavigation,
                ).timeout(const Duration(seconds: 10));
                logger.i(
                    'SERVICE-STATUS: forced fresh fix lat=${p.latitude}, lng=${p.longitude}, acc=${p.accuracy}m');
                onPositionReceived(p, forceRecord: true);
              } catch (e) {
                logger.w('SERVICE-STATUS: forced fresh fix failed: $e');
              }
            }());
          } catch (e) {
            logger
                .e('Failed to restart position stream after GPS came back: $e');
          }
        }
      }

      lastKnownServiceEnabled = enabled;
    },
    onError: (e) => logger.w('ServiceStatus stream error: $e'),
    cancelOnError: false,
  );

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

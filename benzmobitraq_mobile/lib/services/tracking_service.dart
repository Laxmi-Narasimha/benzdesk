import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../core/constants/app_constants.dart';

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
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  // Callbacks for the main isolate
  static Function(LocationUpdate)? onLocationUpdate;
  static Function(String)? onError;
  static Function(bool)? onTrackingStateChanged;

  // Storage keys for persisting state across restarts
  static const String _keySessionId = 'tracking_session_id';
  static const String _keyTotalDistance = 'tracking_total_distance';
  static const String _keyLastLat = 'tracking_last_lat';
  static const String _keyLastLon = 'tracking_last_lon';
  static const String _keyIsTracking = 'tracking_is_active';
  static const String _keySessionStartTime = 'session_start_time';

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize the background service
  /// 
  /// Must be called once at app startup (in main.dart).
  static Future<void> initialize() async {
    try {
      // Check if already running to avoid crash on re-configure
      if (await _service.isRunning()) {
        _logger.i('Tracking service already running, skipping configuration');
        // Re-attach listeners even if running
        _attachListeners();
        return;
      }

      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onServiceStart,
          autoStart: false,
          autoStartOnBoot: false,
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
  }

  // ============================================================
  // START/STOP TRACKING
  // ============================================================

  /// Start location tracking for a session
  /// 
  /// This starts the foreground service and begins GPS updates.
  /// The service will continue running even if the app is killed.
  static Future<bool> startTracking(String sessionId, {bool isResume = false}) async {
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

      // Start the background service
      final isRunning = await _service.isRunning();
      if (!isRunning) {
        await _service.startService();
      }

      // Send session ID to the service
      _service.invoke('startSession', {
        'sessionId': sessionId,
        'isResume': isResume,
      });

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
      await prefs.setBool(_keyIsTracking, false);

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
  
  // State
  String? currentSessionId;
  StreamSubscription<Position>? positionSubscription;
  Position? lastPosition;
  DateTime? lastPositionTime;
  double totalDistance = 0;
  bool isMoving = true;
  int stationaryCount = 0;
  DateTime sessionStartTime = DateTime.now(); // Will be overwritten when session starts

  // Load persisted state
  final prefs = await SharedPreferences.getInstance();
  totalDistance = prefs.getDouble(TrackingService._keyTotalDistance) ?? 0;
  final lastLat = prefs.getDouble(TrackingService._keyLastLat);
  final lastLon = prefs.getDouble(TrackingService._keyLastLon);
  
  // Load session start time for elapsed time calculation
  final startTimeMs = prefs.getInt(TrackingService._keySessionStartTime);
  if (startTimeMs != null) {
    sessionStartTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
  }

  // ============================================================
  // LOCATION TRACKING
  // ============================================================

  void _onPositionReceived(Position position) async {
    final now = DateTime.now();

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

    if (lastPosition != null && lastPositionTime != null) {
      // Calculate distance
      distanceDelta = Geolocator.distanceBetween(
        lastPosition!.latitude,
        lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Calculate time delta
      final timeDelta = now.difference(lastPositionTime!).inSeconds;

      // ============================================================
      // ANTI-TELEPORT FILTER
      // ============================================================
      
      if (timeDelta > 0) {
        final speedMps = distanceDelta / timeDelta;
        final speedKmh = speedMps * 3.6;

        if (speedKmh > AppConstants.maxSpeedKmh) {
          logger.d('Rejected: teleport detected (${speedKmh.toStringAsFixed(1)} km/h)');
          return;
        }
      }

      // ============================================================
      // ADAPTIVE SAMPLING (bike vs car mode)
      // Per spec Section 7.3: speed-based distance thresholds
      // ============================================================
      
      // Check minimum time gate first (5 seconds)
      if (timeDelta < AppConstants.minTimeBetweenUpdates) {
        logger.d('Rejected: too soon (${timeDelta}s < ${AppConstants.minTimeBetweenUpdates}s)');
        return;
      }
      
      // Determine distance threshold based on speed
      final speedMps = position.speed >= 0 ? position.speed : 0.0;
      final distanceThreshold = speedMps <= AppConstants.bikeSpeedThresholdMps
          ? AppConstants.bikeDistanceThreshold  // Bike mode: 30m
          : AppConstants.carDistanceThreshold;   // Car mode: 60m
      
      if (distanceDelta < distanceThreshold) {
        stationaryCount++;
        
        // After several stationary readings, mark as not moving
        if (stationaryCount >= 3) {
          isMoving = false;
          
          // Still send occasional update for "still here" confirmation
          if (stationaryCount % 10 != 0) {
            shouldRecord = false;
          }
        }
      } else {
        // Movement detected - distance delta exceeds threshold
        // Since the distance threshold already filters GPS drift,
        // we always accumulate distance when it passes
        stationaryCount = 0;
        isMoving = true;
        totalDistance += distanceDelta;
        logger.d('Distance accumulated: +${distanceDelta.toStringAsFixed(1)}m, total=${totalDistance.toStringAsFixed(1)}m');
      }

    }

    // Update last position
    lastPosition = position;
    lastPositionTime = now;

    // Persist for recovery
    await prefs.setDouble(TrackingService._keyLastLat, position.latitude);
    await prefs.setDouble(TrackingService._keyLastLon, position.longitude);
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);

    if (!shouldRecord) return;

    // ============================================================
    // SEND UPDATE TO MAIN ISOLATE
    // ============================================================

    final update = LocationUpdate(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      altitude: position.altitude,
      heading: position.heading,
      timestamp: now,
      sessionId: currentSessionId,
      totalDistance: totalDistance,
      isMoving: isMoving,
    );

    service.invoke('locationUpdate', update.toMap());

    // Update notification
    if (service is AndroidServiceInstance) {
      final distanceKm = (totalDistance / 1000).toStringAsFixed(2);
      final status = isMoving ? 'Moving' : 'Stationary';
      
      // Calculate elapsed time
      final elapsed = DateTime.now().difference(sessionStartTime);
      final hours = elapsed.inHours;
      final minutes = elapsed.inMinutes % 60;
      final seconds = elapsed.inSeconds % 60;
      
      final timeStr = '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      
      (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: 'Tracking Active - $status',
        content: '$timeStr elapsed • $distanceKm km',
      );
    }

    // logger.d('Location: ${position.latitude.toStringAsFixed(6)}, '
    //     '${position.longitude.toStringAsFixed(6)} | '
    //     'Δ${distanceDelta.toStringAsFixed(1)}m | '
    //     'Total: ${totalDistance.toStringAsFixed(0)}m');
  }

  Future<void> _startLocationUpdates() async {
    positionSubscription?.cancel();

    // CRITICAL FIX: Use smaller distance filter for more frequent updates
    final distanceFilter = 5; // Was AppConstants.distanceFilterDefault (50m)

    // CRITICAL FIX: Use bestForNavigation for highest accuracy
    // NOTE: Removed timeLimit as it causes TimeoutException on real devices
    // when GPS takes time to get initial fix (especially indoors)
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, // Balanced accuracy (battery friendly)
        distanceFilter: 30, // Update every 30 meters
      ),
    ).listen(
      _onPositionReceived,
      onError: (error) {
        logger.e('Location stream error: $error');
        service.invoke('error', {'message': 'Location error: $error'});
      },
      cancelOnError: false,
    );

    service.invoke('trackingStateChanged', {'isTracking': true});
    logger.i('Location updates started (30m filter, high accuracy)');
  }

  Future<void> _stopLocationUpdates() async {
    positionSubscription?.cancel();
    positionSubscription = null;
    
    // Persist state
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);
    
    service.invoke('trackingStateChanged', {'isTracking': false});
    logger.i('Location updates stopped');
  }

  // ============================================================
  // COMMAND HANDLERS
  // ============================================================

  service.on('startSession').listen((event) async {
    currentSessionId = event?['sessionId'] as String?;
    final isResume = event?['isResume'] as bool? ?? false;
    
    logger.i('Session started: $currentSessionId (Resuming: $isResume)');
    
    if (!isResume) {
      // Only reset for new sessions
      totalDistance = 0;
      lastPosition = null;
      stationaryCount = 0;
      sessionStartTime = DateTime.now();
      
      // Persist start time
      await prefs.setInt(TrackingService._keySessionStartTime, sessionStartTime.millisecondsSinceEpoch);
    } else {
      // For resume, load persisted distance if not already loaded
      if (totalDistance == 0) {
        totalDistance = prefs.getDouble(TrackingService._keyTotalDistance) ?? 0;
      }
    }
    
    await _startLocationUpdates();
  });

  service.on('stopSession').listen((event) async {
    // CRITICAL FIX: Only stop if we have an active session
    if (currentSessionId == null) {
      logger.w('stopSession called but no active session, ignoring');
      return;
    }
    
    logger.i('Session stopped: $currentSessionId');
    await _stopLocationUpdates();
    currentSessionId = null;
  });

  service.on('stopService').listen((event) async {
    logger.i('Service stop requested');
    await _stopLocationUpdates();
    service.stopSelf();
  });


}

/// iOS background mode handler
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

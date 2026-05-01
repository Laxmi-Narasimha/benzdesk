import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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
  // LAZY INSTANTIATION: Prevents usage in background isolate
  static FlutterBackgroundService get _service => FlutterBackgroundService();

  // Callbacks for the main isolate
  static Function(LocationUpdate)? onLocationUpdate;
  static Function(String)? onError;
  static Function(bool)? onTrackingStateChanged;
  
  // HANDSHAKE: Wait for background service to be ready
  static Completer<void>? _serviceReadyCompleter;

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

    _service.on('serviceReady').listen((event) {
      _logger.i('Handshake: Background service is ready');
      if (_serviceReadyCompleter != null && !_serviceReadyCompleter!.isCompleted) {
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
            await ackCompleter.future.timeout(const Duration(milliseconds: 2000));
            ackReceived = true;
            _logger.i('ACK received: Session started successfully in background');
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
  logger.i('DIAGNOSTIC: _onServiceStart EXECUTION STARTED. Service: ${service.hashCode}');
  
  // State
  String? currentSessionId;
  StreamSubscription<Position>? positionSubscription;
  Timer? stationaryHeartbeatTimer;
  Position? lastPosition;
  DateTime? lastPositionTime;
  double totalDistance = 0;
  bool isMoving = true;
  int stationaryCount = 0;
  DateTime sessionStartTime = DateTime.now(); // Will be overwritten when session starts

  // Background Notification Scheduler State
  Timer? backgroundNotifTimer;
  double lastDistanceNotifiedKm = 0;
  DateTime lastTimeNotification = DateTime.now();
  Map<String, dynamic>? notifSettingsMap;
  
  // Initialize Local Notifications for Background Use
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  try {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false);
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    logger.e('Failed to initialize background notifications: $e');
  }

  // Load persisted state
  final prefs = await SharedPreferences.getInstance();
  totalDistance = prefs.getDouble(TrackingService._keyTotalDistance) ?? 0;
  final savedLastLat = prefs.getDouble(TrackingService._keyLastLat);
  final savedLastLon = prefs.getDouble(TrackingService._keyLastLon);
  
  // CRITICAL FIX: Reconstruct lastPosition from saved coordinates.
  // Without this, after an OS-kill + restart the first location update
  // is treated as "first ever" and the gap distance is lost.
  if (savedLastLat != null && savedLastLon != null) {
    // Create a synthetic Position-like object from saved coords.
    // We can't create a real Position, but we'll use a flag to track this.
    logger.i('RECOVERY: Restoring last position from persisted state: $savedLastLat, $savedLastLon');
  }
  
  // Load session start time for elapsed time calculation
  final startTimeMs = prefs.getInt(TrackingService._keySessionStartTime);
  if (startTimeMs != null) {
    sessionStartTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
  }

  // ============================================================
  // LOCATION TRACKING
  // ============================================================

  // Persisted anchor for gap recovery (set from prefs, cleared once used)
  double? _recoveryLat = savedLastLat;
  double? _recoveryLon = savedLastLon;

  void _onPositionReceived(Position position, {bool forceRecord = false}) async {
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
          // CRITICAL: Even though we reject this point for distance,
          // update the anchor so we don't accumulate a massive
          // distance delta after the teleport resolves.
          lastPosition = position;
          lastPositionTime = now;
          return;
        }
      }

      // ============================================================
      // ACCURACY-WEIGHTED JITTER FILTER
      // ============================================================
      
      // Check minimum time gate first
      if (timeDelta < AppConstants.minTimeBetweenUpdates && distanceDelta < AppConstants.carDistanceThreshold) {
        logger.d('Rejected: too soon (${timeDelta}s < ${AppConstants.minTimeBetweenUpdates}s)');
        return;
      }
      
      // Accuracy-weighted distance threshold:
      // The minimum movement must exceed max(30m, 3 * accuracy) to prevent
      // GPS drift at rest from inflating distance. Even at 3m accuracy,
      // this gives a 30m threshold which filters most stationary noise.
      final accuracyWeightedThreshold = (position.accuracy * 3).clamp(30.0, 100.0);
      
      // Also use speed-based threshold for highway driving
      final speedMps = position.speed >= 0 ? position.speed : 0.0;
      final speedBasedThreshold = speedMps <= AppConstants.bikeSpeedThresholdMps
          ? 30.0   // Walking/bike: 30m minimum
          : 50.0;  // Car/highway: 50m minimum
      
      final distanceThreshold = accuracyWeightedThreshold > speedBasedThreshold
          ? accuracyWeightedThreshold
          : speedBasedThreshold;
      
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
        // DO NOT update lastPosition! Let distance build up from the original anchor.
      } else {
        // Movement detected - distance delta exceeds threshold
        stationaryCount = 0;
        isMoving = true;
        totalDistance += distanceDelta;
        logger.d('Distance accumulated: +${distanceDelta.toStringAsFixed(1)}m, total=${totalDistance.toStringAsFixed(1)}m');
        
        // Update anchor position
        lastPosition = position;
        lastPositionTime = now;
      }

    } else {
      // CRITICAL FIX: First position after restart — check if we have a
      // persisted anchor from before the OS killed us.
      if (_recoveryLat != null && _recoveryLon != null) {
        // Calculate distance from persisted anchor to current position
        final recoveryDistance = Geolocator.distanceBetween(
          _recoveryLat!, _recoveryLon!,
          position.latitude, position.longitude,
        );
        
        // Only accumulate if it passes basic sanity checks
        // (not a teleport, the gap is reasonable)
        if (recoveryDistance > 30 && recoveryDistance < 50000) {
          // Rough speed check: assume max 30 min gap at 160 km/h = 80 km max
          totalDistance += recoveryDistance;
          logger.i('RECOVERY: Accumulated gap distance: +${recoveryDistance.toStringAsFixed(1)}m');
        } else if (recoveryDistance >= 50000) {
          logger.w('RECOVERY: Rejected gap distance as teleport: ${recoveryDistance.toStringAsFixed(1)}m');
        }
        
        // Clear recovery anchor — it's consumed
        _recoveryLat = null;
        _recoveryLon = null;
      }
      
      // Set current position as anchor
      lastPosition = position;
      lastPositionTime = now;
    }

    // Persist for recovery
    if (lastPosition != null) {
      await prefs.setDouble(TrackingService._keyLastLat, lastPosition!.latitude);
      await prefs.setDouble(TrackingService._keyLastLon, lastPosition!.longitude);
    }
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);

    if (!shouldRecord && !forceRecord) return;

    // ============================================================
    // SEND UPDATE TO MAIN ISOLATE
    // ============================================================

    // RAW LOGGING FOR DEBUGGING
    logger.i('RAW LOC: ${position.latitude}, ${position.longitude} | Acc: ${position.accuracy}');

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

    try {
      service.invoke('locationUpdate', update.toMap());
    } catch (e) {
      logger.e('FAILED TO INVOKE locationUpdate: $e');
    }

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
      
      try {
        service.setForegroundNotificationInfo(
          title: 'Tracking Active - $status',
          content: '$timeStr elapsed • $distanceKm km',
        );
      } catch (e) {
        logger.e('Failed to update notification: $e');
      }
    }

    // logger.d('Location: ${position.latitude.toStringAsFixed(6)}, '
    //     '${position.longitude.toStringAsFixed(6)} | '
    //     'Δ${distanceDelta.toStringAsFixed(1)}m | '
    //     'Total: ${totalDistance.toStringAsFixed(0)}m');
    
    logger.i('DIAGNOSTIC: Location generated: ${position.latitude}, ${position.longitude}. Acc: ${position.accuracy}');
  }

  Future<void> _startLocationUpdates() async {
    positionSubscription?.cancel();

    // CRITICAL FIX: Use smaller distance filter for more frequent updates
    // distance filter is configured inline below in LocationSettings

    // CRITICAL FIX: Use bestForNavigation for highest accuracy
    // NOTE: Removed timeLimit as it causes TimeoutException on real devices
    // when GPS takes time to get initial fix (especially indoors)
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, // Balanced accuracy (battery friendly)
        distanceFilter: 10, // Smaller filter improves stationary detection
      ),
    ).listen(
      (p) => _onPositionReceived(p, forceRecord: false),
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
    stationaryHeartbeatTimer?.cancel();
    stationaryHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) async {
        if (currentSessionId == null) return;
        try {
          final p = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          _onPositionReceived(p, forceRecord: true);
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
      final double targetDistanceKm = (notifSettingsMap?['distanceKm'] as num?)?.toDouble() ?? 1.0;
      final int targetTimeMinutes = (notifSettingsMap?['timeMinutes'] as int?) ?? 10;
      
      backgroundNotifTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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
        if (now.difference(lastTimeNotification).inMinutes >= targetTimeMinutes) {
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
    logger.i('Location updates started (10m filter, high accuracy, 60s heartbeat)');
  }

  Future<void> _stopLocationUpdates() async {
    positionSubscription?.cancel();
    positionSubscription = null;
    stationaryHeartbeatTimer?.cancel();
    stationaryHeartbeatTimer = null;
    backgroundNotifTimer?.cancel();
    backgroundNotifTimer = null;
    
    // Persist state
    await prefs.setDouble(TrackingService._keyTotalDistance, totalDistance);
    
    try {
      service.invoke('trackingStateChanged', {'isTracking': false});
    } catch (e) {
      logger.e('Failed to invoke trackingStateChanged: $e');
    }
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
      lastDistanceNotifiedKm = 0;
      lastTimeNotification = DateTime.now();
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
    
    // Send ACK to main isolate
    service.invoke('sessionStarted', {'sessionId': currentSessionId});
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

  // SIGNAL READY TO MAIN ISOLATE
  // This prevents the race condition where Main sends startSession before we are listening
  service.invoke('serviceReady');
  logger.i('DIAGNOSTIC: Background Service Ready & Listening');
}

/// iOS background mode handler
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

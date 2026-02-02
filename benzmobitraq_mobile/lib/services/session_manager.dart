import 'dart:async';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../data/models/session_model.dart';
import '../data/models/location_point_model.dart';
import '../data/models/notification_settings.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/location_repository.dart';
import '../data/datasources/local/preferences_local.dart';
import 'tracking_service.dart';
import 'permission_service.dart';
import 'geocoding_service.dart';
import 'notification_scheduler.dart';

/// Session status for UI feedback
enum ManagerSessionStatus {
  idle,           // No active session
  starting,       // Starting session
  active,         // Session running, tracking active
  stopping,       // Stopping session
  error,          // Error occurred
}

/// Current session state with all relevant data
/// 
/// Named ManagerSessionState to avoid conflict with BLoC's SessionState
class ManagerSessionState {
  final ManagerSessionStatus status;
  final SessionModel? session;
  final double currentDistanceMeters;
  final Duration duration;
  final LocationUpdate? lastLocation;
  final String? errorMessage;
  final List<String> warnings;

  const ManagerSessionState({
    this.status = ManagerSessionStatus.idle,
    this.session,
    this.currentDistanceMeters = 0,
    this.duration = Duration.zero,
    this.lastLocation,
    this.errorMessage,
    this.warnings = const [],
  });

  double get currentDistanceKm => currentDistanceMeters / 1000;

  ManagerSessionState copyWith({
    ManagerSessionStatus? status,
    SessionModel? session,
    double? currentDistanceMeters,
    Duration? duration,
    LocationUpdate? lastLocation,
    String? errorMessage,
    List<String>? warnings,
  }) {
    return ManagerSessionState(
      status: status ?? this.status,
      session: session ?? this.session,
      currentDistanceMeters: currentDistanceMeters ?? this.currentDistanceMeters,
      duration: duration ?? this.duration,
      lastLocation: lastLocation ?? this.lastLocation,
      errorMessage: errorMessage ?? this.errorMessage,
      warnings: warnings ?? this.warnings,
    );
  }
}

/// Session Manager - Orchestrates the entire tracking workflow
/// 
/// This is the main controller that ties together:
/// - Session lifecycle (Present → Work Done)
/// - Location tracking service
/// - Local queue for offline storage
/// - Sync to backend
/// 
/// Usage:
/// ```dart
/// final manager = SessionManager(...);
/// await manager.initialize();
/// 
/// // Start work
/// await manager.startSession();
/// 
/// // Listen to updates
/// manager.stateStream.listen((state) => updateUI(state));
/// 
/// // End work  
/// await manager.stopSession();
/// ```
class SessionManager {
  final SessionRepository _sessionRepository;
  final LocationRepository _locationRepository;
  final PreferencesLocal _preferences;
  final PermissionService _permissionService;
  final NotificationScheduler? _notificationScheduler;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  // Current state
  ManagerSessionState _state = const ManagerSessionState();
  final _stateController = StreamController<ManagerSessionState>.broadcast();

  // Timers
  Timer? _durationTimer;
  Timer? _syncTimer;

  // Configuration
  static const Duration _syncInterval = Duration(minutes: 3);

  SessionManager({
    required SessionRepository sessionRepository,
    required LocationRepository locationRepository,
    required PreferencesLocal preferences,
    PermissionService? permissionService,
    NotificationScheduler? notificationScheduler,
  })  : _sessionRepository = sessionRepository,
        _locationRepository = locationRepository,
        _preferences = preferences,
        _permissionService = permissionService ?? PermissionService(),
        _notificationScheduler = notificationScheduler;

  /// Stream of session state updates
  Stream<ManagerSessionState> get stateStream => _stateController.stream;

  /// Current session state
  ManagerSessionState get currentState => _state;

  /// Whether a session is currently active
  bool get isSessionActive => _state.status == ManagerSessionStatus.active;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize the session manager
  /// 
  /// Must be called before using any other methods.
  /// This checks for any active session from a previous app run.
  Future<void> initialize() async {
    try {
      // Set up tracking service callbacks
      TrackingService.onLocationUpdate = _onLocationUpdate;
      TrackingService.onError = _onTrackingError;
      TrackingService.onTrackingStateChanged = _onTrackingStateChanged;

      // Check if there was an active session
      final activeSessionId = await _preferences.getActiveSessionId();
      if (activeSessionId != null) {
        _logger.i('Found active session: $activeSessionId');
        
        // Try to resume
        final session = await _sessionRepository.getSession(activeSessionId);
        if (session != null && session.isActive) {
          await _resumeSession(session);
        } else {
          // Session ended or invalid, clean up
          await _preferences.clearActiveSession();
        }
      }

      // Resume tracking if it was running
      await TrackingService.resumeIfNeeded();

      _logger.i('Session manager initialized');
    } catch (e) {
      _logger.e('Error initializing session manager: $e');
    }
  }

  /// Check if tracking is ready (permissions, services, etc.)
  Future<TrackingReadiness> checkReadiness() async {
    return await _permissionService.checkTrackingReadiness();
  }

  // ============================================================
  // START SESSION
  // ============================================================

  /// Start a new work session
  /// 
  /// This will:
  /// 1. Check permissions
  /// 2. Get current location for session start point
  /// 3. Create session in backend
  /// 4. Start background tracking
  /// 5. Begin sync timer
  Future<bool> startSession() async {
    if (_state.status == ManagerSessionStatus.active) {
      _logger.w('Session already active');
      return false;
    }

    _updateState(_state.copyWith(
      status: ManagerSessionStatus.starting,
      errorMessage: null,
    ));

    try {
      // Step 1: Check permissions
      final readiness = await checkReadiness();
      if (!readiness.canTrack) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: readiness.message,
        ));
        return false;
      }

      // Store warnings for UI
      List<String> warnings = readiness.warnings;

      // Step 2: Get current location
      final position = await TrackingService.getCurrentLocation();
      if (position == null) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Unable to get current location. Please try again.',
        ));
        return false;
      }

      // Step 2b: Get address
      String? address;
      try {
        address = await GeocodingService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        _logger.w('Failed to get start address: $e');
      }

      // Step 3: Get current user ID
      final userId = await _preferences.getUserId();
      if (userId == null) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Not logged in',
        ));
        return false;
      }

      // Step 4: Generate Session ID
      final sessionId = _uuid.v4();

      // CRITICAL FIX: Start tracking FIRST to allow rollback
      // Step 5: Start tracking
      // Save session ID locally temporarily for the service
      await _preferences.saveActiveSession(sessionId);
      
      final trackingStarted = await TrackingService.startTracking(sessionId);
      if (!trackingStarted) {
        await _preferences.clearActiveSession(); // Rollback
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Failed to start location tracking',
        ));
        return false;
      }

      // Step 6: Create session in backend
      final session = SessionModel.start(
        id: sessionId,
        employeeId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );

      final success = await _sessionRepository.startSession(
        session,
        position.latitude,
        position.longitude,
      );

      if (!success) {
        // Rollback tracking if DB fails
        await TrackingService.stopTracking();
        await _preferences.clearActiveSession();
        
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Failed to create session. Please check your connection.',
        ));
        return false;
      }

      // Step 7: Start timers
      await _preferences.setSessionStartTime(session.startTime);
      _startDurationTimer(session.startTime);
      _startSyncTimer();

      // Step 8: Start notification scheduler if available
      if (_notificationScheduler != null) {
        final notifSettings = await _preferences.getNotificationSettings();
        if (notifSettings != null) {
          _notificationScheduler!.startMonitoring(notifSettings);
        }
      }

      // Update state
      _updateState(ManagerSessionState(
        status: ManagerSessionStatus.active,
        session: session,
        currentDistanceMeters: 0,
        duration: Duration.zero,
        warnings: warnings,
      ));

      _logger.i('Session started: $sessionId');
      return true;
    } catch (e) {
      _logger.e('Error starting session: $e');
      // Emergency rollback
      await TrackingService.stopTracking();
      await _preferences.clearActiveSession();
      
      _updateState(_state.copyWith(
        status: ManagerSessionStatus.error,
        errorMessage: 'Error starting session: $e',
      ));
      return false;
    }
  }

  // ============================================================
  // STOP SESSION
  // ============================================================

  /// Stop the current work session
  /// 
  /// This will:
  /// 1. Stop background tracking
  /// 2. Get final location
  /// 3. Sync remaining location points
  /// 4. Update session in backend with end time and total km
  Future<SessionModel?> stopSession() async {
    if (_state.status != ManagerSessionStatus.active) {
      _logger.w('No active session to stop');
      return null;
    }

    _updateState(_state.copyWith(status: ManagerSessionStatus.stopping));

    try {
      // Step 1: Stop tracking
      final totalDistanceM = await TrackingService.stopTracking();
      final totalDistanceKm = totalDistanceM / 1000;

      // Step 2: Stop timers
      _durationTimer?.cancel();
      _syncTimer?.cancel();

      // Step 3: Get final location
      final position = await TrackingService.getCurrentLocation();
      
      String? address;
      if (position != null) {
        try {
          address = await GeocodingService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          _logger.w('Failed to get end address: $e');
        }
      }

      // Step 4: Sync any remaining points
      await _syncPendingLocations();

      // Step 5: End session in backend
      final endedSession = await _sessionRepository.stopSession(
        _state.session!.id,
        position?.latitude,
        position?.longitude,
        totalDistanceKm,
        address: address,
      );

      // Calculate final duration from start time to ensure accuracy
      final startTime = _preferences.getSessionStartTime() ?? _state.session?.startTime ?? DateTime.now();
      final finalDuration = DateTime.now().difference(startTime);

      // Step 6: Clear local session
      await _preferences.clearActiveSession();

      // Step 7: Stop notification scheduler with summary
      if (_notificationScheduler != null) {
        await _notificationScheduler!.stopMonitoring(
          totalKm: totalDistanceKm,
          totalDuration: finalDuration,
        );
      }

      // Update state
      _updateState(const ManagerSessionState(status: ManagerSessionStatus.idle));

      _logger.i('Session stopped. Distance: ${totalDistanceKm.toStringAsFixed(2)} km');
      return endedSession;
    } catch (e) {
      _logger.e('Error stopping session: $e');
      _updateState(_state.copyWith(
        status: ManagerSessionStatus.error,
        errorMessage: 'Error stopping session: $e',
      ));
      return null;
    }
  }

  // ============================================================
  // RESUME SESSION (after app restart)
  // ============================================================

  Future<void> _resumeSession(SessionModel session) async {
    try {
      // Get persisted start time (more accurate for timer)
      final persistedStart = _preferences.getSessionStartTime();
      final startTime = persistedStart ?? session.startTime;
      
      _updateState(ManagerSessionState(
        status: ManagerSessionStatus.active,
        session: session,
        currentDistanceMeters: session.totalKm * 1000,
        duration: DateTime.now().difference(startTime),
      ));

      _startDurationTimer(startTime);
      _startSyncTimer();

      _logger.i('Session resumed: ${session.id}');
    } catch (e) {
      _logger.e('Error resuming session: $e');
    }
  }

  // ============================================================
  // LOCATION UPDATES
  // ============================================================

  void _onLocationUpdate(LocationUpdate update) {
    if (_state.status != ManagerSessionStatus.active) return;

    // Queue location for sync
    _queueLocation(update);

    // Forward to notification scheduler for distance-based notifications
    if (_notificationScheduler != null) {
      _notificationScheduler!.onLocationUpdate(
        update.totalDistance / 1000, // Convert to km
        _state.duration,
      );
    }

    // Update state
    _updateState(_state.copyWith(
      currentDistanceMeters: update.totalDistance,
      lastLocation: update,
    ));
  }

  void _onTrackingError(String error) {
    _logger.e('Tracking error: $error');
    
    if (_state.status == ManagerSessionStatus.active) {
      _updateState(_state.copyWith(
        warnings: [..._state.warnings, error],
      ));
    }
  }

  void _onTrackingStateChanged(bool isTracking) {
    _logger.i('Tracking state changed: $isTracking');
    
    if (!isTracking && _state.status == ManagerSessionStatus.active) {
      // Tracking stopped unexpectedly - try to restart
      _logger.w('Tracking stopped unexpectedly, attempting restart...');
      _attemptTrackingRestart();
    }
  }

  Future<void> _attemptTrackingRestart() async {
    if (_state.session == null) return;

    try {
      await Future.delayed(const Duration(seconds: 2));
      
      if (_state.status == ManagerSessionStatus.active) {
        final started = await TrackingService.startTracking(_state.session!.id);
        if (started) {
          _logger.i('Tracking restarted successfully');
        } else {
          _logger.e('Failed to restart tracking');
        }
      }
    } catch (e) {
      _logger.e('Error restarting tracking: $e');
    }
  }

  // ============================================================
  // LOCATION QUEUE & SYNC
  // ============================================================

  Future<void> _queueLocation(LocationUpdate update) async {
    try {
      final point = LocationPointModel.create(
        id: _uuid.v4(),
        sessionId: update.sessionId ?? _state.session?.id ?? '',
        employeeId: _state.session?.employeeId ?? '',
        latitude: update.latitude,
        longitude: update.longitude,
        accuracy: update.accuracy,
        speed: update.speed,
        altitude: update.altitude,
        heading: update.heading,
        isMoving: update.isMoving,
      );

      await _locationRepository.queueLocation(point);
    } catch (e) {
      _logger.e('Error queueing location: $e');
    }
  }

  Future<void> _syncPendingLocations() async {
    try {
      final uploadedCount = await _locationRepository.uploadPendingLocations();
      _logger.i('Sync completed. Uploaded $uploadedCount points.');

      await _preferences.saveLastSyncTime(DateTime.now());
      _logger.i('Sync completed');
    } catch (e) {
      _logger.e('Error syncing locations: $e');
    }
  }

  // ============================================================
  // TIMERS
  // ============================================================

  void _startDurationTimer(DateTime startTime) {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.status == ManagerSessionStatus.active) {
        _updateState(_state.copyWith(
          duration: DateTime.now().difference(startTime),
        ));
      }
    });
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _syncPendingLocations();
    });
  }

  // ============================================================
  // STATE MANAGEMENT
  // ============================================================

  void _updateState(ManagerSessionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  void dispose() {
    _durationTimer?.cancel();
    _syncTimer?.cancel();
    _stateController.close();
  }
}
